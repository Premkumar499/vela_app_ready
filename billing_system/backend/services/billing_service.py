"""
BillingService – Supabase-backed bill storage.
Bills are saved to erp_billing_system + erp_billing_system_items tables.
Products and customers are still loaded from Supabase on startup.
"""

import os
import threading
from datetime import datetime
from typing import Optional

from config import Config
from models.product import Product
from models.customer import Customer
from models.bill import Bill, BillItem
from services.sample_data import SAMPLE_PRODUCTS, SAMPLE_CUSTOMERS


def _amount_in_words(amount: float) -> str:
    """Convert a rupee amount to words, e.g. 1379.71 → 'One Thousand Three Hundred Seventy Nine Rupees and Seventy One Paise Only'"""
    ones = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine',
            'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen',
            'Seventeen', 'Eighteen', 'Nineteen']
    tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety']

    def _words(n: int) -> str:
        if n == 0:
            return ''
        elif n < 20:
            return ones[n]
        elif n < 100:
            return tens[n // 10] + ((' ' + ones[n % 10]) if n % 10 else '')
        elif n < 1000:
            return ones[n // 100] + ' Hundred' + ((' ' + _words(n % 100)) if n % 100 else '')
        elif n < 100000:
            return _words(n // 1000) + ' Thousand' + ((' ' + _words(n % 1000)) if n % 1000 else '')
        elif n < 10000000:
            return _words(n // 100000) + ' Lakh' + ((' ' + _words(n % 100000)) if n % 100000 else '')
        else:
            return _words(n // 10000000) + ' Crore' + ((' ' + _words(n % 10000000)) if n % 10000000 else '')

    rupees = int(amount)
    paise  = round((amount - rupees) * 100)

    # Handle rounding carry-over (e.g. 100.999 → paise == 100 → roll into rupees)
    if paise == 100:
        rupees += 1
        paise = 0

    rupee_word = 'Rupee' if rupees == 1 else 'Rupees'
    result = (_words(rupees) + ' ' + rupee_word) if rupees else ''
    if paise:
        paise_word = 'Paisa' if paise == 1 else 'Paise'
        result += (' and ' if result else '') + _words(paise) + ' ' + paise_word
    return (result + ' Only').strip() if result else 'Zero Rupees Only'


def _get_supabase():
    """Return an authenticated Supabase client."""
    from dotenv import load_dotenv
    from supabase import create_client
    _env_path = os.path.join(os.path.dirname(__file__), "..", ".env")
    load_dotenv(_env_path, override=True)
    url = os.getenv("SUPABASE_URL", "")
    key = (
        os.getenv("SUPABASE_SERVICE_KEY")
        or os.getenv("SUPABASE_SECRET_KEY")
        or ""
    )
    if not url or not key:
        raise ValueError("SUPABASE_URL or key not set in .env")
    return create_client(url, key)


# Cached module-level client. Creating a fresh client per request is expensive;
# the service-role key is static, so a single shared client is safe and avoids
# the N+1 client-creation overhead in get_all_bills / _row_to_bill_dict.
_SUPABASE_CLIENT = None


def _get_supabase_client():
    """Return a cached, shared Supabase client (created once per process)."""
    global _SUPABASE_CLIENT
    if _SUPABASE_CLIENT is None:
        _SUPABASE_CLIENT = _get_supabase()
    return _SUPABASE_CLIENT


def _safe_float(value, default: float = 0.0) -> float:
    """Coerce a payload value to float without raising on None/bad types."""
    try:
        if value is None:
            return default
        if isinstance(value, str):
            value = value.strip()
            if not value:
                return default
        return float(value)
    except (TypeError, ValueError):
        return default


class BillingService:

    def __init__(self) -> None:
        self._lock: threading.Lock = threading.Lock()
        self._products: list[Product] = self._load_products_from_db()
        self._customers: list[Customer] = self._load_customers_from_db()
        self._hour_prefix: str = ""
        self._hour_seq: int = 0
        self._seed_hour_counter()


    # ------------------------------------------------------------------
    # Invoice number  →  2026AUG08A161  (bill 1 at 16:xx),  2026AUG08A172 (bill 2 at 17:xx)
    # Format: YYYY + MMM(upper) + DD + A + HH + sequence(1…n)
    # Sequence resets to 1 every new hour (or on server restart — seeded from DB)
    # ------------------------------------------------------------------

    def _seed_hour_counter(self) -> None:
        """Sync in-memory counter with the highest sequence in DB for the current hour."""
        now = datetime.now()
        prefix = now.strftime("%Y%b%d").upper() + Config.INVOICE_CONSTANT + now.strftime("%H")
        try:
            sb = _get_supabase_client()
            resp = sb.table("erp_billing_system").select("bill_no").execute()
            seqs = [
                int(bn[len(prefix):])
                for row in resp.data
                for bn in [row.get("bill_no", "")]
                if bn.startswith(prefix) and bn[len(prefix):].isdigit()
            ]
            self._hour_prefix = prefix
            self._hour_seq = max(seqs, default=0)
        except Exception:
            self._hour_prefix = prefix
            self._hour_seq = 0

    def _next_bill_number(self) -> str:
        # Lock guards the whole read-modify-write so two concurrent saves in the
        # same hour cannot mint the same bill_no (previously a UNIQUE violation →
        # one sale lost). The DB itself has no sequence for this format, so the
        # in-process lock is the only protection against duplicates.
        with self._lock:
            now = datetime.now()
            current_prefix = now.strftime("%Y%b%d").upper() + Config.INVOICE_CONSTANT + now.strftime("%H")
            # Hour rolled over — re-seed from DB for the new hour
            if current_prefix != self._hour_prefix:
                self._hour_prefix = current_prefix
                self._hour_seq = 0
                self._seed_hour_counter()
            self._hour_seq += 1
            return self._hour_prefix + str(self._hour_seq)


    # ------------------------------------------------------------------
    # Products loader
    # ------------------------------------------------------------------

    def _load_products_from_db(self) -> list[Product]:
        try:
            sb = _get_supabase_client()

            # Expire any stale reservations before loading so stock is accurate
            try:
                sb.rpc("expire_stale_reservations", {}).execute()
            except Exception:
                pass  # Non-fatal

            inv_resp = sb.table("inventory").select("product_id, current_stock").execute()
            stock_map: dict[str, float] = {
                str(r.get("product_id")): _safe_float(r.get("current_stock"))
                for r in inv_resp.data
            }
            resp = sb.table("products").select(
                "product_id, product_name, selling_price, sku, product_image,"
                "categories(name), units(unit_name), brands(brand_name)"
            ).eq("gst_percentage", 0).order("product_name").execute()

            products: list[Product] = []
            for row in resp.data:
                pid = str(row.get("product_id") or "")
                products.append(Product(
                    id=pid,
                    name=row.get("product_name") or "",
                    unit=((row.get("units") or {}).get("unit_name") or "Nos"),
                    price=_safe_float(row.get("selling_price")),
                    mrp=_safe_float(row.get("selling_price")),
                    stock=stock_map.get(pid, 0.0),
                    category=((row.get("categories") or {}).get("name") or "General"),
                    description=" | ".join(filter(None, [
                        str(row.get("sku") or ""),
                        ((row.get("brands") or {}).get("brand_name") or ""),
                    ])),
                    image_url=row.get("product_image") or None,
                ))
            print(f"[BillingService] Loaded {len(products)} products.")
            return products
        except Exception as exc:
            import traceback; traceback.print_exc()
            print(f"[BillingService] Product load failed: {exc}")
            return list(SAMPLE_PRODUCTS)


    # ------------------------------------------------------------------
    # Customers loader
    # ------------------------------------------------------------------

    def _load_customers_from_db(self) -> list[Customer]:
        walk_in = Customer(
            id="00000000-0000-0000-0000-000000000000",
            name="Walk-in Customer", phone="", address="", email="", area="General",
        )
        try:
            sb = _get_supabase_client()
            resp = (
                sb.table("customers")
                .select("customer_id, name, phone, email, address")
                .order("name")
                .execute()
            )
            customers: list[Customer] = [walk_in]
            for row in resp.data:
                name = (row.get("name") or "").strip()
                if not name:
                    continue
                customers.append(Customer(
                    id=str(row.get("customer_id") or row.get("id")),
                    name=name,
                    phone=row.get("phone") or "",
                    address=row.get("address") or "",
                    email=row.get("email") or "",
                    area="",
                ))
            print(f"[BillingService] Loaded {len(customers) - 1} customers.")
            return customers
        except Exception as exc:
            import traceback; traceback.print_exc()
            return [walk_in] + list(SAMPLE_CUSTOMERS)


    # ------------------------------------------------------------------
    # Products – public API
    # ------------------------------------------------------------------

    def get_all_products(self) -> list[dict]:
        return [p.to_dict() for p in self._products]

    def get_product_by_id(self, product_id: str) -> Optional[dict]:
        for p in self._products:
            if p.id == str(product_id):
                return p.to_dict()
        return None

    def get_products_by_category(self, category: str) -> list[dict]:
        return [p.to_dict() for p in self._products if p.category.lower() == category.lower()]

    def search_products(self, query: str) -> list[dict]:
        q = query.lower()
        return [p.to_dict() for p in self._products if q in p.name.lower() or q in p.category.lower()]

    def _deduct_stock(self, product_id, quantity: float) -> None:
        for p in self._products:
            if p.id == str(product_id):
                p.stock = max(0.0, p.stock - quantity)
                break

    def _restore_stock(self, product_id, quantity: float) -> None:
        for p in self._products:
            if p.id == str(product_id):
                p.stock += quantity
                break


    # ------------------------------------------------------------------
    # Customers – public API
    # ------------------------------------------------------------------

    def get_all_customers(self) -> list[dict]:
        return [c.to_dict() for c in self._customers]

    def get_customer_by_id(self, customer_id: str) -> Optional[dict]:
        for c in self._customers:
            if c.id == customer_id:
                return c.to_dict()
        return None

    def search_customers(self, query: str) -> list[dict]:
        q = query.lower()
        return [
            c.to_dict() for c in self._customers
            if q in c.name.lower() or q in (c.phone or "") or q in (c.area or "").lower()
        ]

    def create_customer(self, name: str, phone: str = "", email: str = "", address: str = "") -> dict:
        try:
            sb = _get_supabase_client()
            resp = sb.table("customers").insert({
                "name": name,
                "phone": phone or None,
                "email": email or None,
                "address": address or None,
            }).execute()
            row = resp.data[0]
            customer = Customer(
                id=str(row.get("customer_id") or row.get("id")),
                name=row.get("name") or name,
                phone=row.get("phone") or "",
                address=row.get("address") or "",
                email=row.get("email") or "",
            )
            self._customers.append(customer)
            return {"success": True, "data": customer.to_dict()}
        except Exception as exc:
            import traceback; traceback.print_exc()
            return {"success": False, "message": str(exc)}


    # ------------------------------------------------------------------
    # Bills – CREATE (save to Supabase erp_billing_system)
    # ------------------------------------------------------------------

    def create_bill(self, payload: dict) -> dict:
        errors = self._validate_bill_payload(payload)
        if errors:
            return {"success": False, "message": "; ".join(errors)}

        bill_number = self._next_bill_number()
        now = datetime.now()
        items = payload.get("items", [])

        grand_total = round(sum(
            _safe_float(i.get("rate", 0)) * _safe_float(i.get("quantity", 0))
            for i in items
        ), 2)

        bill_header = {
            "business_name":  "VELA AGENCY",
            "bill_no":        bill_number,
            "bill_date":      now.strftime("%Y-%m-%d"),
            "bill_time":      now.strftime("%H:%M:%S"),
            "payment_mode":   payload.get("payment_type", "Cash").upper(),
            "total_items":    len(items),
            "total_quantity": round(sum(_safe_float(i.get("quantity", 0)) for i in items), 2),
            "grand_total":    grand_total,
            # ── Salesman-input fields ──────────────────────────────
            "customer_name":  payload.get("customer_name", "Walk-in Customer"),
            "customer_phone": payload.get("customer_phone", "") or "",
            "sales_type":     payload.get("sales_type", "Retail"),
            "through":        payload.get("through", "") or "",
            "area":           payload.get("area", "") or "",
            "remarks":        payload.get("remarks", "") or "",
            "draft_bill_id":  payload.get("draft_bill_id") or "",
        }

        def _user_line_rows(parent_id: str) -> list[dict]:
            return [
                {
                    "bill_id":     parent_id,
                    "sno":         idx + 1,
                    "description": item.get("product_name", ""),
                    "quantity":    _safe_float(item.get("quantity", 0)),
                    "rate":        _safe_float(item.get("rate", 0)),
                    "amount":      round(
                        _safe_float(item.get("rate", 0)) * _safe_float(item.get("quantity", 0)), 2
                    ),
                    "product_id":  item.get("product_id") or None,
                }
                for idx, item in enumerate(items)
            ]

        # Line rows for company bill (includes unit)
        def _company_line_rows(parent_id: str) -> list[dict]:
            return [
                {
                    "invoice_id":  parent_id,
                    "sno":         idx + 1,
                    "description": item.get("product_name", ""),
                    "unit":        item.get("unit", "Nos"),
                    "quantity":    _safe_float(item.get("quantity", 0)),
                    "rate":        _safe_float(item.get("rate", 0)),
                    "amount":      round(
                        _safe_float(item.get("rate", 0)) * _safe_float(item.get("quantity", 0)), 2
                    ),
                    "product_id":  item.get("product_id") or None,
                }
                for idx, item in enumerate(items)
            ]

        try:
            sb = _get_supabase_client()

            # ── 1. User Bill table ──────────────────────────────────────
            header_resp = sb.table("erp_billing_system").insert(bill_header).execute()
            bill_id = header_resp.data[0]["bill_id"]
            sb.table("erp_billing_system_items").insert(_user_line_rows(bill_id)).execute()
            print(f"[create_bill] User bill saved to DB: {bill_number}")

            # ── 2. Company Bill table ───────────────────────────────────
            company_header = {
                "invoice_no":      bill_number,
                "invoice_date":    now.strftime("%Y-%m-%d"),
                "invoice_time":    now.strftime("%H:%M:%S"),
                "customer_name":   payload.get("customer_name", "Walk-in Customer"),
                "customer_phone":  payload.get("customer_phone", "") or "",
                "payment_mode":    payload.get("payment_type", "Cash"),
                "transaction_id":  bill_number,
                "upi_id":          None,
                "total_amount":    grand_total,
                "amount_in_words": _amount_in_words(grand_total),
                # ── Salesman-input fields ──────────────────────────────
                "sales_type":      payload.get("sales_type", "Retail"),
                "through":         payload.get("through", "") or "",
                "area":            payload.get("area", "") or "",
                "remarks":         payload.get("remarks", "") or "",
                "draft_bill_id":   payload.get("draft_bill_id") or "",
            }
            try:
                company_resp = sb.table("erp_billing_system_company").insert(company_header).execute()
                invoice_id = company_resp.data[0]["invoice_id"]
                sb.table("erp_billing_system_company_items").insert(_company_line_rows(invoice_id)).execute()
                print(f"[create_bill] Company invoice saved to DB: {bill_number}")
            except Exception as company_exc:
                import traceback; traceback.print_exc()
                print(f"[create_bill] WARNING: Company invoice DB insert failed: {company_exc}")

            # ── 3. Complete reservations (stock already deducted at reserve time) ──
            # complete_bill_reservations only decrements reserved_stock;
            # current_stock was already reduced when the reservation was created.
            # IMPORTANT: Do NOT call reserve_stock here — that would double-deduct.
            draft_bill_id = payload.get("draft_bill_id")
            if draft_bill_id:
                try:
                    from services.reservation_service import reservation_service as _rs
                    from services.draft_service import draft_service as _ds
                    rs_result = _rs.complete_bill_reservations(str(draft_bill_id))
                    if rs_result.get("success"):
                        print(f"[create_bill] Reservations completed for draft: {draft_bill_id}")
                    else:
                        print(f"[create_bill] WARNING: complete_bill_reservations: {rs_result.get('message')}")
                    # Mark the bill_drafts row as COMPLETED
                    _ds.complete_draft(str(draft_bill_id))
                except Exception as rs_exc:
                    print(f"[create_bill] WARNING: reservation/draft completion failed: {rs_exc}")
            else:                # No draft_bill_id: bill was saved without going through the reservation
                # flow (e.g. direct API call).  Deduct stock directly using a dedicated
                # RPC so the operation is still atomic and row-locked.
                # This path should be rare in normal POS usage.
                from services.reservation_service import reservation_service as _rs
                tmp_bill_id = f"DIRECT-{bill_number}"
                for item in items:
                    try:
                        pid = item.get("product_id")
                        qty = float(item.get("quantity", 0))
                        if pid and qty > 0:
                            r = _rs.reserve_stock(
                                product_id=str(pid),
                                bill_id=tmp_bill_id,
                                quantity=qty,
                                user_id=None,
                            )
                            if r.get("success"):
                                # Immediately complete so reserved_stock is also cleared
                                _rs.complete_bill_reservations(tmp_bill_id)
                    except Exception:
                        pass  # Non-fatal – stock sync best-effort

            # ── 4. Generate and upload company invoice PDF to bucket ────
            try:
                self._generate_and_upload_company_pdf(bill_number)
                print(f"[create_bill] Company PDF uploaded to bucket: {bill_number}")
            except Exception as pdf_exc:
                import traceback; traceback.print_exc()
                print(f"[create_bill] WARNING: Company PDF generation failed: {pdf_exc}")
                # Non-fatal - bill is already saved, PDF can be regenerated later

            bill = Bill.from_dict({
                **payload,
                "customer_id": 0,  # Not stored in DB, placeholder for model
                "bill_number": bill_number,
                "date": now.isoformat()
            })
            return {
                "success": True,
                "message": "Bill Saved Successfully",
                "bill_number": bill_number,
                "bill": bill.to_dict(),
            }

        except Exception as exc:
            import traceback; traceback.print_exc()
            return {"success": False, "message": f"Failed to save bill: {exc}"}


    # ------------------------------------------------------------------
    # Bills – READ / DELETE (from Supabase)
    # ------------------------------------------------------------------

    def get_all_bills(self) -> list[dict]:
        try:
            sb = _get_supabase_client()
            rows = (
                sb.table("erp_billing_system")
                .select("*, erp_billing_system_items(*)")
                .order("created_at", desc=True)
                .execute()
            ).data
            return [self._row_to_bill_dict(r) for r in rows]
        except Exception as exc:
            print(f"[BillingService] get_all_bills failed: {exc}")
            return []

    def get_bill_by_number(self, bill_number: str) -> Optional[dict]:
        try:
            sb = _get_supabase_client()
            rows = (
                sb.table("erp_billing_system")
                .select("*, erp_billing_system_items(*)")
                .eq("bill_no", bill_number)
                .execute()
            ).data
            return self._row_to_bill_dict(rows[0]) if rows else None
        except Exception as exc:
            print(f"[BillingService] get_bill_by_number failed: {exc}")
            return None

    def delete_bill(self, bill_number: str) -> dict:
        try:
            sb = _get_supabase_client()

            # ── 1. User bill DB (items auto-cascade via FK ON DELETE CASCADE) ──
            user_rows = (
                sb.table("erp_billing_system")
                .select("bill_id")
                .eq("bill_no", bill_number)
                .execute()
            ).data
            if not user_rows:
                return {"success": False, "message": f"Bill {bill_number} not found"}

            sb.table("erp_billing_system").delete().eq("bill_id", user_rows[0]["bill_id"]).execute()
            print(f"[delete_bill] erp_billing_system deleted: {bill_number}")

            # ── 2. Company invoice DB (items auto-cascade via FK ON DELETE CASCADE) ──
            company_rows = (
                sb.table("erp_billing_system_company")
                .select("invoice_id")
                .eq("invoice_no", bill_number)
                .execute()
            ).data
            if company_rows:
                sb.table("erp_billing_system_company").delete().eq("invoice_id", company_rows[0]["invoice_id"]).execute()
                print(f"[delete_bill] erp_billing_system_company deleted: {bill_number}")
            else:
                print(f"[delete_bill] No matching company invoice found for: {bill_number}")

            # ── 3. Delete PDFs from both Storage buckets ─────────────────
            pdf_file = f"{bill_number}.pdf"
            for bucket in ("erp_billing_system", "erp_billing_system_company"):
                try:
                    sb.storage.from_(bucket).remove([pdf_file])
                    print(f"[delete_bill] Storage bucket '{bucket}' removed: {pdf_file}")
                except Exception as bucket_exc:
                    # File may not exist in bucket — not a fatal error
                    print(f"[delete_bill] Storage bucket '{bucket}' skip ({bucket_exc})")

            # ── 4. Release reservations if bill is deleted ────────────────────
            try:
                from services.reservation_service import reservation_service as _rs
                # Try by bill_id (UUID) first, then by bill_no
                _rs.release_bill_reservations(user_rows[0]["bill_id"])
                _rs.release_bill_reservations(bill_number)
            except Exception as rs_exc:
                print(f"[delete_bill] WARNING: reservation release failed: {rs_exc}")

            # ── 5. Re-sync hour counter so next bill continues from real max ──
            self._seed_hour_counter()

            return {"success": True, "message": f"Bill {bill_number} deleted"}
        except Exception as exc:
            import traceback; traceback.print_exc()
            return {"success": False, "message": str(exc)}


    # ------------------------------------------------------------------
    # Helper – Supabase row → Bill dict (same shape Flutter expects)
    # ------------------------------------------------------------------

    def _row_to_bill_dict(self, row: dict) -> dict:
        items_raw = sorted(
            row.get("erp_billing_system_items") or [],
            key=lambda x: x.get("sno", 0)
        )

        # Try to get customer_name and unit from the company invoice table
        company_units: dict[int, str] = {}
        customer_name_from_company = ""
        try:
            sb = _get_supabase_client()
            bill_no = row["bill_no"]
            comp_rows = (
                sb.table("erp_billing_system_company")
                .select("customer_name, erp_billing_system_company_items(sno, unit)")
                .eq("invoice_no", bill_no)
                .execute()
            ).data
            if comp_rows:
                customer_name_from_company = comp_rows[0].get("customer_name") or ""
                for ci in (comp_rows[0].get("erp_billing_system_company_items") or []):
                    company_units[ci.get("sno", 0)] = ci.get("unit") or "Nos"
        except Exception:
            pass

        bill_items = [
            {
                "product_id":   None,
                "product_name": it["description"],
                "unit":         company_units.get(it.get("sno", 0), "Nos"),
                "quantity":     float(it["quantity"]),
                "rate":         float(it["rate"]),
                "total":        float(it["amount"]),
            }
            for it in items_raw
        ]
        grand_total = float(row["grand_total"])
        # erp_billing_system carries the salesman fields (migration 0007);
        # prefer them, falling back to the company table only for legacy rows.
        customer_name = (
            (row.get("customer_name") or "").strip()
            or customer_name_from_company
            or "Walk-in Customer"
        )
        return {
            "bill_number":    row["bill_no"],
            "date":           f"{row['bill_date']}T{row.get('bill_time', '00:00:00')}",
            "customer_id":    0,
            "customer_name":  customer_name,
            "customer_phone": (row.get("customer_phone") or "").strip(),
            "payment_type":   row.get("payment_mode", "Cash"),
            "sales_type":     row.get("sales_type", "Retail"),
            "through":        (row.get("through") or "").strip(),
            "area":           (row.get("area") or "").strip(),
            "price_list":     "Retail",
            "remarks":        (row.get("remarks") or "").strip(),
            "items":          bill_items,
            "subtotal":       grand_total,
            "grand_total":    grand_total,
            "gst_total":      0.0,
            "round_off":      0.0,
            "gst_breakup":    {},
            "item_count":     row.get("total_items", len(bill_items)),
        }


    # ------------------------------------------------------------------
    # Dashboard summary
    # ------------------------------------------------------------------

    def get_dashboard_summary(self) -> dict:
        try:
            sb = _get_supabase_client()
            resp = sb.table("erp_billing_system").select("grand_total").execute()
            total_sales = sum(float(r["grand_total"]) for r in resp.data)
            total_bills = len(resp.data)
        except Exception:
            total_sales, total_bills = 0.0, 0
        return {
            "total_bills":     total_bills,
            "total_sales":     round(total_sales, 2),
            "total_products":  len(self._products),
            "total_customers": len(self._customers),
        }

    # ------------------------------------------------------------------
    # Company PDF Generation and Upload
    # ------------------------------------------------------------------

    def _generate_and_upload_company_pdf(self, bill_number: str) -> None:
        """
        Generate company invoice PDF from DB and upload to erp_billing_system_company bucket.
        This is called automatically after bill creation.
        """
        # Import here to avoid circular imports
        from routes.invoice_export import _generate_company_invoice_pdf
        
        pdf_bytes = _generate_company_invoice_pdf(bill_number)
        file_name = f"{bill_number}.pdf"
        
        sb = _get_supabase_client()
        sb.storage.from_("erp_billing_system_company").upload(
            path=file_name,
            file=pdf_bytes,
            file_options={"content-type": "application/pdf", "upsert": "true"},
        )
        print(f"[_generate_and_upload_company_pdf] SUCCESS: Uploaded {file_name} to erp_billing_system_company bucket")

    # ------------------------------------------------------------------
    # Validation
    # ------------------------------------------------------------------

    def _validate_bill_payload(self, payload: dict) -> list[str]:
        errors: list[str] = []
        if not isinstance(payload, dict):
            return ["Invalid bill payload"]
        if not payload.get("customer_name"):
            errors.append("customer_name is required")
        items = payload.get("items", [])
        if not isinstance(items, list) or not items:
            errors.append("Bill must contain at least one item")
            return errors
        for idx, item in enumerate(items, start=1):
            if not isinstance(item, dict):
                errors.append(f"Item {idx}: must be an object")
                continue
            if not item.get("product_id"):
                errors.append(f"Item {idx}: product_id is required")
            if _safe_float(item.get("quantity", 0)) <= 0:
                errors.append(f"Item {idx}: quantity must be greater than 0")
            if _safe_float(item.get("rate", 0)) <= 0:
                errors.append(f"Item {idx}: rate must be greater than 0")
        return errors


# Module-level singleton
billing_service = BillingService()

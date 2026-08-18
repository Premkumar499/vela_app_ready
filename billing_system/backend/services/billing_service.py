"""
BillingService – Supabase-backed bill storage.
Bills are saved to erp_billing_system + erp_billing_system_items tables.
Products and customers are still loaded from Supabase on startup.
"""

import os
import threading
from datetime import datetime, timedelta
from decimal import Decimal, ROUND_HALF_UP
from typing import Optional

from config import Config
from models.product import Product
from models.customer import Customer
from models.bill import Bill, BillItem



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

    # Compute rupees and paise in Decimal space (HALF_UP) so e.g. 123.999 → 124.00,
    # never "123 Rupees and 100 Paise".
    money_val = _money(amount)
    rupees = int(money_val)
    paise = int((money_val - rupees) * 100)

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


_MONEY = Decimal("0.01")


def _money(value) -> Decimal:
    """Coerce a value to a 2-decimal money Decimal using HALF_UP rounding.

    All money arithmetic in this service goes through this helper so line
    amounts and the grand total are rounded consistently and the displayed
    TOTAL always equals the sum of the line AMOUNTs (avoids float/banker's
    rounding producing a 1-paise mismatch on printed invoices).
    """
    if value is None:
        return Decimal("0")
    if isinstance(value, Decimal):
        return value.quantize(_MONEY, rounding=ROUND_HALF_UP)
    try:
        return Decimal(str(value)).quantize(_MONEY, rounding=ROUND_HALF_UP)
    except (TypeError, ValueError, ArithmeticError):
        return Decimal("0")


class BillingService:

    def __init__(self) -> None:
        self._lock: threading.Lock = threading.Lock()
        # Defer the network/DB loads until first use so importing the module
        # (and constructing the singleton) does not hit Supabase / slow boot.
        self._products: Optional[list[Product]] = None
        self._customers: Optional[list[Customer]] = None
        self._last_mint_minute: str = ""
        self._seen_bill_numbers: set = set()

    def _ensure_loaded(self) -> None:
        """Lazily load products/customers on first use."""
        if self._products is None:
            self._products = self._load_products_from_db()
        if self._customers is None:
            self._customers = self._load_customers_from_db()


    # ------------------------------------------------------------------
    # Invoice number  →  2026AUG121325A  (bill at 13:25 on 12 AUG 2026)
    # Format: YYYY + MMM(upper) + DD + HHMM (time) + INVOICE_CONSTANT
    # The time component gives each bill a unique number. If two bills are
    # created in the same minute, the number rolls forward minute-by-minute
    # so every bill stays unique.
    # ------------------------------------------------------------------

    def _next_bill_number(self) -> str:
        with self._lock:
            base = datetime.now()
            for _ in range(60):
                candidate = self._format_bill_number(base)
                if candidate not in self._seen_bill_numbers and not self._bill_number_exists(candidate):
                    self._seen_bill_numbers.add(candidate)
                    return candidate
                base += timedelta(minutes=1)
            return self._format_bill_number(datetime.now())

    @staticmethod
    def _format_bill_number(dt: datetime) -> str:
        return dt.strftime("%Y%b%d").upper() + dt.strftime("%H%M") + Config.INVOICE_CONSTANT

    def _bill_number_exists(self, bill_no: str) -> bool:
        try:
            sb = _get_supabase_client()
            resp = sb.table("erp_billing_system").select("bill_no").eq("bill_no", bill_no).limit(1).execute()
            return bool(resp.data)
        except Exception:
            return False


    # ------------------------------------------------------------------
    # Products loader
    # ------------------------------------------------------------------

    def _load_products_from_db(self) -> list[Product]:
        try:
            sb = _get_supabase_client()

            # Expire any stale reservations before loading so stock is accurate
            try:
                from services.reservation_service import reservation_service as _rs
                _rs.expire_stale_reservations()
                _rs.expire_stale_holds(hours=2)
            except Exception:
                pass  # Non-fatal

            inv_resp = sb.table("inventory").select(
                "product_id, current_stock, reserved_stock").execute()
            stock_map: dict[str, float] = {}
            reserved_map: dict[str, float] = {}
            for r in inv_resp.data:
                pid = str(r.get("product_id"))
                stock_map[pid] = _safe_float(r.get("current_stock"))
                reserved_map[pid] = _safe_float(r.get("reserved_stock"))
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
                    reserved=reserved_map.get(pid, 0.0),
                    available_stock=stock_map.get(pid, 0.0) - reserved_map.get(pid, 0.0),
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
            return []


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
            customers: list[Customer] = [walk_in]
            
            # Fetch all customers in batches of 1000 to bypass Supabase default limit
            offset = 0
            limit = 1000
            while True:
                resp = (
                    sb.table("customers")
                    .select("customer_id, name, phone, email, address, area, credit_limit, balance")
                    .order("name")
                    .range(offset, offset + limit - 1)
                    .execute()
                )
                if not resp.data:
                    break
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
                        area=row.get("area") or "",
                        credit_limit=float(row.get("credit_limit") or 0.0),
                        balance=float(row.get("balance") or 0.0),
                    ))
                if len(resp.data) < limit:
                    break
                offset += limit

            print(f"[BillingService] Loaded {len(customers) - 1} customers.")
            return customers
        except Exception as exc:
            import traceback; traceback.print_exc()
            return [walk_in]


    # ------------------------------------------------------------------
    # Products – public API
    # ------------------------------------------------------------------

    def get_all_products(self) -> list[dict]:
        self._ensure_loaded()
        return [p.to_dict() for p in self._products]

    def get_product_by_id(self, product_id: str) -> Optional[dict]:
        self._ensure_loaded()
        for p in self._products:
            if p.id == str(product_id):
                return p.to_dict()
        return None

    def get_products_by_category(self, category: str) -> list[dict]:
        self._ensure_loaded()
        return [p.to_dict() for p in self._products if p.category.lower() == category.lower()]

    def search_products(self, query: str) -> list[dict]:
        self._ensure_loaded()
        q = query.lower()
        return [p.to_dict() for p in self._products if q in p.name.lower() or q in p.category.lower()]

    # ------------------------------------------------------------------
    # Customers – public API
    # ------------------------------------------------------------------

    def get_all_customers(self) -> list[dict]:
        self._ensure_loaded()
        return [c.to_dict() for c in self._customers]

    def get_customer_by_id(self, customer_id: str) -> Optional[dict]:
        self._ensure_loaded()
        for c in self._customers:
            if c.id == customer_id:
                return c.to_dict()
        return None

    def search_customers(self, query: str) -> list[dict]:
        self._ensure_loaded()
        q = query.lower()
        return [
            c.to_dict() for c in self._customers
            if q in c.name.lower() or q in (c.phone or "") or q in (c.area or "").lower()
        ]

    def create_customer(self, name: str, phone: str = "", email: str = "", address: str = "") -> dict:
        self._ensure_loaded()
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
                area=row.get("area") or "",
                credit_limit=float(row.get("credit_limit") or 0.0),
                balance=float(row.get("balance") or 0.0),
            )
            if self._customers is not None:
                self._customers.append(customer)
            return {"success": True, "data": customer.to_dict()}
        except Exception as exc:
            import traceback; traceback.print_exc()
            return {"success": False, "message": str(exc)}

    def update_customer(self, customer_id: str, name: str, phone: str = "",
                        email: str = "", address: str = "") -> dict:
        self._ensure_loaded()
        try:
            sb = _get_supabase_client()
            resp = (
                sb.table("customers")
                .update({
                    "name": name,
                    "phone": phone or None,
                    "email": email or None,
                    "address": address or None,
                })
                .eq("customer_id", customer_id)
                .execute()
            )
            if not resp.data:
                return {"success": False, "message": "Customer not found"}
            row = resp.data[0]
            self._customers = None  # force reload on next read
            return {"success": True, "data": Customer(
                id=str(row.get("customer_id") or row.get("id")),
                name=row.get("name") or name,
                phone=row.get("phone") or "",
                address=row.get("address") or "",
                email=row.get("email") or "",
                area=row.get("area") or "",
                credit_limit=float(row.get("credit_limit") or 0.0),
                balance=float(row.get("balance") or 0.0),
            ).to_dict()}
        except Exception as exc:
            import traceback; traceback.print_exc()
            return {"success": False, "message": str(exc)}

    def delete_customer(self, customer_id: str) -> dict:
        self._ensure_loaded()
        try:
            sb = _get_supabase_client()
            resp = (
                sb.table("customers")
                .delete()
                .eq("customer_id", customer_id)
                .execute()
            )
            if not resp.data:
                return {"success": False, "message": "Customer not found"}
            self._customers = None  # force reload on next read
            return {"success": True, "message": "Customer deleted"}
        except Exception as exc:
            import traceback; traceback.print_exc()
            return {"success": False, "message": str(exc)}


    # ------------------------------------------------------------------
    # Products – ADMIN CRUD (Supabase)
    # ------------------------------------------------------------------

    def _find_or_create_ref(self, table: str, name_col: str, name: str) -> str:
        """Find a categories/units/brands row by name; create it if missing."""
        sb = _get_supabase_client()
        # Map table names to their actual primary key column name in the database
        id_col = {
            "categories": "category_id",
            "units": "unit_id",
            "brands": "brand_id"
        }.get(table, "id")

        resp = sb.table(table).select(id_col).eq(name_col, name).limit(1).execute()
        if resp.data:
            return str(resp.data[0][id_col])
        ins = sb.table(table).insert({name_col: name}).execute()
        return str(ins.data[0][id_col])

    def _get_default_warehouse_id(self) -> str:
        try:
            sb = _get_supabase_client()
            resp = sb.table("warehouses").select("warehouse_id").limit(1).execute()
            if resp.data:
                return str(resp.data[0]["warehouse_id"])
        except Exception:
            pass
        return "c1a9b73a-7771-4473-8bce-a96fccc79f97"

    def _reload_products(self) -> None:
        """Force a fresh product load from the DB on the next access."""
        self._products = None
        self._ensure_loaded()

    def create_product(self, name: str, price: float, stock: float,
                       category: str = "General", unit: str = "PCS",
                       sku: str = "") -> dict:
        self._ensure_loaded()
        try:
            sb = _get_supabase_client()
            category_id = self._find_or_create_ref("categories", "name", category or "General")
            unit_id = self._find_or_create_ref("units", "unit_name", unit or "PCS")
            resp = sb.table("products").insert({
                "product_name": name,
                "selling_price": float(price),
                "sku": sku or None,
                "gst_percentage": 0,
                "category_id": category_id,
                "unit_id": unit_id,
            }).execute()
            product_id = str(resp.data[0]["product_id"])
            try:
                sb.table("inventory").insert({
                    "product_id": product_id,
                    "warehouse_id": self._get_default_warehouse_id(),
                    "current_stock": float(stock),
                    "reserved_stock": 0,
                }).execute()
            except Exception as inv_exc:
                print(f"[create_product] WARNING: inventory insert failed: {inv_exc}")
            self._reload_products()
            return {"success": True, "data": self.get_product_by_id(product_id)}
        except Exception as exc:
            import traceback; traceback.print_exc()
            return {"success": False, "message": str(exc)}

    def update_product(self, product_id: str, name: str, price: float,
                       stock: float, category: str = "General",
                       unit: str = "PCS", sku: str = "") -> dict:
        self._ensure_loaded()
        try:
            sb = _get_supabase_client()
            category_id = self._find_or_create_ref("categories", "name", category or "General")
            unit_id = self._find_or_create_ref("units", "unit_name", unit or "PCS")
            resp = (
                sb.table("products")
                .update({
                    "product_name": name,
                    "selling_price": float(price),
                    "sku": sku or None,
                    "category_id": category_id,
                    "unit_id": unit_id,
                })
                .eq("product_id", product_id)
                .execute()
            )
            if not resp.data:
                return {"success": False, "message": "Product not found"}
            # Sync stock into the inventory table (insert row if missing).
            inv = (
                sb.table("inventory")
                .update({"current_stock": float(stock)})
                .eq("product_id", product_id)
                .execute()
            )
            if not inv.data:
                try:
                    sb.table("inventory").insert({
                        "product_id": product_id,
                        "warehouse_id": self._get_default_warehouse_id(),
                        "current_stock": float(stock),
                        "reserved_stock": 0,
                    }).execute()
                except Exception as inv_exc:
                    print(f"[update_product] WARNING: inventory insert failed: {inv_exc}")
            self._reload_products()
            return {"success": True, "data": self.get_product_by_id(product_id)}
        except Exception as exc:
            import traceback; traceback.print_exc()
            return {"success": False, "message": str(exc)}

    def delete_product(self, product_id: str) -> dict:
        self._ensure_loaded()
        try:
            sb = _get_supabase_client()
            # Remove inventory row first (FK safety), then the product itself.
            try:
                sb.table("inventory").delete().eq("product_id", product_id).execute()
            except Exception as inv_exc:
                print(f"[delete_product] WARNING: inventory delete failed: {inv_exc}")
            resp = (
                sb.table("products")
                .delete()
                .eq("product_id", product_id)
                .execute()
            )
            if not resp.data:
                return {"success": False, "message": "Product not found"}
            self._reload_products()
            return {"success": True, "message": "Product deleted"}
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

        self._ensure_loaded()
        bill_number = self._next_bill_number()
        now = datetime.now()
        items = payload.get("items", [])

        # Compute line amounts and the grand total in one pass, rounding each
        # line with HALF_UP so the stored TOTAL always equals the sum of the
        # stored line AMOUNTs (no 1-paise drift on printed invoices).
        line_totals: list[Decimal] = []
        total_quantity = Decimal("0")
        for item in items:
            qty = _money(item.get("quantity", 0))
            rate = _money(item.get("rate", 0))
            line_totals.append((qty * rate).quantize(_MONEY, rounding=ROUND_HALF_UP))
            total_quantity += qty
        grand_total = float(sum(line_totals, Decimal("0")))

        payload_amount_paid = payload.get("amount_paid")
        if payload_amount_paid is None:
            payment_type = payload.get("payment_type", "Cash").upper()
            if payment_type in ("CASH", "UPI"):
                amount_paid = grand_total
            else:
                amount_paid = 0.0
        else:
            amount_paid = float(payload_amount_paid)

        bill_header = {
            "business_name":  "VELA AGENCY",
            "bill_no":        bill_number,
            "bill_date":      now.strftime("%Y-%m-%d"),
            "bill_time":      now.strftime("%H:%M:%S"),
            "payment_mode":   payload.get("payment_type", "Cash").upper(),
            "total_items":    len(items),
            "total_quantity": float(total_quantity),
            "grand_total":    grand_total,
            # ── Salesman-input fields ──────────────────────────────
            "customer_name":  payload.get("customer_name", "Walk-in Customer"),
            "customer_phone": payload.get("customer_phone", "") or "",
            "sales_type":     payload.get("sales_type", "Retail"),
            "through":        payload.get("through", "") or "",
            "area":           payload.get("area", "") or "",
            "remarks":        payload.get("remarks", "") or "",
            "draft_bill_id":  payload.get("draft_bill_id") or "",
            "amount_paid":    amount_paid,
        }

        def _user_line_rows(parent_id: str) -> list[dict]:
            return [
                {
                    "bill_id":     parent_id,
                    "sno":         idx + 1,
                    "description": item.get("product_name", ""),
                    "quantity":    float(_money(item.get("quantity", 0))),
                    "rate":        float(_money(item.get("rate", 0))),
                    "amount":      float(line_totals[idx]),
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
                    "quantity":    float(_money(item.get("quantity", 0))),
                    "rate":        float(_money(item.get("rate", 0))),
                    "amount":      float(line_totals[idx]),
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
                "amount_paid":     amount_paid,
            }
            try:
                company_resp = sb.table("erp_billing_system_company").insert(company_header).execute()
                invoice_id = company_resp.data[0]["invoice_id"]
                sb.table("erp_billing_system_company_items").insert(_company_line_rows(invoice_id)).execute()
                print(f"[create_bill] Company invoice saved to DB: {bill_number}")
            except Exception as company_exc:
                # Never leave a half-saved bill (user row without company row).
                # Roll back the user bill so the DB stays consistent and the
                # caller gets a clear failure they can safely retry.
                import traceback; traceback.print_exc()
                try:
                    sb.table("erp_billing_system").delete().eq("bill_id", bill_id).execute()
                    print(f"[create_bill] ROLLED BACK user bill: {bill_number}")
                except Exception as rb_exc:
                    print(f"[create_bill] Rollback of user bill failed: {rb_exc}")
                raise RuntimeError(f"Company invoice DB insert failed: {company_exc}") from company_exc

            # ── 3. Link holds from the draft to the real bill number ──
            # Holds stay HELD; stock is NOT deducted at save time. Only the
            # stock-out person's release_hold reduces current_stock later.
            draft_bill_id = payload.get("draft_bill_id")
            if draft_bill_id:
                try:
                    from services.reservation_service import reservation_service as _rs
                    from services.draft_service import draft_service as _ds
                    rs_result = _rs.link_holds_to_bill(str(draft_bill_id), bill_number)
                    if rs_result.get("success"):
                        print(f"[create_bill] Holds linked from draft {draft_bill_id} to bill {bill_number}")
                    else:
                        print(f"[create_bill] WARNING: link_holds_to_bill: {rs_result.get('message')}")
                    # Mark the bill_drafts row as COMPLETED
                    _ds.complete_draft(str(draft_bill_id))
                except Exception as rs_exc:
                    print(f"[create_bill] WARNING: hold/draft linking failed: {rs_exc}")
            else:                # No draft_bill_id: bill was saved without going through the
                # draft flow (e.g. direct API call / salesperson push).
                # Create holds keyed to the real bill number so they appear
                # in the reserve table for the stock-out person.
                from services.reservation_service import reservation_service as _rs
                for item in items:
                    try:
                        pid = item.get("product_id")
                        qty = float(item.get("quantity", 0))
                        if pid and qty > 0:
                            _rs.hold_stock(product_id=str(pid), bill_id=bill_number, quantity=qty)
                    except Exception:
                        pass  # Non-fatal – stock hold best-effort

            # ── 4. Generate and upload company invoice PDF to bucket ────
            # Non-fatal: the bill is already saved and can be regenerated via
            # POST /invoice-export/generate-company/<invoice_number>. Surface it
            # as a warning instead of swallowing it silently.
            warnings: list[str] = []
            try:
                is_salesperson_bill = payload.get("is_salesperson_bill", False) or bool(payload.get("through"))
                self._generate_and_upload_company_pdf(bill_number, is_salesperson_bill=is_salesperson_bill)
                print(f"[create_bill] Company PDF uploaded to bucket: {bill_number}")
            except Exception as pdf_exc:
                import traceback; traceback.print_exc()
                print(f"[create_bill] WARNING: Company PDF generation failed: {pdf_exc}")
                warnings.append(f"Company PDF generation failed: {pdf_exc}")

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
                "warnings": warnings,
                "bill": bill.to_dict(),
            }

        except Exception as exc:
            import traceback; traceback.print_exc()
            return {"success": False, "message": f"Failed to save bill: {exc}"}


    # ------------------------------------------------------------------
    # Bills – READ / DELETE (from Supabase)
    # ------------------------------------------------------------------

    def get_all_bills(self, limit: int = 200, offset: int = 0) -> list[dict]:
        try:
            sb = _get_supabase_client()
            rows = (
                sb.table("erp_billing_system")
                .select("*, erp_billing_system_items(*)")
                .order("created_at", desc=True)
                .range(offset, offset + max(limit, 1) - 1)
                .execute()
            ).data
            # Batch-load the company meta (customer_name + line units) in ONE
            # query instead of one query per bill (N+1).
            comp_map = self._company_meta_map([r["bill_no"] for r in rows])
            return [self._row_to_bill_dict(r, comp_map) for r in rows]
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
            if not rows:
                return None
            comp_map = self._company_meta_map([bill_number])
            return self._row_to_bill_dict(rows[0], comp_map)
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
            for bucket in ("erp_billing_system", "erp_billing_system_company", "salesperson_bill", "salesperson_bill_user"):
                try:
                    sb.storage.from_(bucket).remove([pdf_file])
                    print(f"[delete_bill] Storage bucket '{bucket}' removed: {pdf_file}")
                except Exception as bucket_exc:
                    # File may not exist in bucket — not a fatal error
                    print(f"[delete_bill] Storage bucket '{bucket}' skip ({bucket_exc})")

            # ── 4. Cancel holds if bill is deleted (no stock restore) ────
            # Holds never deducted current_stock, so deletion only frees
            # reserved_stock. Already-RELEASED holds stay released.
            try:
                from services.reservation_service import reservation_service as _rs
                # Try by bill_id (UUID) first, then by bill_no
                _rs.cancel_bill_holds(user_rows[0]["bill_id"])
                _rs.cancel_bill_holds(bill_number)
            except Exception as rs_exc:
                print(f"[delete_bill] WARNING: hold cancellation failed: {rs_exc}")

            # ── 5. Allow reusing the freed bill number if minted in this process ──
            self._seen_bill_numbers.discard(bill_number)

            return {"success": True, "message": f"Bill {bill_number} deleted"}
        except Exception as exc:
            import traceback; traceback.print_exc()
            return {"success": False, "message": str(exc)}


    # ------------------------------------------------------------------
    # Helper – Supabase row → Bill dict (same shape Flutter expects)
    # ------------------------------------------------------------------

    def _company_meta_map(self, bill_nos: list[str]) -> dict:
        """
        Fetch customer_name + line units from the company table for a set of
        bill numbers in a single query. Returns {invoice_no: {...}}.
        """
        if not bill_nos:
            return {}
        try:
            sb = _get_supabase_client()
            comp_rows = (
                sb.table("erp_billing_system_company")
                .select("invoice_no, customer_name, erp_billing_system_company_items(sno, unit)")
                .in_("invoice_no", bill_nos)
                .execute()
            ).data
        except Exception as exc:
            print(f"[BillingService] _company_meta_map failed: {exc}")
            return {}

        meta: dict = {}
        for cr in comp_rows:
            units = {
                ci.get("sno", 0): (ci.get("unit") or "Nos")
                for ci in (cr.get("erp_billing_system_company_items") or [])
            }
            meta[cr["invoice_no"]] = {
                "customer_name": cr.get("customer_name") or "",
                "units": units,
            }
        return meta

    def _row_to_bill_dict(self, row: dict, comp_map: Optional[dict] = None) -> dict:
        items_raw = sorted(
            row.get("erp_billing_system_items") or [],
            key=lambda x: x.get("sno", 0)
        )

        # Try to get customer_name and unit from the company invoice table
        company_units: dict[int, str] = {}
        customer_name_from_company = ""
        if comp_map is None:
            comp_map = self._company_meta_map([row["bill_no"]])
        comp = comp_map.get(row["bill_no"], {})
        company_units = comp.get("units", {}) or {}
        customer_name_from_company = comp.get("customer_name", "") or ""

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
            "amount_paid":    float(row.get("amount_paid") or 0.0),
            "balance":        float(row.get("balance") or (grand_total - float(row.get("amount_paid") or 0.0))),
        }


    # ------------------------------------------------------------------
    # Dashboard summary
    # ------------------------------------------------------------------

    def get_dashboard_summary(self) -> dict:
        self._ensure_loaded()
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

    def _generate_and_upload_company_pdf(self, bill_number: str, is_salesperson_bill: bool = False) -> None:
        """
        Generate company invoice PDF from DB and upload to erp_billing_system_company or salesperson_bill bucket.
        This is called automatically after bill creation.
        """
        # Import here to avoid circular imports
        from routes.invoice_export import _generate_company_invoice_pdf, _generate_user_bill_pdf
        
        pdf_bytes = _generate_company_invoice_pdf(bill_number)
        file_name = f"{bill_number}.pdf"
        
        sb = _get_supabase_client()
        
        if is_salesperson_bill:
            # Upload to salesperson_bill (company invoice layout)
            try:
                sb.storage.from_("salesperson_bill").upload(
                    path=file_name,
                    file=pdf_bytes,
                    file_options={"content-type": "application/pdf", "upsert": "true"},
                )
                print(f"[_generate_and_upload_company_pdf] SUCCESS: Uploaded {file_name} to salesperson_bill bucket")
            except Exception as e:
                print(f"[_generate_and_upload_company_pdf] ERROR uploading to salesperson_bill: {e}")
                
            # Upload to salesperson_bill_user (user receipt thermal layout)
            try:
                user_pdf_bytes = _generate_user_bill_pdf(bill_number)
                sb.storage.from_("salesperson_bill_user").upload(
                    path=file_name,
                    file=user_pdf_bytes,
                    file_options={"content-type": "application/pdf", "upsert": "true"},
                )
                print(f"[_generate_and_upload_company_pdf] SUCCESS: Uploaded {file_name} to salesperson_bill_user bucket")
            except Exception as e:
                print(f"[_generate_and_upload_company_pdf] ERROR uploading to salesperson_bill_user: {e}")
        else:
            try:
                sb.storage.from_("erp_billing_system_company").upload(
                    path=file_name,
                    file=pdf_bytes,
                    file_options={"content-type": "application/pdf", "upsert": "true"},
                )
                print(f"[_generate_and_upload_company_pdf] SUCCESS: Uploaded {file_name} to erp_billing_system_company bucket")
            except Exception as e:
                print(f"[_generate_and_upload_company_pdf] ERROR uploading to erp_billing_system_company: {e}")
                
            try:
                user_pdf_bytes = _generate_user_bill_pdf(bill_number)
                sb.storage.from_("erp_billing_system").upload(
                    path=file_name,
                    file=user_pdf_bytes,
                    file_options={"content-type": "application/pdf", "upsert": "true"},
                )
                print(f"[_generate_and_upload_company_pdf] SUCCESS: Uploaded {file_name} to erp_billing_system bucket")
            except Exception as e:
                print(f"[_generate_and_upload_company_pdf] ERROR uploading to erp_billing_system: {e}")

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


# Module-level singleton, created lazily so importing the module (or the Flask
# app) never performs network/DB work at import time.
_billing_service_instance: Optional["BillingService"] = None


def get_billing_service() -> "BillingService":
    global _billing_service_instance
    if _billing_service_instance is None:
        _billing_service_instance = BillingService()
    return _billing_service_instance


# Backwards-compatible module-level singleton. Construction is cheap
# (no network/DB work); lazy loading happens on first use.
billing_service = get_billing_service()

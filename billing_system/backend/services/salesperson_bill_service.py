"""
SalespersonBillService – pushes rows from the salesperson_bills inbox
through the existing create_bill flow.

Flow (manual push, admin-triggered):
    1. Read a PENDING row from salesperson_bills by id.
    2. Resolve each item's product_id by matching product_name.
    3. Call BillingService.create_bill() → writes erp_billing_system
       + erp_billing_system_company and generates BOTH PDFs.
    4. On success, delete the inbox row (bill data is now permanent).
"""

import json
import logging
from datetime import datetime, timezone

logger = logging.getLogger(__name__)


def _get_supabase():
    import os
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


class SalespersonBillService:
    # ------------------------------------------------------------------
    # List the inbox
    # ------------------------------------------------------------------
    def list_pending(self, statuses: list[str] = None) -> list[dict]:
        if statuses is None:
            statuses = ["PENDING"]
        try:
            sb = _get_supabase()
            rows = (
                sb.table("salesperson_bills")
                .select("*")
                .in_("status", statuses)
                .order("created_at", desc=True)
                .execute()
            ).data
            return rows
        except Exception as exc:
            logger.exception("[SalespersonBillService] list_pending failed")
            return []

    # ------------------------------------------------------------------
    # Push a single inbox row → create bill (user + company PDFs)
    # ------------------------------------------------------------------
    def push(self, bill_id: str) -> dict:
        from services.billing_service import billing_service

        try:
            sb = _get_supabase()
            resp = (
                sb.table("salesperson_bills")
                .select("*")
                .eq("id", bill_id)
                .maybe_single()
                .execute()
            )
            row = resp.data
            if not row:
                return {"success": False, "message": f"No inbox row with id {bill_id}"}
            if row.get("status") not in ("PENDING", "ERROR"):
                return {
                    "success": False,
                    "message": f"Inbox row is already {row.get('status')}",
                }

            # Atomically claim the row so a second worker (auto-polling +
            # manual push racing on the same id) cannot double-bill it.
            # We change the status to 'PROCESSED' during the claim to prevent other
            # threads/workers from matching the status and double-processing.
            claimed = (
                sb.table("salesperson_bills")
                .update({"status": "PROCESSED", "updated_at": datetime.now(timezone.utc).isoformat()})
                .eq("id", bill_id)
                .in_("status", ["PENDING", "ERROR"])
                .execute()
            )
            if not claimed.data:
                return {
                    "success": False,
                    "message": f"Inbox row {bill_id} was already claimed by another worker",
                }

            items_raw = row.get("items") or []

            # Inbox rows created by the salesman app store items as a JSON
            # *string* (TEXT column), not a JSONB array. Normalize to a list
            # before iterating, otherwise every character is treated as an item.
            if isinstance(items_raw, str):
                try:
                    items_raw = json.loads(items_raw)
                except (TypeError, ValueError):
                    items_raw = []
            if not isinstance(items_raw, list):
                items_raw = [items_raw] if items_raw else []
            
            # Fetch product details from DB for fallback units and rates
            try:
                products_db = sb.table("products").select("product_id, product_name, selling_price, unit").execute().data or []
            except Exception as pe:
                print(f"[SalespersonBillService] Error fetching products for fallback: {pe}")
                products_db = []

            prod_lookup = {}
            valid_pids = set()
            for p in products_db:
                p_id = p.get("product_id")
                p_name = (p.get("product_name") or "").lower().strip()
                if p_id:
                    prod_lookup[p_id] = p
                    valid_pids.add(str(p_id))
                if p_name:
                    prod_lookup[p_name] = p

            items = []
            missing = []
            for it in items_raw:
                if isinstance(it, str):
                    # Legacy inbox rows store items as plain product names
                    product_name = it
                    product_id = self._resolve_product_id(product_name)
                    db_prod = prod_lookup.get(product_name.lower().strip()) if product_name else None
                    db_unit = db_prod.get("unit") if db_prod else "Nos"
                    db_price = float(db_prod.get("selling_price") or 0.0) if db_prod else 0.0
                    quantity = 1
                    rate = db_price
                    unit = db_unit
                else:
                    product_name = it.get("product_name", "")
                    # Only trust a stored product_id if it truly exists in the
                    # products table (fake ids like "P001" would break the FK).
                    stored_pid = str(it.get("product_id") or "").strip()
                    product_id = (
                        stored_pid if stored_pid in valid_pids
                        else self._resolve_product_id(product_name)
                    )
                    db_prod = prod_lookup.get(product_id) or prod_lookup.get((product_name or "").lower().strip())
                    db_unit = db_prod.get("unit") if db_prod else "Nos"
                    db_price = float(db_prod.get("selling_price") or 0.0) if db_prod else 0.0
                    unit = it.get("unit") or db_unit or "Nos"
                    rate = float(it.get("rate") or it.get("unit_price") or it.get("price") or db_price or 0.0)
                    # Salesman apps may send the key as "quantity" or "qty";
                    # coerce safely and fall back to 1 if neither is usable.
                    qty_raw = it.get("quantity")
                    if qty_raw is None:
                        qty_raw = it.get("qty")
                    try:
                        quantity = float(qty_raw or 0) if qty_raw not in (None, "") else 1.0
                    except (TypeError, ValueError):
                        quantity = 1.0

                if not product_id:
                    missing.append(product_name or "?")
                    continue

                items.append({
                    "product_id":   product_id,
                    "product_name": product_name,
                    "unit":         unit,
                    "quantity":     quantity,
                    "rate":         rate,
                })

            if missing:
                err_msg = "Could not match product(s): " + ", ".join(missing)
                sb.table("salesperson_bills").update({
                    "status": "ERROR",
                    "updated_at": datetime.now(timezone.utc).isoformat()
                }).eq("id", bill_id).execute()
                return {"success": False, "message": err_msg}

            payload = {
                "customer_id":    row.get("customer_id") or 0,
                "customer_name":  row.get("customer_name") or "Walk-in Customer",
                "customer_phone": row.get("customer_phone") or "",
                "payment_type":   row.get("payment_type") or "Cash",
                "sales_type":     row.get("sales_type") or "Retail",
                "through":        row.get("submitted_by") or "",
                "area":           "",
                "remarks":        "",
                "price_list":     row.get("price_list") or "Retail",
                "draft_bill_id":  "",
                "items":          items,
                "is_salesperson_bill": True,
                "amount_paid":    float(row.get("amount_paid") or 0.0),
            }

            result = billing_service.create_bill(payload)
            if not result.get("success"):
                # Mark as ERROR so we don't retry indefinitely
                sb.table("salesperson_bills").update({
                    "status": "ERROR",
                    "updated_at": datetime.now(timezone.utc).isoformat()
                }).eq("id", bill_id).execute()
                return result

            # Bill created → data is permanent in erp_billing_system /
            # erp_billing_system_company. Remove the inbox row.
            sb.table("salesperson_bills").delete().eq("id", bill_id).execute()
            result["deleted_inbox_row"] = True
            result["bill_number"] = result.get("bill_number")
            return result
        except Exception as exc:
            import traceback
            traceback.print_exc()
            logger.exception("[SalespersonBillService] push failed")
            try:
                sb = _get_supabase()
                sb.table("salesperson_bills").update({
                    "status": "ERROR",
                    "updated_at": datetime.now(timezone.utc).isoformat()
                }).eq("id", bill_id).execute()
            except Exception:
                pass
            return {"success": False, "message": f"Failed to push bill: {exc}"}

    def update_payment(self, bill_id: str, amount_paid: float) -> dict:
        """Update amount_paid on a pending salesperson bill."""
        try:
            sb = _get_supabase()
            update_data = {
                "amount_paid": amount_paid,
                "updated_at": datetime.now(timezone.utc).isoformat()
            }
            # Note: Since PostgreSQL generated columns are used, PG automatically
            # recalculates "balance" = "grand_total" - "amount_paid".
            resp = sb.table("salesperson_bills").update(update_data).eq("id", bill_id).execute()
            if not resp.data:
                return {"success": False, "message": f"No salesperson bill with ID {bill_id}"}
            
            return {
                "success": True, 
                "message": "Payment updated successfully", 
                "data": resp.data[0]
            }
        except Exception as exc:
            logger.exception("[SalespersonBillService] update_payment failed")
            return {"success": False, "message": f"Failed to update payment: {exc}"}

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------
    @staticmethod
    def _resolve_product_id(product_name: str) -> str | None:
        """
        Match product_name against the products table.

        Strategy (in order):
          1. exact case-insensitive match on product_name
          2. full-name substring (ilike %name%)
          3. token AND-match (all words of the name appear in product_name)
        """
        if not product_name:
            return None
        name = product_name.strip()
        tokens = [t for t in name.upper().split() if t]
        try:
            sb = _get_supabase()
            resp = (
                sb.table("products")
                .select("product_id, product_name")
                .execute()
            )
            products = resp.data or []

            lowered = name.lower()
            for p in products:
                if (p.get("product_name") or "").lower() == lowered:
                    return str(p["product_id"])

            for p in products:
                if lowered in (p.get("product_name") or "").lower():
                    return str(p["product_id"])

            if tokens:
                candidates = []
                for p in products:
                    pname = (p.get("product_name") or "").upper()
                    if all(t in pname for t in tokens):
                        candidates.append(p)
                if len(candidates) == 1:
                    return str(candidates[0]["product_id"])
                if len(candidates) > 1:
                    return None
        except Exception:
            pass
        return None


# Module-level singleton
salesperson_bill_service = SalespersonBillService()

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
    def list_pending(self) -> list[dict]:
        try:
            sb = _get_supabase()
            rows = (
                sb.table("salesperson_bills")
                .select("*")
                .eq("status", "PENDING")
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
            if row.get("status") != "PENDING":
                return {
                    "success": False,
                    "message": f"Inbox row is already {row.get('status')}",
                }

            items_raw = row.get("items") or []
            items = []
            missing = []
            for it in items_raw:
                product_id = self._resolve_product_id(it.get("product_name"))
                if not product_id:
                    missing.append(it.get("product_name", "?"))
                items.append({
                    "product_id":   product_id,
                    "product_name": it.get("product_name", ""),
                    "unit":         it.get("unit", "Nos"),
                    "quantity":     float(it.get("quantity", 0)),
                    "rate":         float(it.get("rate", 0)),
                })

            if missing:
                return {
                    "success": False,
                    "message": "Could not match product(s): " + ", ".join(missing),
                }

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
            }

            result = billing_service.create_bill(payload)
            if not result.get("success"):
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
            return {"success": False, "message": f"Failed to push bill: {exc}"}

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

"""
ReservationService – stock reservation logic via Supabase RPC.

All stock operations go through PostgreSQL RPCs that use SELECT … FOR UPDATE
row-level locking, making them safe for concurrent access from multiple
ERP applications (NON_GST_ERP and GST_ERP) sharing the same inventory.

Contract:
  source_app = 'NON_GST_ERP'

RPC functions used:
  reserve_stock(p_product_id, p_bill_id, p_user_id, p_source_app, p_quantity)
  release_reservation(p_reservation_id)
  complete_reservation(p_reservation_id)
  release_bill_reservations(p_bill_id, p_source_app)
  complete_bill_reservations(p_bill_id, p_source_app)
  expire_stale_reservations()
  update_reservation(p_reservation_id, p_new_quantity, p_source_app)  [migration 0006]

Hold RPCs (migration 0011 - holds never touch current_stock):
  hold_stock(p_product_id, p_bill_id, p_user_id, p_source_app, p_quantity)
  release_hold(p_reservation_id, p_source_app)          [stock-out action]
  cancel_hold(p_reservation_id, p_source_app)
  update_hold(p_reservation_id, p_new_quantity, p_source_app)
  cancel_bill_holds(p_bill_id, p_source_app)
  expire_stale_holds(p_hours, p_source_app)
  link_holds_to_bill(p_old_bill_id, p_new_bill_id, p_source_app)
"""

import logging
from typing import Optional

logger = logging.getLogger(__name__)

SOURCE_APP = "NON_GST_ERP"


_SUPABASE_CLIENT = None


def _get_supabase():
    global _SUPABASE_CLIENT
    if _SUPABASE_CLIENT is None:
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
        _SUPABASE_CLIENT = create_client(url, key)
    return _SUPABASE_CLIENT


class ReservationService:
    """
    Handles stock reservation lifecycle:
      reserve  → called when product is added to bill
      release  → called when bill is cancelled / product removed
      complete → called when bill is finalized (saved)
    """

    # ------------------------------------------------------------------
    # Reserve stock for one product on a bill
    # ------------------------------------------------------------------
    def reserve_stock(
        self,
        product_id: str,
        bill_id: str,
        quantity: float,
        user_id: Optional[str] = None,
    ) -> dict:
        """
        Atomically reserves `quantity` units of `product_id` for `bill_id`.

        Returns:
          {
            "success": bool,
            "reservation_id": str | None,
            "product_id": str,
            "reserved_quantity": float,
            "remaining_available": float,
            "error_code": str | None,
            "message": str
          }
        """
        return self._rpc_returning_dict("reserve_stock", {
            "p_product_id": product_id,
            "p_bill_id":    bill_id,
            "p_user_id":    user_id or "",
            "p_source_app": SOURCE_APP,
            "p_quantity":   float(quantity),
        })

    # ------------------------------------------------------------------
    # Release a single reservation (e.g. product removed from bill)
    # ------------------------------------------------------------------
    def release_reservation(self, reservation_id: str) -> dict:
        """
        Releases a single ACTIVE reservation and restores stock.
        """
        return self._rpc_returning_dict("release_reservation", {
            "p_reservation_id": reservation_id,
        })

    # ------------------------------------------------------------------
    # Release ALL active reservations for a bill (bill cancelled)
    # ------------------------------------------------------------------
    def release_bill_reservations(self, bill_id: str) -> dict:
        """
        Atomically releases all ACTIVE reservations for a bill.
        Call this when a bill is cancelled or abandoned.
        """
        return self._rpc_returning_dict("release_bill_reservations", {
            "p_bill_id":    bill_id,
            "p_source_app": SOURCE_APP,
        })

    # ------------------------------------------------------------------
    # Complete ALL active reservations for a bill (bill saved/finalized)
    # ------------------------------------------------------------------
    def complete_bill_reservations(self, bill_id: str) -> dict:
        """
        Completes all ACTIVE reservations for a bill.
        reserved_stock is decremented; current_stock stays (already consumed at reserve).
        Call this when a bill is successfully saved.
        """
        return self._rpc_returning_dict("complete_bill_reservations", {
            "p_bill_id":    bill_id,
            "p_source_app": SOURCE_APP,
        })

    # ------------------------------------------------------------------
    # Update an existing ACTIVE reservation to a new quantity (atomic)
    # ------------------------------------------------------------------
    def update_reservation(
        self,
        reservation_id: str,
        new_quantity: float,
    ) -> dict:
        """
        Atomically adjusts an existing ACTIVE reservation to a new quantity.

        Increasing: deducts the delta from current_stock, adds to reserved_stock.
        Decreasing: restores the delta to current_stock, subtracts from reserved_stock.

        This is safer than release + re-reserve because there is no race window
        between the two operations where another app could grab the freed stock.

        Returns:
          {
            "success": bool,
            "reservation_id": str,
            "product_id": str,
            "old_quantity": float,
            "new_quantity": float,
            "remaining_available": float,
            "error_code": str | None,
            "message": str
          }
        """
        return self._rpc_returning_dict("update_reservation", {
            "p_reservation_id": reservation_id,
            "p_new_quantity":   float(new_quantity),
            "p_source_app":     SOURCE_APP,
        })

    # ------------------------------------------------------------------
    # Expire stale reservations (housekeeping)
    # ------------------------------------------------------------------
    def expire_stale_reservations(self) -> dict:
        """
        Expires all ACTIVE reservations past their expires_at timestamp.
        Call this on product list load or periodically.
        """
        result = self._rpc_returning_dict("expire_stale_reservations", {})
        if "expired_count" not in result:
            result["expired_count"] = 0
        return result

    # ------------------------------------------------------------------
    # Hold stock for one product (no current_stock deduction) [migration 0011]
    # ------------------------------------------------------------------
    def hold_stock(
        self,
        product_id: str,
        bill_id: str,
        quantity: float,
        user_id: Optional[str] = None,
    ) -> dict:
        """
        Holds `quantity` units of `product_id` for `bill_id`.
        Only reserved_stock increases; current_stock stays untouched.
        """
        return self._rpc_returning_dict("hold_stock", {
            "p_product_id": product_id,
            "p_bill_id":    bill_id,
            "p_user_id":    user_id or "",
            "p_source_app": SOURCE_APP,
            "p_quantity":   float(quantity),
        })

    # ------------------------------------------------------------------
    # Release a single hold (stock-out person only) - deducts current_stock
    # ------------------------------------------------------------------
    def release_hold(self, reservation_id: str) -> dict:
        """
        Stock-out action: deducts current_stock AND reserved_stock,
        marks the hold RELEASED. The ONLY place current_stock decreases.
        """
        return self._rpc_returning_dict("release_hold", {
            "p_reservation_id": reservation_id,
            "p_source_app":     SOURCE_APP,
        })

    # ------------------------------------------------------------------
    # Cancel a single hold (no current_stock change)
    # ------------------------------------------------------------------
    def cancel_hold(self, reservation_id: str) -> dict:
        """
        Cancels a HELD reservation; reserved_stock only.
        Used on item removal / draft cancel.
        """
        return self._rpc_returning_dict("cancel_hold", {
            "p_reservation_id": reservation_id,
            "p_source_app":     SOURCE_APP,
        })

    # ------------------------------------------------------------------
    # Update a hold quantity (delta on reserved_stock only)
    # ------------------------------------------------------------------
    def update_hold(
        self,
        reservation_id: str,
        new_quantity: float,
    ) -> dict:
        """
        Atomically adjusts a HELD reservation's quantity.
        Delta applies to reserved_stock only; current_stock never moves.
        """
        return self._rpc_returning_dict("update_hold", {
            "p_reservation_id": reservation_id,
            "p_new_quantity":   float(new_quantity),
            "p_source_app":     SOURCE_APP,
        })

    # ------------------------------------------------------------------
    # Cancel all holds of one bill (bill cancelled / deleted)
    # ------------------------------------------------------------------
    def cancel_bill_holds(self, bill_id: str) -> dict:
        """
        Cancels all HELD reservations for a bill.
        No current_stock change; reserved_stock only.
        """
        return self._rpc_returning_dict("cancel_bill_holds", {
            "p_bill_id":    bill_id,
            "p_source_app": SOURCE_APP,
        })

    # ------------------------------------------------------------------
    # Link holds from draft id to the real bill number (bill saved)
    # ------------------------------------------------------------------
    def link_holds_to_bill(self, old_bill_id: str, new_bill_id: str) -> dict:
        """
        Renames HELD reservations from the DRAFT-* id to the saved
        bill number so they appear in the reserve table.
        """
        return self._rpc_returning_dict("link_holds_to_bill", {
            "p_old_bill_id": old_bill_id,
            "p_new_bill_id": new_bill_id,
            "p_source_app":  SOURCE_APP,
        })

    # ------------------------------------------------------------------
    # Expire stale draft holds (housekeeping) [migration 0011]
    # ------------------------------------------------------------------
    def expire_stale_holds(self, hours: float = 2) -> dict:
        """
        Cancels abandoned DRAFT-* HELD reservations older than `hours`.
        Real-bill holds never expire.
        """
        return self._rpc_returning_dict("expire_stale_holds", {
            "p_hours":      float(hours),
            "p_source_app": SOURCE_APP,
        })

    # ------------------------------------------------------------------
    # Reserve table: all HELD reservations grouped by bill
    # ------------------------------------------------------------------
    def get_held_reservations(self) -> dict:
        """
        Returns the reserve table: HELD reservations (NON_GST_ERP only)
        grouped by bill, joined with product names and company bill info.
        """
        try:
            holds_resp = self._execute_with_retry(
                lambda sb: sb.table("stock_reservations")
                .select("id, product_id, bill_id, quantity, reserved_at")
                .eq("status", "HELD")
                .eq("source_app", SOURCE_APP)
                .order("reserved_at")
                .execute()
            )
            holds = holds_resp.data or []
            if not holds:
                return {"success": True, "count": 0, "data": []}

            product_ids = sorted({str(h["product_id"]) for h in holds})
            prod_resp = self._execute_with_retry(
                lambda sb: sb.table("products")
                .select("product_id, product_name, units(unit_name)")
                .in_("product_id", product_ids)
                .execute()
            )
            prod_rows = prod_resp.data or []
            prod_map = {
                str(r["product_id"]): {
                    "name": r.get("product_name") or "(deleted product)",
                    "unit": ((r.get("units") or {}).get("unit_name") or "Nos"),
                }
                for r in prod_rows
            }

            inv_resp = self._execute_with_retry(
                lambda sb: sb.table("inventory")
                .select("product_id, current_stock, reserved_stock")
                .in_("product_id", product_ids)
                .execute()
            )
            inv_rows = inv_resp.data or []
            inv_map = {
                str(r["product_id"]): {
                    "current":  float(r.get("current_stock") or 0),
                    "reserved": float(r.get("reserved_stock") or 0),
                }
                for r in inv_rows
            }

            bill_ids = sorted({
                h["bill_id"] for h in holds if not h["bill_id"].startswith("DRAFT-")
            })
            bill_map = {}
            if bill_ids:
                comp_resp = self._execute_with_retry(
                    lambda sb: sb.table("erp_billing_system_company")
                    .select("invoice_no, customer_name, customer_phone, payment_mode,"
                            " sales_type, through, area, total_amount, invoice_date, invoice_time")
                    .in_("invoice_no", bill_ids)
                    .execute()
                )
                comp_rows = comp_resp.data or []
                for r in comp_rows:
                    bill_map[str(r["invoice_no"])] = r

            # Group holds by bill, preserving first-reserved order
            groups: list[dict] = []
            seen: dict[str, int] = {}
            for h in holds:
                bill_id = h["bill_id"]
                idx = seen.get(bill_id)
                if idx is None:
                    seen[bill_id] = len(groups)
                    comp = bill_map.get(bill_id, {})
                    groups.append({
                        "bill_number":    bill_id,
                        "customer_name":  comp.get("customer_name") or "",
                        "customer_phone": comp.get("customer_phone") or "",
                        "payment_mode":   comp.get("payment_mode") or "",
                        "sales_type":     comp.get("sales_type") or "",
                        "through":        comp.get("through") or "",
                        "area":           comp.get("area") or "",
                        "total_amount":   float(comp.get("total_amount") or 0),
                        "invoice_date":   str(comp.get("invoice_date") or ""),
                        "invoice_time":   str(comp.get("invoice_time") or ""),
                        "created_at":     h["reserved_at"],
                        "total_quantity": 0.0,
                        "items":          [],
                    })
                g = groups[seen[bill_id]]
                pid = str(h["product_id"])
                inv = inv_map.get(pid, {"current": 0, "reserved": 0})
                g["items"].append({
                    "reservation_id":  str(h["id"]),
                    "product_id":      pid,
                    "name":            prod_map.get(pid, {}).get("name", "(deleted product)"),
                    "unit":            prod_map.get(pid, {}).get("unit", "Nos"),
                    "quantity":        float(h["quantity"]),
                    "reserved_at":     h["reserved_at"],
                    "current_stock":   inv["current"],
                    "reserved_stock":  inv["reserved"],
                    "available_stock": inv["current"] - inv["reserved"],
                })
                g["total_quantity"] += float(h["quantity"])

            return {"success": True, "count": len(groups), "data": groups}
        except Exception as exc:
            logger.exception("[ReservationService] get_held_reservations failed")
            return self._error("RESERVATION_FAILED", str(exc))
    # ------------------------------------------------------------------
    # Get current stock info for a product
    # ------------------------------------------------------------------
    def get_stock_info(self, product_id: str) -> dict:
        """
        Returns live current_stock and reserved_stock from the database.
        """
        try:
            resp = self._execute_with_retry(
                lambda sb: sb.table("inventory").select(
                    "product_id, current_stock, reserved_stock"
                ).eq("product_id", product_id).execute()
            )

            if not resp.data:
                return self._error("PRODUCT_NOT_FOUND", f"Product {product_id} not found in inventory")

            row = resp.data[0]
            return {
                "success":         True,
                "product_id":      str(row["product_id"]),
                "current_stock":   float(row.get("current_stock") or 0),
                "reserved_stock":  float(row.get("reserved_stock") or 0),
            }
        except Exception as exc:
            logger.exception("[ReservationService] get_stock_info failed")
            return self._error("RESERVATION_FAILED", str(exc))

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _unwrap(data) -> dict:
        """
        Supabase RPC functions that RETURN JSON come back as a list
        containing one element (the JSON object).  Unwrap it safely.
        """
        if isinstance(data, list):
            return data[0] if data else {}
        if isinstance(data, dict):
            return data
        return {}

    # ------------------------------------------------------------------
    # Execute a RETURNS JSON RPC and normalise the result into a dict.
    # postgrest-py treats a bare JSON object response (not wrapped in a
    # list) as an "API error" and raises APIError; the real result is
    # actually inside exc.args[0]. Handle both the happy path and that
    # exception path so callers always receive the RPC result dict.
    # ------------------------------------------------------------------
    def _execute_with_retry(self, query_builder_fn, retries=3, delay=1.0):
        """
        Executes a Supabase query builder function with retries on network/HTTP/protocol errors.
        """
        import time
        import httpx
        global _SUPABASE_CLIENT
        last_exc = None
        for attempt in range(retries):
            try:
                return query_builder_fn(_get_supabase())
            except httpx.RequestError as exc:
                last_exc = exc
                logger.warning(
                    "[ReservationService] Database query failed (attempt %d/%d): %s. Clearing cached client and retrying...",
                    attempt + 1, retries, str(exc)
                )
                _SUPABASE_CLIENT = None
                if attempt < retries - 1:
                    time.sleep(delay)
        raise last_exc

    def _rpc_returning_dict(self, rpc_name: str, params: dict) -> dict:
        try:
            result = self._execute_with_retry(lambda sb: sb.rpc(rpc_name, params).execute())
            if result.data is None:
                return {"success": True, "message": "No response from database"}
            return self._unwrap(result.data)
        except Exception as exc:
            if exc.args:
                raw_arg = exc.args[0]
                if isinstance(raw_arg, dict) and 'success' in raw_arg:
                    return raw_arg  # actual RPC result dict
                if isinstance(raw_arg, str) and "'success'" in raw_arg:
                    import ast
                    try:
                        parsed = ast.literal_eval(raw_arg)
                        if isinstance(parsed, dict) and 'success' in parsed:
                            return parsed
                    except Exception:
                        pass

            err_str = str(exc)
            if "PGRST202" in err_str or "no matches found" in err_str.lower():
                logger.warning("[ReservationService] %s RPC not deployed", rpc_name)
                return self._error("RPC_NOT_DEPLOYED",
                    f"{rpc_name} not deployed. Run migration in Supabase SQL Editor.")
            logger.exception("[ReservationService] %s failed", rpc_name)
            return self._error("RESERVATION_FAILED", err_str)

    @staticmethod
    def _error(error_code: str, message: str) -> dict:
        return {
            "success":            False,
            "reservation_id":     None,
            "product_id":         None,
            "reserved_quantity":  0,
            "remaining_available": 0,
            "error_code":         error_code,
            "message":            message,
        }


# Module-level singleton
reservation_service = ReservationService()

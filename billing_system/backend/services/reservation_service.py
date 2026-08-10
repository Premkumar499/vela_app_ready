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
"""

import logging
from typing import Optional

logger = logging.getLogger(__name__)

SOURCE_APP = "NON_GST_ERP"


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
        try:
            sb = _get_supabase()
            result = sb.rpc("reserve_stock", {
                "p_product_id": product_id,
                "p_bill_id":    bill_id,
                "p_user_id":    user_id or "",
                "p_source_app": SOURCE_APP,
                "p_quantity":   float(quantity),
            }).execute()

            if not result.data:
                return self._error("RESERVATION_FAILED", "No response from database")

            return self._unwrap(result.data)

        except Exception as exc:
            logger.exception("[ReservationService] reserve_stock failed")
            return self._error("RESERVATION_FAILED", str(exc))

    # ------------------------------------------------------------------
    # Release a single reservation (e.g. product removed from bill)
    # ------------------------------------------------------------------
    def release_reservation(self, reservation_id: str) -> dict:
        """
        Releases a single ACTIVE reservation and restores stock.
        """
        try:
            sb = _get_supabase()
            result = sb.rpc("release_reservation", {
                "p_reservation_id": reservation_id,
            }).execute()

            if not result.data:
                return self._error("RESERVATION_FAILED", "No response from database")

            return self._unwrap(result.data)

        except Exception as exc:
            logger.exception("[ReservationService] release_reservation failed")
            return self._error("RESERVATION_FAILED", str(exc))

    # ------------------------------------------------------------------
    # Release ALL active reservations for a bill (bill cancelled)
    # ------------------------------------------------------------------
    def release_bill_reservations(self, bill_id: str) -> dict:
        """
        Atomically releases all ACTIVE reservations for a bill.
        Call this when a bill is cancelled or abandoned.
        """
        try:
            sb = _get_supabase()
            result = sb.rpc("release_bill_reservations", {
                "p_bill_id":    bill_id,
                "p_source_app": SOURCE_APP,
            }).execute()

            if not result.data:
                return self._error("RESERVATION_FAILED", "No response from database")

            return self._unwrap(result.data)

        except Exception as exc:
            logger.exception("[ReservationService] release_bill_reservations failed")
            return self._error("RESERVATION_FAILED", str(exc))

    # ------------------------------------------------------------------
    # Complete ALL active reservations for a bill (bill saved/finalized)
    # ------------------------------------------------------------------
    def complete_bill_reservations(self, bill_id: str) -> dict:
        """
        Completes all ACTIVE reservations for a bill.
        reserved_stock is decremented; current_stock stays (already consumed at reserve).
        Call this when a bill is successfully saved.
        """
        try:
            sb = _get_supabase()
            result = sb.rpc("complete_bill_reservations", {
                "p_bill_id":    bill_id,
                "p_source_app": SOURCE_APP,
            }).execute()

            if not result.data:
                return self._error("RESERVATION_FAILED", "No response from database")

            return self._unwrap(result.data)

        except Exception as exc:
            logger.exception("[ReservationService] complete_bill_reservations failed")
            return self._error("RESERVATION_FAILED", str(exc))

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
        try:
            sb = _get_supabase()
            result = sb.rpc("update_reservation", {
                "p_reservation_id": reservation_id,
                "p_new_quantity":   float(new_quantity),
                "p_source_app":     SOURCE_APP,
            }).execute()

            if not result.data:
                return self._error("RESERVATION_FAILED", "No response from database")

            return self._unwrap(result.data)

        except Exception as exc:
            err_str = str(exc)

            # postgrest-py raises APIError when a RETURNS JSON function returns a bare
            # dict (not a list of rows). The actual result is in exc.args[0] as a str.
            if exc.args:
                raw_arg = exc.args[0]
                if isinstance(raw_arg, dict) and 'success' in raw_arg:
                    return raw_arg  # already a dict
                if isinstance(raw_arg, str) and "'success'" in raw_arg:
                    import ast
                    try:
                        parsed = ast.literal_eval(raw_arg)
                        if isinstance(parsed, dict) and 'success' in parsed:
                            return parsed
                    except Exception:
                        pass

            # If the RPC is not deployed, surface a clear message
            if "PGRST202" in err_str or "no matches found" in err_str.lower():
                logger.warning("[ReservationService] update_reservation RPC not deployed")
                return self._error("RPC_NOT_DEPLOYED",
                    "update_reservation not deployed. Run migration 0006 in Supabase SQL Editor.")

            logger.exception("[ReservationService] update_reservation failed")
            return self._error("RESERVATION_FAILED", err_str)

    # ------------------------------------------------------------------
    # Expire stale reservations (housekeeping)
    # ------------------------------------------------------------------
    def expire_stale_reservations(self) -> dict:
        """
        Expires all ACTIVE reservations past their expires_at timestamp.
        Call this on product list load or periodically.
        """
        try:
            sb = _get_supabase()
            result = sb.rpc("expire_stale_reservations", {}).execute()
            if not result.data:
                return {"success": True, "expired_count": 0, "message": "No stale reservations"}
            return self._unwrap(result.data)
        except Exception as exc:
            logger.exception("[ReservationService] expire_stale_reservations failed")
            return {"success": False, "message": str(exc)}

    # ------------------------------------------------------------------
    # Get current stock info for a product
    # ------------------------------------------------------------------
    def get_stock_info(self, product_id: str) -> dict:
        """
        Returns live current_stock and reserved_stock from the database.
        """
        try:
            sb = _get_supabase()
            resp = sb.table("inventory").select(
                "product_id, current_stock, reserved_stock"
            ).eq("product_id", product_id).execute()

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

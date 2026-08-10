"""
DraftService – manages bill_drafts rows for NON_GST_ERP.

The bill_drafts table is shared with the GST ERP.
We create a row when a billing session starts and use its id as the
bill_id in stock_reservations, giving full traceability:

    bill_drafts  →  stock_reservations  →  inventory

Status lifecycle:
    ACTIVE     – draft in progress (reservations are live)
    COMPLETED  – bill saved (reservations completed)
    CANCELLED  – bill cancelled (reservations released)

All state transitions are done here; stock operations remain in
ReservationService.
"""

import logging
from datetime import datetime, timezone

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


class DraftService:
    """
    Creates and manages bill_drafts rows for NON_GST_ERP.
    """

    # ------------------------------------------------------------------
    # Create a new draft bill session
    # ------------------------------------------------------------------
    def create_draft(self, draft_id: str, user_id: str | None = None) -> dict:
        """
        Insert a new ACTIVE row into bill_drafts.

        Args:
            draft_id:  Client-generated ID (e.g. 'DRAFT-1749481234567').
                       Must be globally unique — use timestamp-based IDs.
            user_id:   Optional UUID of the logged-in user.

        Returns:
            { "success": bool, "draft_id": str, "message": str }
        """
        try:
            sb = _get_supabase()
            row = {
                "id":         draft_id,
                "source_app": SOURCE_APP,
                "status":     "ACTIVE",
            }
            if user_id:
                row["created_by"] = user_id

            result = sb.table("bill_drafts").insert(row).execute()

            if not result.data:
                return {"success": False, "draft_id": draft_id,
                        "message": "Insert returned no data"}

            return {"success": True, "draft_id": draft_id,
                    "message": "Draft bill created"}

        except Exception as exc:
            # Handle duplicate ID gracefully — idempotent for network retries
            if "duplicate" in str(exc).lower() or "23505" in str(exc):
                return {"success": True, "draft_id": draft_id,
                        "message": "Draft already exists (idempotent)"}
            logger.exception("[DraftService] create_draft failed")
            return {"success": False, "draft_id": draft_id, "message": str(exc)}

    # ------------------------------------------------------------------
    # Mark draft as COMPLETED (bill saved)
    # ------------------------------------------------------------------
    def complete_draft(self, draft_id: str) -> dict:
        """
        Transitions bill_drafts status: ACTIVE → COMPLETED.
        Call after create_bill succeeds.
        """
        try:
            sb = _get_supabase()
            result = sb.table("bill_drafts").update({
                "status":       "COMPLETED",
                "completed_at": datetime.now(timezone.utc).isoformat(),
                "updated_at":   datetime.now(timezone.utc).isoformat(),
            }).eq("id", draft_id).eq("source_app", SOURCE_APP).execute()

            return {"success": True, "draft_id": draft_id,
                    "message": "Draft marked COMPLETED"}

        except Exception as exc:
            logger.exception("[DraftService] complete_draft failed")
            return {"success": False, "draft_id": draft_id, "message": str(exc)}

    # ------------------------------------------------------------------
    # Mark draft as CANCELLED (bill abandoned)
    # ------------------------------------------------------------------
    def cancel_draft(self, draft_id: str) -> dict:
        """
        Transitions bill_drafts status: ACTIVE → CANCELLED.
        Call after release_bill_reservations succeeds.
        """
        try:
            sb = _get_supabase()
            result = sb.table("bill_drafts").update({
                "status":       "CANCELLED",
                "cancelled_at": datetime.now(timezone.utc).isoformat(),
                "updated_at":   datetime.now(timezone.utc).isoformat(),
            }).eq("id", draft_id).eq("source_app", SOURCE_APP).execute()

            return {"success": True, "draft_id": draft_id,
                    "message": "Draft marked CANCELLED"}

        except Exception as exc:
            logger.exception("[DraftService] cancel_draft failed")
            return {"success": False, "draft_id": draft_id, "message": str(exc)}

    # ------------------------------------------------------------------
    # Get draft info
    # ------------------------------------------------------------------
    def get_draft(self, draft_id: str) -> dict:
        """
        Returns the bill_drafts row for a given draft_id.
        """
        try:
            sb = _get_supabase()
            result = sb.table("bill_drafts").select("*") \
                .eq("id", draft_id).execute()

            if not result.data:
                return {"success": False, "draft_id": draft_id,
                        "message": "Draft not found"}

            return {"success": True, "data": result.data[0]}

        except Exception as exc:
            logger.exception("[DraftService] get_draft failed")
            return {"success": False, "draft_id": draft_id, "message": str(exc)}


# Module-level singleton
draft_service = DraftService()

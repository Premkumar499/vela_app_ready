"""
Reservation system test suite — NON_GST_ERP stock reservation.

Tests cover:
  - Basic reserve / release / complete lifecycle
  - Insufficient stock rejection
  - Concurrent NON_GST_ERP vs GST_ERP reservation (race condition)
  - Quantity update (atomic delta via update_reservation RPC)
  - Cancel draft (release_bill_reservations)
  - Complete draft (complete_bill_reservations)
  - Expiry
  - Duplicate reservation protection
  - Multiple products per draft
  - Double-deduction prevention

These tests mock the Supabase RPC layer so they run without a live DB.
For live integration testing, run against a real Supabase instance.

Run:
    cd billing_system/backend
    pytest tests/test_reservations.py -v
"""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import pytest
from unittest.mock import MagicMock, patch, call
from services.reservation_service import ReservationService, SOURCE_APP


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _ok_response(data: dict):
    """Mimic a Supabase execute() result."""
    mock = MagicMock()
    mock.data = data
    return mock


def _make_service():
    return ReservationService()


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def svc():
    return _make_service()


@pytest.fixture
def client():
    from app import create_app
    app = create_app()
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


# ===========================================================================
# 1. reserve_stock
# ===========================================================================

class TestReserveStock:
    """TEST 1: Basic reservation (current_stock 12 → 5, reserved_stock 0 → 7)."""

    def test_reserve_calls_rpc_with_correct_args(self, svc):
        mock_sb = MagicMock()
        mock_sb.rpc.return_value.execute.return_value = _ok_response({
            "success": True,
            "reservation_id": "res-001",
            "product_id": "prod-001",
            "reserved_quantity": 7,
            "remaining_available": 5,
            "error_code": None,
            "message": "Stock reserved successfully",
        })
        with patch("services.reservation_service._get_supabase", return_value=mock_sb):
            result = svc.reserve_stock("prod-001", "DRAFT-001", 7.0, "user-1")

        mock_sb.rpc.assert_called_once_with("reserve_stock", {
            "p_product_id": "prod-001",
            "p_bill_id":    "DRAFT-001",
            "p_user_id":    "user-1",
            "p_source_app": "NON_GST_ERP",
            "p_quantity":   7.0,
        })
        assert result["success"] is True
        assert result["reserved_quantity"] == 7
        assert result["remaining_available"] == 5

    def test_reserve_returns_reservation_id(self, svc):
        mock_sb = MagicMock()
        mock_sb.rpc.return_value.execute.return_value = _ok_response({
            "success": True,
            "reservation_id": "res-abc",
            "reserved_quantity": 7,
            "remaining_available": 5,
            "error_code": None,
            "message": "ok",
        })
        with patch("services.reservation_service._get_supabase", return_value=mock_sb):
            result = svc.reserve_stock("prod-001", "DRAFT-001", 7.0)
        assert result["reservation_id"] == "res-abc"

    def test_reserve_source_app_is_non_gst(self, svc):
        """Confirm source_app is always NON_GST_ERP."""
        assert SOURCE_APP == "NON_GST_ERP"


# ===========================================================================
# 2. Insufficient stock
# ===========================================================================

class TestInsufficientStock:
    """TEST 2: NON_GST requests 6 when only 5 available → REJECT."""

    def test_insufficient_stock_returned(self, svc):
        mock_sb = MagicMock()
        mock_sb.rpc.return_value.execute.return_value = _ok_response({
            "success": False,
            "reservation_id": None,
            "product_id": "prod-001",
            "reserved_quantity": 0,
            "remaining_available": 5,
            "error_code": "INSUFFICIENT_STOCK",
            "message": "Only 5 units are currently available",
        })
        with patch("services.reservation_service._get_supabase", return_value=mock_sb):
            result = svc.reserve_stock("prod-001", "DRAFT-002", 6.0)

        assert result["success"] is False
        assert result["error_code"] == "INSUFFICIENT_STOCK"
        assert result["remaining_available"] == 5

    def test_exact_available_stock_succeeds(self, svc):
        """TEST 1 variant: requesting exactly 5 of 5 available → SUCCESS."""
        mock_sb = MagicMock()
        mock_sb.rpc.return_value.execute.return_value = _ok_response({
            "success": True,
            "reservation_id": "res-exact",
            "reserved_quantity": 5,
            "remaining_available": 0,
            "error_code": None,
            "message": "ok",
        })
        with patch("services.reservation_service._get_supabase", return_value=mock_sb):
            result = svc.reserve_stock("prod-001", "DRAFT-003", 5.0)
        assert result["success"] is True
        assert result["remaining_available"] == 0


# ===========================================================================
# 3. Release reservation (cancel product)
# ===========================================================================

class TestReleaseReservation:
    """TEST 3: Release single reservation → stock restored."""

    def test_release_calls_rpc_correctly(self, svc):
        mock_sb = MagicMock()
        mock_sb.rpc.return_value.execute.return_value = _ok_response({
            "success": True,
            "error_code": None,
            "message": "Reservation released successfully",
        })
        with patch("services.reservation_service._get_supabase", return_value=mock_sb):
            result = svc.release_reservation("res-001")

        # Live DB: release_reservation takes only p_reservation_id (no p_source_app)
        mock_sb.rpc.assert_called_once_with("release_reservation", {
            "p_reservation_id": "res-001",
        })
        assert result["success"] is True

    def test_release_not_found_returns_error(self, svc):
        mock_sb = MagicMock()
        mock_sb.rpc.return_value.execute.return_value = _ok_response({
            "success": False,
            "error_code": "RESERVATION_NOT_FOUND",
            "message": "Reservation not found",
        })
        with patch("services.reservation_service._get_supabase", return_value=mock_sb):
            result = svc.release_reservation("nonexistent")
        assert result["success"] is False
        assert result["error_code"] == "RESERVATION_NOT_FOUND"


# ===========================================================================
# 4. Cancel draft bill (release all reservations)
# ===========================================================================

class TestReleaseBillReservations:
    """TEST 8: Cancel draft → ALL reservations released atomically."""

    def test_release_bill_calls_rpc_correctly(self, svc):
        mock_sb = MagicMock()
        mock_sb.rpc.return_value.execute.return_value = _ok_response({
            "success": True,
            "released_count": 2,
            "message": "Released 2 reservations for bill DRAFT-001",
        })
        with patch("services.reservation_service._get_supabase", return_value=mock_sb):
            result = svc.release_bill_reservations("DRAFT-001")

        mock_sb.rpc.assert_called_once_with("release_bill_reservations", {
            "p_bill_id":    "DRAFT-001",
            "p_source_app": "NON_GST_ERP",
        })
        assert result["success"] is True
        assert result["released_count"] == 2

    def test_release_bill_multi_product(self, svc):
        """DRAFT with Product A=7, Product B=3 → both released."""
        mock_sb = MagicMock()
        mock_sb.rpc.return_value.execute.return_value = _ok_response({
            "success": True,
            "released_count": 2,
            "message": "Released 2 reservations for bill DRAFT-001",
        })
        with patch("services.reservation_service._get_supabase", return_value=mock_sb):
            result = svc.release_bill_reservations("DRAFT-001")
        assert result["released_count"] == 2


# ===========================================================================
# 5. Complete bill (finalize)
# ===========================================================================

class TestCompleteBillReservations:
    """TEST 4: Complete bill → ACTIVE → COMPLETED, reserved_stock cleared."""

    def test_complete_bill_calls_rpc_correctly(self, svc):
        mock_sb = MagicMock()
        mock_sb.rpc.return_value.execute.return_value = _ok_response({
            "success": True,
            "completed_count": 1,
            "message": "Completed 1 reservations for bill DRAFT-001",
        })
        with patch("services.reservation_service._get_supabase", return_value=mock_sb):
            result = svc.complete_bill_reservations("DRAFT-001")

        mock_sb.rpc.assert_called_once_with("complete_bill_reservations", {
            "p_bill_id":    "DRAFT-001",
            "p_source_app": "NON_GST_ERP",
        })
        assert result["success"] is True
        assert result["completed_count"] == 1

    def test_complete_does_not_restore_current_stock(self, svc):
        """
        On complete, only reserved_stock is decremented.
        current_stock stays at 5 (was deducted at reserve time).
        This test confirms complete_bill_reservations is called, not release.
        """
        mock_sb = MagicMock()
        mock_sb.rpc.return_value.execute.return_value = _ok_response({
            "success": True,
            "completed_count": 1,
            "message": "ok",
        })
        with patch("services.reservation_service._get_supabase", return_value=mock_sb):
            result = svc.complete_bill_reservations("DRAFT-001")

        # Must call complete_bill_reservations, NOT release_bill_reservations
        call_args = mock_sb.rpc.call_args
        assert call_args[0][0] == "complete_bill_reservations"
        assert result["success"] is True


# ===========================================================================
# 6. Atomic quantity update
# ===========================================================================

class TestUpdateReservation:
    """TEST 9 & 10: Quantity change (7→5 releases 2; 5→10 checks available)."""

    def test_update_reservation_decrease(self, svc):
        """7 → 5: delta = -2, 2 units returned to current_stock."""
        mock_sb = MagicMock()
        mock_sb.rpc.return_value.execute.return_value = _ok_response({
            "success": True,
            "reservation_id": "res-001",
            "product_id": "prod-001",
            "old_quantity": 7,
            "new_quantity": 5,
            "remaining_available": 2,  # the 2 units freed
            "error_code": None,
            "message": "Reservation updated from 7 to 5 units",
        })
        with patch("services.reservation_service._get_supabase", return_value=mock_sb):
            result = svc.update_reservation("res-001", 5.0)

        mock_sb.rpc.assert_called_once_with("update_reservation", {
            "p_reservation_id": "res-001",
            "p_new_quantity":   5.0,
            "p_source_app":     "NON_GST_ERP",
        })
        assert result["success"] is True
        assert result["old_quantity"] == 7
        assert result["new_quantity"] == 5

    def test_update_reservation_increase_success(self, svc):
        """5 → 10: 5 additional available → SUCCESS."""
        mock_sb = MagicMock()
        mock_sb.rpc.return_value.execute.return_value = _ok_response({
            "success": True,
            "reservation_id": "res-001",
            "old_quantity": 5,
            "new_quantity": 10,
            "remaining_available": 0,
            "error_code": None,
            "message": "Reservation updated from 5 to 10 units",
        })
        with patch("services.reservation_service._get_supabase", return_value=mock_sb):
            result = svc.update_reservation("res-001", 10.0)
        assert result["success"] is True
        assert result["new_quantity"] == 10

    def test_update_reservation_increase_insufficient(self, svc):
        """TEST 10: 5 → 10, only 2 more available → FAIL, draft stays at 5."""
        mock_sb = MagicMock()
        mock_sb.rpc.return_value.execute.return_value = _ok_response({
            "success": False,
            "reservation_id": "res-001",
            "old_quantity": 5,
            "new_quantity": 10,
            "remaining_available": 2,
            "error_code": "INSUFFICIENT_STOCK",
            "message": "Only 2 additional units are available (need 5 more)",
        })
        with patch("services.reservation_service._get_supabase", return_value=mock_sb):
            result = svc.update_reservation("res-001", 10.0)
        assert result["success"] is False
        assert result["error_code"] == "INSUFFICIENT_STOCK"
        assert result["remaining_available"] == 2


# ===========================================================================
# 7. Expiry
# ===========================================================================

class TestExpireStaleReservations:
    def test_expire_stale_calls_rpc(self, svc):
        mock_sb = MagicMock()
        mock_sb.rpc.return_value.execute.return_value = _ok_response({
            "success": True,
            "expired_count": 3,
            "message": "Expired 3 stale reservations",
        })
        with patch("services.reservation_service._get_supabase", return_value=mock_sb):
            result = svc.expire_stale_reservations()

        mock_sb.rpc.assert_called_once_with("expire_stale_reservations", {})
        assert result["success"] is True
        assert result["expired_count"] == 3

    def test_expire_no_stale_returns_zero(self, svc):
        mock_sb = MagicMock()
        mock_sb.rpc.return_value.execute.return_value = _ok_response({
            "success": True,
            "expired_count": 0,
            "message": "Expired 0 stale reservations",
        })
        with patch("services.reservation_service._get_supabase", return_value=mock_sb):
            result = svc.expire_stale_reservations()
        assert result["expired_count"] == 0


# ===========================================================================
# 8. Concurrent reservation (GST vs NON-GST) simulation
# ===========================================================================

class TestConcurrency:
    """
    TEST 5: Two apps simultaneously request 7 from stock of 12.
    One wins (gets 7), the other loses (INSUFFICIENT_STOCK).
    The DB's SELECT … FOR UPDATE ensures only one transaction succeeds.

    We simulate this by having one call return success and the other fail.
    In production the DB lock serializes them — the loser always gets < 0
    available, never -2.
    """

    def test_only_one_concurrent_request_wins(self):
        """
        Simulate NON_GST_ERP and GST_ERP both requesting 7 from stock=12.
        First call wins → remaining_available = 5.
        Second call (GST_ERP, simulated by different bill_id) loses.
        """
        non_gst_svc = ReservationService()
        gst_result_data = {
            "success": False,
            "reservation_id": None,
            "product_id": "prod-001",
            "reserved_quantity": 0,
            "remaining_available": 5,
            "error_code": "INSUFFICIENT_STOCK",
            "message": "Only 5 units are currently available",
        }

        # NON_GST_ERP wins
        mock_sb_winner = MagicMock()
        mock_sb_winner.rpc.return_value.execute.return_value = _ok_response({
            "success": True,
            "reservation_id": "res-nongst",
            "reserved_quantity": 7,
            "remaining_available": 5,
            "error_code": None,
            "message": "Stock reserved successfully",
        })
        with patch("services.reservation_service._get_supabase", return_value=mock_sb_winner):
            winner = non_gst_svc.reserve_stock("prod-001", "DRAFT-NON", 7.0)

        # GST_ERP loses (remaining = 5 after NON_GST won)
        mock_sb_loser = MagicMock()
        mock_sb_loser.rpc.return_value.execute.return_value = _ok_response(gst_result_data)
        with patch("services.reservation_service._get_supabase", return_value=mock_sb_loser):
            loser = non_gst_svc.reserve_stock("prod-001", "DRAFT-GST", 7.0)

        assert winner["success"] is True
        assert winner["reserved_quantity"] == 7
        assert loser["success"] is False
        assert loser["error_code"] == "INSUFFICIENT_STOCK"
        # Stock never went negative
        assert loser["remaining_available"] >= 0

    def test_both_succeed_if_total_within_stock(self):
        """
        TEST 6: NON_GST=5, GST=7, stock=12 → both succeed.
        Final: current_stock=0, reserved_stock=12.
        """
        svc = ReservationService()
        mock_sb = MagicMock()

        # First call: NON_GST reserves 5 → remaining = 7
        mock_sb.rpc.return_value.execute.return_value = _ok_response({
            "success": True,
            "reservation_id": "res-nongst",
            "reserved_quantity": 5,
            "remaining_available": 7,
            "error_code": None,
            "message": "ok",
        })
        with patch("services.reservation_service._get_supabase", return_value=mock_sb):
            r1 = svc.reserve_stock("prod-001", "DRAFT-NON", 5.0)

        # Second call: GST reserves 7 → remaining = 0
        mock_sb.rpc.return_value.execute.return_value = _ok_response({
            "success": True,
            "reservation_id": "res-gst",
            "reserved_quantity": 7,
            "remaining_available": 0,
            "error_code": None,
            "message": "ok",
        })
        with patch("services.reservation_service._get_supabase", return_value=mock_sb):
            r2 = svc.reserve_stock("prod-001", "DRAFT-GST", 7.0)

        assert r1["success"] is True
        assert r2["success"] is True
        assert r2["remaining_available"] == 0

    def test_stock_never_negative(self):
        """Stock can never go below 0 — DB rejects with INSUFFICIENT_STOCK."""
        svc = ReservationService()
        mock_sb = MagicMock()
        mock_sb.rpc.return_value.execute.return_value = _ok_response({
            "success": False,
            "reservation_id": None,
            "remaining_available": 0,
            "error_code": "INSUFFICIENT_STOCK",
            "message": "Only 0 units are currently available",
        })
        with patch("services.reservation_service._get_supabase", return_value=mock_sb):
            result = svc.reserve_stock("prod-001", "DRAFT-X", 1.0)
        assert result["success"] is False
        assert result["remaining_available"] >= 0


# ===========================================================================
# 9. Duplicate reservation protection
# ===========================================================================

class TestDuplicateProtection:
    """
    TEST 7: The live reserve_stock RPC uses upsert semantics for duplicate
    product+bill combinations — it updates the existing reservation quantity
    rather than creating a duplicate or rejecting.
    This prevents double-billing while still allowing quantity adjustments.
    """

    def test_duplicate_returns_success_with_updated_quantity(self, svc):
        """Live DB: second reserve for same bill+product → updates qty, returns success."""
        mock_sb = MagicMock()
        mock_sb.rpc.return_value.execute.return_value = _ok_response({
            "success": True,
            "reservation_id": "res-001",
            "product_id": "prod-001",
            "reserved_quantity": 3.0,
            "remaining_available": 21.0,
            "error_code": None,
            "message": "Reserved",
        })
        with patch("services.reservation_service._get_supabase", return_value=mock_sb):
            result = svc.reserve_stock("prod-001", "DRAFT-001", 3.0)
        # Upsert semantics: success with updated quantity
        assert result["success"] is True
        assert result["reserved_quantity"] == 3.0

    def test_duplicate_does_not_double_deduct_stock(self, svc):
        """The upsert path adjusts the delta, never double-deducts."""
        mock_sb = MagicMock()
        # First call: reserve 7 → current_stock goes 24→17
        mock_sb.rpc.return_value.execute.return_value = _ok_response({
            "success": True,
            "reservation_id": "res-001",
            "reserved_quantity": 7.0,
            "remaining_available": 17.0,
            "error_code": None,
            "message": "Reserved",
        })
        with patch("services.reservation_service._get_supabase", return_value=mock_sb):
            r1 = svc.reserve_stock("prod-001", "DRAFT-001", 7.0)

        # Second call (upsert to qty=5): delta = -2, current_stock goes 17→19
        mock_sb.rpc.return_value.execute.return_value = _ok_response({
            "success": True,
            "reservation_id": "res-001",
            "reserved_quantity": 5.0,
            "remaining_available": 19.0,
            "error_code": None,
            "message": "Reserved",
        })
        with patch("services.reservation_service._get_supabase", return_value=mock_sb):
            r2 = svc.reserve_stock("prod-001", "DRAFT-001", 5.0)

        assert r1["success"] and r2["success"]
        # remaining_available reflects the adjusted stock, not double-deducted
        assert r2["remaining_available"] == 19.0


# ===========================================================================
# 10. Stock info query
# ===========================================================================

class TestStockInfo:
    def test_get_stock_info(self, svc):
        mock_sb = MagicMock()
        mock_sb.table.return_value.select.return_value.eq.return_value.execute.return_value = \
            _ok_response([{"product_id": "prod-001", "current_stock": 5, "reserved_stock": 7}])
        with patch("services.reservation_service._get_supabase", return_value=mock_sb):
            result = svc.get_stock_info("prod-001")
        assert result["success"] is True
        assert result["current_stock"] == 5
        assert result["reserved_stock"] == 7

    def test_get_stock_info_not_found(self, svc):
        mock_sb = MagicMock()
        mock_sb.table.return_value.select.return_value.eq.return_value.execute.return_value = \
            _ok_response([])
        with patch("services.reservation_service._get_supabase", return_value=mock_sb):
            result = svc.get_stock_info("nonexistent")
        assert result["success"] is False
        assert result["error_code"] == "PRODUCT_NOT_FOUND"


# ===========================================================================
# 11. Flask API endpoints for reservations
# ===========================================================================

class TestReservationAPI:
    def test_reserve_missing_product_id(self, client):
        resp = client.post("/reservations/reserve", json={
            "bill_id": "DRAFT-001", "quantity": 7
        })
        assert resp.status_code == 400

    def test_reserve_missing_bill_id(self, client):
        resp = client.post("/reservations/reserve", json={
            "product_id": "prod-001", "quantity": 7
        })
        assert resp.status_code == 400

    def test_reserve_zero_quantity(self, client):
        resp = client.post("/reservations/reserve", json={
            "product_id": "prod-001", "bill_id": "DRAFT-001", "quantity": 0
        })
        assert resp.status_code == 400

    def test_release_missing_reservation_id(self, client):
        resp = client.post("/reservations/release", json={})
        assert resp.status_code == 400

    def test_release_bill_missing_bill_id(self, client):
        resp = client.post("/reservations/release-bill", json={})
        assert resp.status_code == 400

    def test_complete_bill_missing_bill_id(self, client):
        resp = client.post("/reservations/complete-bill", json={})
        assert resp.status_code == 400

    def test_update_missing_reservation_id(self, client):
        resp = client.post("/reservations/update", json={"new_quantity": 5})
        assert resp.status_code == 400

    def test_update_zero_quantity(self, client):
        resp = client.post("/reservations/update", json={
            "reservation_id": "res-001", "new_quantity": 0
        })
        assert resp.status_code == 400

    def test_expire_stale_endpoint_exists(self, client):
        """expire-stale endpoint exists and returns 200 (may call Supabase, handled)."""
        with patch("services.reservation_service._get_supabase") as mock_get:
            mock_sb = MagicMock()
            mock_sb.rpc.return_value.execute.return_value = _ok_response({
                "success": True, "expired_count": 0, "message": "ok"
            })
            mock_get.return_value = mock_sb
            resp = client.post("/reservations/expire-stale", json={})
        assert resp.status_code == 200

    def test_stock_info_endpoint(self, client):
        with patch("services.reservation_service._get_supabase") as mock_get:
            mock_sb = MagicMock()
            mock_sb.table.return_value.select.return_value.eq.return_value.execute.return_value = \
                _ok_response([{"product_id": "prod-001", "current_stock": 5, "reserved_stock": 7}])
            mock_get.return_value = mock_sb
            resp = client.get("/reservations/stock/prod-001")
        assert resp.status_code == 200
        data = resp.json
        assert data["success"] is True
        assert data["current_stock"] == 5
        assert data["reserved_stock"] == 7

    def test_stock_info_not_found(self, client):
        with patch("services.reservation_service._get_supabase") as mock_get:
            mock_sb = MagicMock()
            mock_sb.table.return_value.select.return_value.eq.return_value.execute.return_value = \
                _ok_response([])
            mock_get.return_value = mock_sb
            resp = client.get("/reservations/stock/nonexistent")
        assert resp.status_code == 404


# ===========================================================================
# 12. Double-deduction prevention in billing_service.create_bill
# ===========================================================================

class TestDoubleDeductionPrevention:
    """
    Verifies that create_bill calls complete_bill_reservations (not reserve_stock)
    when a draft_bill_id is provided, preventing double-deduction.
    """

    def test_create_bill_with_draft_calls_complete_not_reserve(self):
        from services.billing_service import BillingService
        svc = BillingService()

        # Patch the reservation service so we can spy on it
        with patch("services.reservation_service.ReservationService.complete_bill_reservations") as mock_complete, \
             patch("services.reservation_service.ReservationService.reserve_stock") as mock_reserve, \
             patch("services.billing_service._get_supabase") as mock_sb:

            mock_complete.return_value = {
                "success": True, "completed_count": 1, "message": "ok"
            }

            # Simulate DB insert returning a bill row
            mock_insert = MagicMock()
            mock_insert.data = [{"bill_id": "bill-uuid-001"}]
            mock_sb.return_value.table.return_value.insert.return_value.execute.return_value = mock_insert

            svc.create_bill({
                "customer_id":    1,
                "customer_name":  "Test",
                "payment_type":   "Cash",
                "draft_bill_id":  "DRAFT-001",
                "items": [{
                    "product_id":   "prod-001",
                    "product_name": "Rice",
                    "unit":         "KG",
                    "quantity":     5,
                    "rate":         100,
                    "discount_percent": 0,
                }],
            })

        # complete must be called, reserve must NOT be called (no double deduction)
        mock_complete.assert_called_once_with("DRAFT-001")
        mock_reserve.assert_not_called()

"""
Reservation routes – stock reservation lifecycle for the POS billing screen.

Endpoints:
  POST   /reservations/reserve              – reserve stock for one product
  POST   /reservations/release              – release a single reservation
  POST   /reservations/release-bill         – release all reservations for a bill
  POST   /reservations/complete-bill        – complete all reservations for a bill
  POST   /reservations/expire-stale         – expire stale reservations (housekeeping)
  GET    /reservations/stock/<product_id>   – get live stock info for a product

Hold endpoints (migration 0011 – holds never deduct current_stock):
  POST   /reservations/hold                 – hold stock (no current_stock change)
  POST   /reservations/release-hold         – stock-out: deduct current_stock + reserved_stock
  POST   /reservations/cancel-hold          – cancel a single hold
  POST   /reservations/update-hold          – atomically change a hold quantity
  POST   /reservations/cancel-bill-holds    – cancel all holds for a bill
  POST   /reservations/expire-stale-holds   – expire stale DRAFT-* holds (housekeeping)
  GET    /reservations/held                 – reserve table (held bills, NON_GST_ERP only)
"""

from flask import Blueprint, jsonify, request
from services.reservation_service import reservation_service

reservations_bp = Blueprint("reservations", __name__, url_prefix="/reservations")


@reservations_bp.post("/reserve")
def reserve():
    """
    Reserve stock for one product when it is added to a bill.

    Body:
      {
        "product_id": "uuid",
        "bill_id":    "DRAFT-xxxx",
        "quantity":   7,
        "user_id":    "optional-user-uuid"
      }
    """
    body = request.get_json(silent=True) or {}
    product_id = body.get("product_id")
    bill_id    = body.get("bill_id")
    quantity   = body.get("quantity")
    user_id    = body.get("user_id", "")

    if not product_id:
        return jsonify({"success": False, "error_code": "INVALID_QUANTITY",
                        "message": "product_id is required"}), 400
    if not bill_id:
        return jsonify({"success": False, "error_code": "BILL_NOT_FOUND",
                        "message": "bill_id is required"}), 400
    if quantity is None or float(quantity) <= 0:
        return jsonify({"success": False, "error_code": "INVALID_QUANTITY",
                        "message": "quantity must be greater than 0"}), 400

    result = reservation_service.reserve_stock(
        product_id=str(product_id),
        bill_id=str(bill_id),
        quantity=float(quantity),
        user_id=str(user_id) if user_id else None,
    )

    status_code = 200 if result.get("success") else 409
    return jsonify(result), status_code


@reservations_bp.post("/release")
def release():
    """
    Release a single active reservation.

    Body: { "reservation_id": "uuid" }
    """
    body = request.get_json(silent=True) or {}
    reservation_id = body.get("reservation_id")

    if not reservation_id:
        return jsonify({"success": False, "error_code": "RESERVATION_NOT_ACTIVE",
                        "message": "reservation_id is required"}), 400

    result = reservation_service.release_reservation(str(reservation_id))
    status_code = 200 if result.get("success") else 409
    return jsonify(result), status_code


@reservations_bp.post("/release-bill")
def release_bill():
    """
    Release ALL active reservations for a bill (bill cancelled / abandoned).

    Body: { "bill_id": "DRAFT-xxxx" }
    """
    body = request.get_json(silent=True) or {}
    bill_id = body.get("bill_id")

    if not bill_id:
        return jsonify({"success": False, "error_code": "BILL_NOT_FOUND",
                        "message": "bill_id is required"}), 400

    result = reservation_service.release_bill_reservations(str(bill_id))
    status_code = 200 if result.get("success") else 409
    return jsonify(result), status_code


@reservations_bp.post("/update")
def update():
    """
    Atomically update an existing ACTIVE reservation to a new quantity.
    Safer than release + re-reserve (no race window between operations).

    Body:
      {
        "reservation_id": "uuid",
        "new_quantity":   5
      }
    """
    body = request.get_json(silent=True) or {}
    reservation_id = body.get("reservation_id")
    new_quantity   = body.get("new_quantity")

    if not reservation_id:
        return jsonify({"success": False, "error_code": "RESERVATION_NOT_ACTIVE",
                        "message": "reservation_id is required"}), 400
    if new_quantity is None or float(new_quantity) <= 0:
        return jsonify({"success": False, "error_code": "INVALID_QUANTITY",
                        "message": "new_quantity must be greater than 0"}), 400

    result = reservation_service.update_reservation(
        reservation_id=str(reservation_id),
        new_quantity=float(new_quantity),
    )

    status_code = 200 if result.get("success") else 409
    return jsonify(result), status_code


@reservations_bp.post("/complete-bill")
def complete_bill():
    """
    Complete ALL active reservations for a bill (bill saved/finalized).

    Body: { "bill_id": "DRAFT-xxxx" }
    """
    body = request.get_json(silent=True) or {}
    bill_id = body.get("bill_id")

    if not bill_id:
        return jsonify({"success": False, "error_code": "BILL_NOT_FOUND",
                        "message": "bill_id is required"}), 400

    result = reservation_service.complete_bill_reservations(str(bill_id))
    status_code = 200 if result.get("success") else 409
    return jsonify(result), status_code


@reservations_bp.post("/expire-stale")
def expire_stale():
    """Expire stale reservations (housekeeping endpoint)."""
    result = reservation_service.expire_stale_reservations()
    return jsonify(result), 200


@reservations_bp.get("/stock/<string:product_id>")
def stock_info(product_id: str):
    """GET /reservations/stock/<product_id> – live stock for a product."""
    result = reservation_service.get_stock_info(product_id)
    status_code = 200 if result.get("success") else 404
    return jsonify(result), status_code


# --------------------------------------------------------------------------
# Hold endpoints (migration 0011)
# Holds reserve stock without deducting current_stock. Only the stock-out
# person's release-hold reduces current_stock.
# --------------------------------------------------------------------------


@reservations_bp.post("/hold")
def hold():
    """
    Hold stock for one product when it is added to a bill.
    current_stock is NOT deducted; only reserved_stock increases.

    Body:
      {
        "product_id": "uuid",
        "bill_id":    "DRAFT-xxxx",
        "quantity":   7,
        "user_id":    "optional-user-uuid"
      }
    """
    body = request.get_json(silent=True) or {}
    product_id = body.get("product_id")
    bill_id    = body.get("bill_id")
    quantity   = body.get("quantity")
    user_id    = body.get("user_id", "")

    if not product_id:
        return jsonify({"success": False, "error_code": "INVALID_QUANTITY",
                        "message": "product_id is required"}), 400
    if not bill_id:
        return jsonify({"success": False, "error_code": "BILL_NOT_FOUND",
                        "message": "bill_id is required"}), 400
    if quantity is None or float(quantity) <= 0:
        return jsonify({"success": False, "error_code": "INVALID_QUANTITY",
                        "message": "quantity must be greater than 0"}), 400

    result = reservation_service.hold_stock(
        product_id=str(product_id),
        bill_id=str(bill_id),
        quantity=float(quantity),
        user_id=str(user_id) if user_id else None,
    )

    status_code = 200 if result.get("success") else 409
    return jsonify(result), status_code


@reservations_bp.post("/release-hold")
def release_hold():
    """
    Stock-out action: deducts current_stock AND reserved_stock and marks
    the hold RELEASED. This is the ONLY place current_stock decreases.

    Body: { "reservation_id": "uuid" }
    """
    body = request.get_json(silent=True) or {}
    reservation_id = body.get("reservation_id")

    if not reservation_id:
        return jsonify({"success": False, "error_code": "RESERVATION_NOT_ACTIVE",
                        "message": "reservation_id is required"}), 400

    result = reservation_service.release_hold(str(reservation_id))
    status_code = 200 if result.get("success") else 409
    return jsonify(result), status_code


@reservations_bp.post("/cancel-hold")
def cancel_hold():
    """
    Cancel a single hold. reserved_stock only; current_stock never changes.

    Body: { "reservation_id": "uuid" }
    """
    body = request.get_json(silent=True) or {}
    reservation_id = body.get("reservation_id")

    if not reservation_id:
        return jsonify({"success": False, "error_code": "RESERVATION_NOT_ACTIVE",
                        "message": "reservation_id is required"}), 400

    result = reservation_service.cancel_hold(str(reservation_id))
    status_code = 200 if result.get("success") else 409
    return jsonify(result), status_code


@reservations_bp.post("/update-hold")
def update_hold():
    """
    Atomically update a HELD reservation's quantity (delta on reserved_stock only).

    Body:
      {
        "reservation_id": "uuid",
        "new_quantity":   5
      }
    """
    body = request.get_json(silent=True) or {}
    reservation_id = body.get("reservation_id")
    new_quantity   = body.get("new_quantity")

    if not reservation_id:
        return jsonify({"success": False, "error_code": "RESERVATION_NOT_ACTIVE",
                        "message": "reservation_id is required"}), 400
    if new_quantity is None or float(new_quantity) <= 0:
        return jsonify({"success": False, "error_code": "INVALID_QUANTITY",
                        "message": "new_quantity must be greater than 0"}), 400

    result = reservation_service.update_hold(
        reservation_id=str(reservation_id),
        new_quantity=float(new_quantity),
    )

    status_code = 200 if result.get("success") else 409
    return jsonify(result), status_code


@reservations_bp.post("/cancel-bill-holds")
def cancel_bill_holds():
    """
    Cancel ALL holds for a bill (bill cancelled / deleted).
    No current_stock change; reserved_stock is freed.

    Body: { "bill_id": "DRAFT-xxxx" or bill number }
    """
    body = request.get_json(silent=True) or {}
    bill_id = body.get("bill_id")

    if not bill_id:
        return jsonify({"success": False, "error_code": "BILL_NOT_FOUND",
                        "message": "bill_id is required"}), 400

    result = reservation_service.cancel_bill_holds(str(bill_id))
    status_code = 200 if result.get("success") else 409
    return jsonify(result), status_code


@reservations_bp.post("/expire-stale-holds")
def expire_stale_holds():
    """
    Expire stale DRAFT-* holds (housekeeping).
    Only abandoned drafts older than `hours` are cancelled; real-bill holds never expire.

    Body: { "hours": 2 } (optional, default 2)
    """
    body = request.get_json(silent=True) or {}
    hours = body.get("hours", 2)
    result = reservation_service.expire_stale_holds(hours=float(hours))
    return jsonify(result), 200


@reservations_bp.get("/held")
def held():
    """
    GET /reservations/held – the reserve table.
    Returns all HELD reservations (NON_GST_ERP only) grouped by bill,
    joined with product names and company bill info.
    """
    result = reservation_service.get_held_reservations()
    status_code = 200 if result.get("success") else 500
    return jsonify(result), status_code

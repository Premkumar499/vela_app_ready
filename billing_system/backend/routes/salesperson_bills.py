"""
Salesperson bill inbox routes – manual "push to bill" flow.

Endpoints:
  GET  /salesperson-bills              – list PENDING inbox rows
  POST /salesperson-bills/<id>/push    – create user + company bills and
                                          generate both PDFs, then delete the row
"""

from flask import Blueprint, jsonify
from services.salesperson_bill_service import salesperson_bill_service

salesperson_bills_bp = Blueprint("salesperson_bills", __name__, url_prefix="/salesperson-bills")


@salesperson_bills_bp.get("/")
def list_pending():
    """List all PENDING and ERROR bill requests from the salesmen."""
    rows = salesperson_bill_service.list_pending(["PENDING", "ERROR"])
    return jsonify({"success": True, "data": rows}), 200


@salesperson_bills_bp.post("/<string:bill_id>/push")
def push_bill(bill_id: str):
    """
    Push one inbox row through create_bill.

    Creates the user bill (erp_billing_system) and the company bill
    (erp_billing_system_company), generates BOTH PDFs, then deletes
    the inbox row.
    """
    result = salesperson_bill_service.push(bill_id)
    status_code = 200 if result.get("success") else 422
    return jsonify(result), status_code


@salesperson_bills_bp.patch("/<string:bill_id>/payment")
def update_payment(bill_id: str):
    """
    Update the payment amount for a salesperson bill request.
    This calculates the new balance and updates the payment.
    """
    from flask import request
    data = request.json or {}
    amount_paid = data.get("amount_paid")
    if amount_paid is None:
        return jsonify({"success": False, "message": "amount_paid is required"}), 400
    try:
        amount_paid = float(amount_paid)
    except (TypeError, ValueError):
        return jsonify({"success": False, "message": "amount_paid must be a valid number"}), 400

    result = salesperson_bill_service.update_payment(bill_id, amount_paid)
    status_code = 200 if result.get("success") else 422
    return jsonify(result), status_code


@salesperson_bills_bp.patch("/completed/<string:bill_no>/payment")
def update_completed_payment(bill_no: str):
    """
    Update the payment amount for a completed salesperson bill.
    This reconstructs the bill, deletes the old one, and creates a new one with the updated payment.
    """
    from flask import request
    data = request.json or {}
    amount_paid = data.get("amount_paid")
    if amount_paid is None:
        return jsonify({"success": False, "message": "amount_paid is required"}), 400
    try:
        amount_paid = float(amount_paid)
    except (TypeError, ValueError):
        return jsonify({"success": False, "message": "amount_paid must be a valid number"}), 400

    result = salesperson_bill_service.update_completed_payment(bill_no, amount_paid)
    status_code = 200 if result.get("success") else 422
    return jsonify(result), status_code



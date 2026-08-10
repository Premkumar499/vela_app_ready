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
    """List all PENDING bill requests from the salesmen."""
    rows = salesperson_bill_service.list_pending()
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

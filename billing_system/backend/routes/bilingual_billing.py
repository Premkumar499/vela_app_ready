"""
Simplified Bilingual Billing Routes - for Vela Agency Bill System.

NOTE: The /api/bilingual/bills endpoints are utility routes and are not
called by the main Flutter app (which uses the /bill/ and /bills/ routes).
The generate-bill-number endpoint can be used to preview the next bill number.
"""

from flask import Blueprint, jsonify, request
from datetime import datetime

from services.billing_service import billing_service

bilingual_bp = Blueprint("bilingual", __name__, url_prefix="/api/bilingual")


@bilingual_bp.route("/bills", methods=["POST"])
def create_simple_bill():
    """
    Create a simplified bill via the main billing service so it is persisted
    in Supabase (erp_billing_system table) rather than lost in memory.
    """
    try:
        data = request.get_json(silent=True) or {}

        items_raw = data.get("items", [])
        items = []
        for it in items_raw:
            if isinstance(it, dict):
                items.append({
                    "product_id":   it.get("product_id", ""),
                    "product_name": it.get("product_name", it.get("name", "")),
                    "unit":         it.get("unit", "Nos"),
                    "quantity":     float(it.get("quantity", 1)),
                    "rate":         float(it.get("rate", 0)),
                })

        if not items:
            return jsonify({"success": False, "message": "No items provided"}), 400

        payload = {
            "customer_id":   0,
            "customer_name": data.get("customerName", "Walk-in Customer"),
            "payment_type":  data.get("paymentMode", "Cash"),
            "sales_type":    "Retail",
            "through":       "",
            "area":          "",
            "remarks":       "",
            "price_list":    "Retail",
            "items":         items,
        }

        result = billing_service.create_bill(payload)
        if result.get("success"):
            return jsonify({
                "success": True,
                "message": "Bill created successfully",
                "bill": {
                    "billNo":       result.get("bill_number"),
                    "date":         datetime.now().strftime("%d/%m/%Y"),
                    "time":         datetime.now().strftime("%I:%M %p"),
                    "paymentMode":  data.get("paymentMode", "Cash"),
                    "customerName": data.get("customerName", "Walk-in Customer"),
                    "items":        items,
                },
            }), 201
        return jsonify(result), 422

    except Exception as e:
        return jsonify({"success": False, "message": f"Error creating bill: {str(e)}"}), 400


@bilingual_bp.route("/bills", methods=["GET"])
def get_all_simple_bills():
    """Get all bills from the persistent store (newest first)."""
    data = billing_service.get_all_bills()
    return jsonify({"success": True, "bills": data}), 200


@bilingual_bp.route("/bills/<bill_no>", methods=["GET"])
def get_simple_bill(bill_no: str):
    """Get a specific bill by number."""
    bill = billing_service.get_bill_by_number(bill_no)
    if bill:
        return jsonify({"success": True, "bill": bill}), 200
    return jsonify({"success": False, "message": f"Bill {bill_no} not found"}), 404


@bilingual_bp.route("/bills/<bill_no>", methods=["DELETE"])
def delete_simple_bill(bill_no: str):
    """Delete a bill by number."""
    result = billing_service.delete_bill(bill_no)
    status = 200 if result.get("success") else 404
    return jsonify(result), status


@bilingual_bp.route("/generate-bill-number", methods=["GET"])
def generate_bill_number():
    """Return the next available bill number (does NOT create a bill)."""
    bill_no = billing_service._next_bill_number()
    now = datetime.now()
    return jsonify({
        "success": True,
        "billNo": bill_no,
        "date":   now.strftime("%d/%m/%Y"),
        "time":   now.strftime("%I:%M %p"),
    }), 200

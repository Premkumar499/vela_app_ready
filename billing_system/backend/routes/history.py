"""
Bill history routes.
"""

from concurrent.futures import ThreadPoolExecutor, as_completed
from flask import Blueprint, jsonify, request
from services.billing_service import billing_service

history_bp = Blueprint("history", __name__, url_prefix="/bills")


@history_bp.get("/")
def list_bills():
    """GET /bills/ – return all bills, newest first."""
    data = billing_service.get_all_bills()
    return jsonify({"success": True, "data": data, "count": len(data)}), 200


@history_bp.get("/summary")
def summary():
    """
    GET /bills/summary – dashboard totals.
    NOTE: This route MUST be registered before /<bill_number> so that
    Flask matches the literal path '/bills/summary' first.
    """
    data = billing_service.get_dashboard_summary()
    return jsonify({"success": True, "data": data}), 200


@history_bp.get("/<string:bill_number>")
def get_bill(bill_number: str):
    """GET /bills/<bill_number>"""
    bill = billing_service.get_bill_by_number(bill_number)
    if bill is None:
        return jsonify({"success": False, "message": "Bill not found"}), 404
    return jsonify({"success": True, "data": bill}), 200


@history_bp.delete("/<string:bill_number>")
def delete_bill(bill_number: str):
    """DELETE /bills/<bill_number>"""
    result = billing_service.delete_bill(bill_number)
    status = 200 if result["success"] else 404
    return jsonify(result), status


@history_bp.post("/bulk-delete")
def bulk_delete_bills():
    """POST /bills/bulk-delete"""
    payload = request.json or {}
    bill_numbers = payload.get("bill_numbers", [])
    if not bill_numbers:
        return jsonify({"success": False, "message": "No bill numbers provided"}), 400

    # Each delete_bill makes several sequential network calls (DB deletes,
    # storage removals, hold-cancel RPCs), so run bill deletions in parallel.
    deleted = []
    errors = []
    with ThreadPoolExecutor(max_workers=min(8, len(bill_numbers))) as pool:
        futures = {pool.submit(billing_service.delete_bill, bn): bn for bn in bill_numbers}
        for future in as_completed(futures):
            bn = futures[future]
            try:
                res = future.result()
            except Exception as exc:
                errors.append(f"Bill {bn}: {exc}")
                continue
            if res["success"]:
                deleted.append(bn)
            else:
                errors.append(f"Bill {bn}: {res.get('message', 'Unknown error')}")

    if errors:
        return jsonify({
            "success": len(deleted) > 0,
            "message": f"Deleted {len(deleted)} bills. Errors: {'; '.join(errors)}",
            "deleted": deleted
        }), 200 if deleted else 400

    return jsonify({"success": True, "message": f"Successfully deleted {len(deleted)} bills.", "deleted": deleted}), 200


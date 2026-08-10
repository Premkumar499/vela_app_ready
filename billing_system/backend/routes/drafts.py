"""
Draft bill routes – manage bill_drafts lifecycle for NON_GST_ERP.

Endpoints:
  POST  /drafts/create   – create a new ACTIVE draft row
  POST  /drafts/complete – mark draft COMPLETED (bill saved)
  POST  /drafts/cancel   – mark draft CANCELLED (bill abandoned)
  GET   /drafts/<id>     – get draft info
"""

from flask import Blueprint, jsonify, request
from services.draft_service import draft_service

drafts_bp = Blueprint("drafts", __name__, url_prefix="/drafts")


@drafts_bp.post("/create")
def create_draft():
    """
    Create a new ACTIVE draft in bill_drafts.

    Body: { "draft_id": "DRAFT-xxxx", "user_id": "optional-uuid" }
    """
    body = request.get_json(silent=True) or {}
    draft_id = body.get("draft_id")
    user_id  = body.get("user_id")

    if not draft_id:
        return jsonify({"success": False, "message": "draft_id is required"}), 400

    result = draft_service.create_draft(str(draft_id), user_id=user_id)
    status_code = 200 if result.get("success") else 409
    return jsonify(result), status_code


@drafts_bp.post("/complete")
def complete_draft():
    """
    Mark draft COMPLETED after bill is saved.

    Body: { "draft_id": "DRAFT-xxxx" }
    """
    body = request.get_json(silent=True) or {}
    draft_id = body.get("draft_id")

    if not draft_id:
        return jsonify({"success": False, "message": "draft_id is required"}), 400

    result = draft_service.complete_draft(str(draft_id))
    return jsonify(result), 200


@drafts_bp.post("/cancel")
def cancel_draft():
    """
    Mark draft CANCELLED when bill is abandoned.

    Body: { "draft_id": "DRAFT-xxxx" }
    """
    body = request.get_json(silent=True) or {}
    draft_id = body.get("draft_id")

    if not draft_id:
        return jsonify({"success": False, "message": "draft_id is required"}), 400

    result = draft_service.cancel_draft(str(draft_id))
    return jsonify(result), 200


@drafts_bp.get("/<string:draft_id>")
def get_draft(draft_id: str):
    """GET /drafts/<draft_id> – get draft status and info."""
    result = draft_service.get_draft(draft_id)
    status_code = 200 if result.get("success") else 404
    return jsonify(result), status_code

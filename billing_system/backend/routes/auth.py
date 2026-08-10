"""
Auth routes – login via mobile_number (used as password) from the users table.
"""

import os
from flask import Blueprint, jsonify, request
from dotenv import load_dotenv
from supabase import create_client

auth_bp = Blueprint("auth", __name__, url_prefix="/auth")


def _get_supabase():
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


@auth_bp.post("/login")
def login():
    """
    POST /auth/login
    Body: { "mobile_number": "9344486055" }

    Looks up the user by mobile_number in the users table.
    The mobile_number IS the password.
    Returns user info on success (role, name, warehouse_id).
    """
    body = request.get_json(silent=True) or {}
    mobile = str(body.get("mobile_number", "")).strip()

    if not mobile:
        return jsonify({"success": False, "message": "mobile_number is required"}), 400

    try:
        sb = _get_supabase()
        resp = (
            sb.table("users")
            .select("user_id, role_id, warehouse_id, mobile_number, full_name, is_active")
            .eq("mobile_number", mobile)
            .eq("is_active", True)
            .limit(1)
            .execute()
        )
        rows = resp.data or []

        if not rows:
            return jsonify({"success": False, "message": "Invalid credentials"}), 401

        user = rows[0]

        # Only Billing Employees (role_id = 3) can access this system
        if user.get("role_id") != 3:
            return jsonify({"success": False, "message": "Access denied. Only Billing Employees can log in."}), 403

        return jsonify({
            "success": True,
            "data": {
                "user_id":      user["user_id"],
                "role_id":      user["role_id"],
                "warehouse_id": user["warehouse_id"],
                "full_name":    user["full_name"],
                "mobile_number": user["mobile_number"],
            },
        }), 200

    except Exception as e:
        return jsonify({"success": False, "message": f"Server error: {str(e)}"}), 500

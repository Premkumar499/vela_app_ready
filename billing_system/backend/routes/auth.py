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
    role_id = body.get("role_id")

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

        # Verify that the role matches the selected role
        actual_role_id = user.get("role_id")
        full_name = str(user.get("full_name", "")).strip().lower()

        is_admin = actual_role_id in (1, 2) or "admin" in full_name
        is_billing = actual_role_id == 3 or "billing" in full_name
        is_warehouse = actual_role_id == 4 or "warehouse" in full_name

        if role_id is not None:
            try:
                expected_role_id = int(role_id)
                # Map role ID to canonical roles
                expected_admin = expected_role_id in (1, 2)
                expected_billing = expected_role_id == 3
                expected_warehouse = expected_role_id == 4

                if (expected_admin and not is_admin) or \
                   (expected_billing and not is_billing) or \
                   (expected_warehouse and not is_warehouse):
                    role_names = {1: "Admin", 2: "Admin", 3: "Billing Employee", 4: "Warehouse Manager"}
                    selected_name = role_names.get(expected_role_id, f"Role {expected_role_id}")
                    actual_name = "Admin" if is_admin else ("Billing Employee" if is_billing else "Warehouse Manager")
                    return jsonify({
                        "success": False,
                        "message": f"Role mismatch. Selected role is '{selected_name}' but this user is registered as '{actual_name}'."
                    }), 401
            except (ValueError, TypeError):
                pass

        # Only Admin, Billing Employees and Warehouse Manager can access this system
        if not (is_admin or is_billing or is_warehouse):
            return jsonify({"success": False, "message": "Access denied. Only Admin, Billing Employees and Warehouse Manager can log in."}), 403

        # Normalize role_id for frontend compatibility:
        # 1 = Admin, 3 = Billing Employee, 4 = Warehouse Manager
        norm_role_id = 1 if is_admin else (3 if is_billing else 4)

        return jsonify({
            "success": True,
            "data": {
                "user_id":      user["user_id"],
                "role_id":      norm_role_id,
                "warehouse_id": user["warehouse_id"],
                "full_name":    user["full_name"],
                "mobile_number": user["mobile_number"],
            },
        }), 200

    except Exception as e:
        import logging
        logging.getLogger(__name__).exception("Login error")
        return jsonify({"success": False, "message": "Server error. Please try again."}), 500

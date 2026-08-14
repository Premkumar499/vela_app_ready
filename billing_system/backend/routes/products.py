"""
Product routes.
"""

from flask import Blueprint, jsonify, request
from services.billing_service import billing_service

products_bp = Blueprint("products", __name__, url_prefix="/products")


@products_bp.get("/")
def list_products():
    """
    GET /products/
    Optional query params:
      ?category=Grocery   – filter by category
      ?search=rice        – search by name / category
    """
    category = request.args.get("category", "").strip()
    search = request.args.get("search", "").strip()

    if search:
        data = billing_service.search_products(search)
    elif category:
        data = billing_service.get_products_by_category(category)
    else:
        data = billing_service.get_all_products()

    return jsonify({"success": True, "data": data, "count": len(data)}), 200


@products_bp.get("/<string:product_id>")
def get_product(product_id: str):
    """GET /products/<uuid>"""
    product = billing_service.get_product_by_id(product_id)
    if product is None:
        return jsonify({"success": False, "message": "Product not found"}), 404
    return jsonify({"success": True, "data": product}), 200


def _num(value, default: float = 0.0) -> float:
    try:
        if value is None or value == "":
            return default
        return float(value)
    except (TypeError, ValueError):
        return default


@products_bp.post("/")
def create_product():
    """
    POST /products/
    Body: { "name": str, "price": float, "stock": float,
            "category": str, "unit": str, "sku": str }
    Inserts into Supabase (products + inventory) and returns the product.
    """
    body = request.get_json(silent=True) or {}
    name = (body.get("name") or "").strip()
    if not name:
        return jsonify({"success": False, "message": "name is required"}), 400

    result = billing_service.create_product(
        name=name,
        price=_num(body.get("price")),
        stock=_num(body.get("stock")),
        category=(body.get("category") or "General").strip(),
        unit=(body.get("unit") or "PCS").strip(),
        sku=(body.get("sku") or "").strip(),
    )
    if result.get("success"):
        return jsonify(result), 201
    return jsonify(result), 500


@products_bp.put("/<string:product_id>")
def update_product(product_id: str):
    """
    PUT /products/<uuid>
    Body: { "name": str, "price": float, "stock": float,
            "category": str, "unit": str, "sku": str }
    """
    body = request.get_json(silent=True) or {}
    name = (body.get("name") or "").strip()
    if not name:
        return jsonify({"success": False, "message": "name is required"}), 400

    result = billing_service.update_product(
        product_id=product_id,
        name=name,
        price=_num(body.get("price")),
        stock=_num(body.get("stock")),
        category=(body.get("category") or "General").strip(),
        unit=(body.get("unit") or "PCS").strip(),
        sku=(body.get("sku") or "").strip(),
    )
    if result.get("success"):
        return jsonify(result), 200
    if "not found" in result.get("message", ""):
        return jsonify(result), 404
    return jsonify(result), 500


@products_bp.delete("/<string:product_id>")
def delete_product(product_id: str):
    """DELETE /products/<uuid>"""
    result = billing_service.delete_product(product_id)
    if result.get("success"):
        return jsonify(result), 200
    if "not found" in result.get("message", ""):
        return jsonify(result), 404
    return jsonify(result), 500


@products_bp.post("/bulk-delete")
def bulk_delete_products():
    """
    POST /products/bulk-delete
    Body: { "product_ids": [uuid, uuid, ...] }
    """
    body = request.get_json(silent=True) or {}
    product_ids = body.get("product_ids")
    if not product_ids or not isinstance(product_ids, list):
        return jsonify({"success": False, "message": "product_ids is required and must be a list"}), 400

    deleted = []
    errors = []
    for pid in product_ids:
        res = billing_service.delete_product(pid)
        if res.get("success"):
            deleted.append(pid)
        else:
            errors.append({"product_id": pid, "error": res.get("message", "Unknown error")})

    if errors:
        return jsonify({
            "success": len(deleted) > 0,
            "deleted": deleted,
            "errors": errors,
            "message": f"Successfully deleted {len(deleted)} product(s), {len(errors)} failed."
        }), 200
    return jsonify({
        "success": True,
        "deleted": deleted,
        "message": f"Successfully deleted all {len(deleted)} product(s)."
    }), 200


"""
Warehouse routes – read-only data for the Warehouse Manager role.

Endpoints:
  GET /warehouse/products          – product list with live stock
  GET /warehouse/barcodes          – barcode / SKU list
  GET /warehouse/stock-movements   – stock in/out movement history
"""

from flask import Blueprint, jsonify, request
from services.warehouse_service import warehouse_service

warehouse_bp = Blueprint("warehouse", __name__, url_prefix="/warehouse")


@warehouse_bp.get("/products")
def warehouse_products():
    """
    GET /warehouse/products
    Optional: ?search=rice – filter by name / sku / barcode / category / brand
    """
    search = request.args.get("search", "").strip()
    result = warehouse_service.get_products(search=search)
    if not result.get("success"):
        return jsonify(result), 500
    return jsonify(result), 200


@warehouse_bp.get("/barcodes")
def warehouse_barcodes():
    """
    GET /warehouse/barcodes
    Optional: ?search=1234 – filter by name / barcode / sku / item_code
    """
    search = request.args.get("search", "").strip()
    result = warehouse_service.get_barcodes(search=search)
    if not result.get("success"):
        return jsonify(result), 500
    return jsonify(result), 200


@warehouse_bp.get("/stock-movements")
def warehouse_stock_movements():
    """
    GET /warehouse/stock-movements
    Optional: ?search=rice&limit=200
    """
    search = request.args.get("search", "").strip()
    try:
        limit = min(max(int(request.args.get("limit", 200)), 1), 1000)
    except (TypeError, ValueError):
        limit = 200
    result = warehouse_service.get_stock_movements(search=search, limit=limit)
    if not result.get("success"):
        return jsonify(result), 500
    return jsonify(result), 200

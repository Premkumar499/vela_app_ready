"""
WarehouseService – read-only data for the Warehouse Manager role.

Reads product list, barcode list and stock in/out movements straight from
Supabase (shared schema: products, inventory, stock_reservations).
"""

import os

SOURCE_APP = "NON_GST_ERP"


def _get_supabase():
    from dotenv import load_dotenv
    from supabase import create_client
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


def _safe_float(value, default: float = 0.0) -> float:
    try:
        if value is None or value == "":
            return default
        return float(value)
    except (TypeError, ValueError):
        return default


class WarehouseService:

    # ------------------------------------------------------------------
    # Product list (products + inventory joined in code)
    # ------------------------------------------------------------------
    def get_products(self, search: str = "") -> dict:
        try:
            sb = _get_supabase()

            inv_rows = (
                sb.table("inventory")
                .select("product_id, current_stock, reserved_stock")
                .execute()
            ).data or []
            stock_map = {
                str(r["product_id"]): {
                    "current": _safe_float(r.get("current_stock")),
                    "reserved": _safe_float(r.get("reserved_stock")),
                }
                for r in inv_rows
            }

            query = (
                sb.table("products")
                .select(
                    "product_id, product_name, sku, barcode, item_code,"
                    "selling_price, purchase_price, minimum_stock,"
                    "categories(name), units(unit_name), brands(brand_name)"
                )
                .eq("gst_percentage", 0)
                .order("product_name")
            )
            rows = query.execute().data or []

            data = []
            for r in rows:
                pid = str(r.get("product_id") or "")
                inv = stock_map.get(pid, {"current": 0.0, "reserved": 0.0})
                row = {
                    "id":            pid,
                    "name":          r.get("product_name") or "",
                    "sku":           r.get("sku") or "",
                    "barcode":       r.get("barcode") or r.get("item_code") or "",
                    "category":      ((r.get("categories") or {}).get("name") or "General"),
                    "unit":          ((r.get("units") or {}).get("unit_name") or "Nos"),
                    "brand":         ((r.get("brands") or {}).get("brand_name") or ""),
                    "price":         _safe_float(r.get("selling_price")),
                    "purchase_price": _safe_float(r.get("purchase_price")),
                    "current_stock": inv["current"],
                    "reserved_stock": inv["reserved"],
                    "available_stock": round(inv["current"] - inv["reserved"], 2),
                    "minimum_stock": _safe_float(r.get("minimum_stock")),
                }
                if search:
                    q = search.lower()
                    haystack = " ".join([
                        row["name"], row["sku"], row["barcode"],
                        row["category"], row["brand"],
                    ]).lower()
                    if q not in haystack:
                        continue
                data.append(row)

            return {"success": True, "count": len(data), "data": data}
        except Exception as exc:
            import traceback; traceback.print_exc()
            return {"success": False, "message": str(exc)}

    # ------------------------------------------------------------------
    # Barcode list
    # ------------------------------------------------------------------
    def get_barcodes(self, search: str = "") -> dict:
        try:
            sb = _get_supabase()
            rows = (
                sb.table("products")
                .select(
                    "product_id, product_name, sku, barcode, item_code,"
                    "units(unit_name)"
                )
                .eq("gst_percentage", 0)
                .order("product_name")
                .execute()
            ).data or []

            data = []
            for r in rows:
                barcode = r.get("barcode") or ""
                sku = r.get("sku") or ""
                item_code = r.get("item_code") or ""
                if not (barcode or sku or item_code):
                    continue  # only show products that have a barcode/SKU
                row = {
                    "product_id":   str(r.get("product_id") or ""),
                    "name":         r.get("product_name") or "",
                    "unit":         ((r.get("units") or {}).get("unit_name") or "Nos"),
                    "barcode":      barcode,
                    "sku":          sku,
                    "item_code":    item_code,
                }
                if search:
                    q = search.lower()
                    haystack = " ".join([
                        row["name"], row["barcode"], row["sku"], row["item_code"],
                    ]).lower()
                    if q not in haystack:
                        continue
                data.append(row)

            return {"success": True, "count": len(data), "data": data}
        except Exception as exc:
            import traceback; traceback.print_exc()
            return {"success": False, "message": str(exc)}

    # ------------------------------------------------------------------
    # Stock in/out movements (derived from stock_reservations)
    #   IN   → RELEASED / EXPIRED  (stock restored to inventory)
    #   OUT  → COMPLETED           (bill finalized, stock consumed)
    #   HOLD → HELD / ACTIVE       (stock reserved for a bill)
    # ------------------------------------------------------------------
    def get_stock_movements(self, search: str = "", limit: int = 200) -> dict:
        try:
            sb = _get_supabase()
            rows = (
                sb.table("stock_reservations")
                .select(
                    "id, product_id, bill_id, quantity, status,"
                    "reserved_at, expires_at, released_at, completed_at"
                )
                .eq("source_app", SOURCE_APP)
                .order("created_at", desc=True)
                .limit(limit)
                .execute()
            ).data or []

            if not rows:
                return {"success": True, "count": 0, "data": []}

            product_ids = sorted({str(r["product_id"]) for r in rows})
            prod_rows = (
                sb.table("products")
                .select("product_id, product_name, units(unit_name)")
                .in_("product_id", product_ids)
                .execute()
            ).data or []
            prod_map = {
                str(r["product_id"]): {
                    "name": r.get("product_name") or "(deleted product)",
                    "unit": ((r.get("units") or {}).get("unit_name") or "Nos"),
                }
                for r in prod_rows
            }

            movement_type = {
                "COMPLETED": "OUT",
                "RELEASED":  "IN",
                "EXPIRED":   "IN",
                "HELD":      "HOLD",
                "ACTIVE":    "HOLD",
            }

            data = []
            for r in rows:
                status = r.get("status") or ""
                name = prod_map.get(str(r.get("product_id") or ""), {}).get(
                    "name", "(deleted product)")
                unit = prod_map.get(str(r.get("product_id") or ""), {}).get(
                    "unit", "Nos")
                row = {
                    "reservation_id": str(r.get("id") or ""),
                    "product_id":     str(r.get("product_id") or ""),
                    "name":           name,
                    "unit":           unit,
                    "quantity":       _safe_float(r.get("quantity")),
                    "status":         status,
                    "movement":       movement_type.get(status, status),
                    "bill_id":        r.get("bill_id") or "",
                    "reserved_at":    r.get("reserved_at"),
                    "completed_at":   r.get("completed_at"),
                    "released_at":    r.get("released_at"),
                }
                if search:
                    q = search.lower()
                    haystack = " ".join([
                        row["name"], row["bill_id"], row["status"],
                    ]).lower()
                    if q not in haystack:
                        continue
                data.append(row)

            return {"success": True, "count": len(data), "data": data}
        except Exception as exc:
            import traceback; traceback.print_exc()
            return {"success": False, "message": str(exc)}


# Module-level singleton
warehouse_service = WarehouseService()

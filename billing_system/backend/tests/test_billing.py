"""
Comprehensive test suite for BillingService and Flask API endpoints.

Run:
    cd billing_system/backend
    pytest tests/ -v
"""

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import pytest
from app import create_app
from services.billing_service import BillingService
from services.sample_data import SAMPLE_PRODUCTS


@pytest.fixture
def service():
    return BillingService()


@pytest.fixture
def client():
    app = create_app()
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


def _valid_bill():
    return {
        "customer_id": 1,
        "customer_name": "Walk-in Customer",
        "payment_type": "Cash",
        "sales_type": "Retail",
        "items": [
            {
                "product_id": 1,
                "product_name": SAMPLE_PRODUCTS[0].name,
                "unit": SAMPLE_PRODUCTS[0].unit,
                "quantity": 2,
                "rate": float(SAMPLE_PRODUCTS[0].price),
                "gst_percent": 0,
                "discount_percent": 0,
            }
        ],
    }


# ===========================================================================
# 1. Products
# ===========================================================================

class TestProducts:
    def test_products_loaded_from_excel(self, service):
        assert len(service.get_all_products()) == 545

    def test_get_product_by_valid_id(self, service):
        p = service.get_product_by_id(1)
        assert p is not None
        assert "name" in p

    def test_get_product_by_invalid_id(self, service):
        assert service.get_product_by_id(9999) is None

    def test_product_has_required_fields(self, service):
        p = service.get_product_by_id(1)
        for field in ("id", "name", "unit", "price", "mrp", "stock", "category"):
            assert field in p

    def test_search_products_by_name(self, service):
        results = service.search_products("rice")
        assert len(results) > 0

    def test_search_products_no_match(self, service):
        assert service.search_products("xyznonexistent999") == []

    def test_product_price_positive(self, service):
        assert any(p["price"] > 0 for p in service.get_all_products())

    def test_product_stock_non_negative(self, service):
        for p in service.get_all_products():
            assert p["stock"] >= 0


# ===========================================================================
# 2. Customers
# ===========================================================================

class TestCustomers:
    def test_walkin_customer_exists(self, service):
        c = service.get_customer_by_id(1)
        assert c is not None
        assert c["name"] == "Walk-in Customer"

    def test_get_customer_by_invalid_id(self, service):
        assert service.get_customer_by_id(9999) is None

    def test_customer_has_required_fields(self, service):
        c = service.get_customer_by_id(1)
        for field in ("id", "name", "phone", "area"):
            assert field in c

    def test_search_customers(self, service):
        assert len(service.search_customers("walk")) >= 1


# ===========================================================================
# 3. Bill Creation
# ===========================================================================

class TestCreateBill:
    def test_create_valid_bill(self, service):
        result = service.create_bill(_valid_bill())
        assert result["success"] is True
        assert result["bill_number"] == "INV0001"

    def test_bill_number_increments(self, service):
        service.create_bill(_valid_bill())
        r2 = service.create_bill(_valid_bill())
        assert r2["bill_number"] == "INV0002"

    def test_bill_stored_in_memory(self, service):
        service.create_bill(_valid_bill())
        assert len(service._bills) == 1

    def test_bill_has_required_fields(self, service):
        bill = service.create_bill(_valid_bill())["bill"]
        for field in ("bill_number", "date", "customer_id", "items", "subtotal", "grand_total"):
            assert field in bill

    def test_subtotal_correct(self, service):
        rate = float(SAMPLE_PRODUCTS[0].price)
        bill = service.create_bill(_valid_bill())["bill"]
        assert bill["subtotal"] == round(rate * 2, 2)

    def test_bill_with_ignored_discount(self, service):
        payload = _valid_bill()
        payload["items"][0]["discount_percent"] = 10
        result = service.create_bill(payload)
        assert result["success"] is True
        assert "discount_total" not in result["bill"]
        subtotal = round(float(payload["items"][0]["rate"]) * 2, 2)
        assert result["bill"]["grand_total"] == subtotal

    def test_bill_with_multiple_items(self, service):
        payload = _valid_bill()
        payload["items"].append({
            "product_id": 2,
            "product_name": SAMPLE_PRODUCTS[1].name,
            "unit": SAMPLE_PRODUCTS[1].unit,
            "quantity": 1,
            "rate": float(SAMPLE_PRODUCTS[1].price),
            "gst_percent": 0,
            "discount_percent": 0,
        })
        result = service.create_bill(payload)
        assert result["success"] is True
        assert len(result["bill"]["items"]) == 2

    def test_payment_type_saved(self, service):
        payload = _valid_bill()
        payload["payment_type"] = "UPI"
        result = service.create_bill(payload)
        assert result["bill"]["payment_type"] == "UPI"

    def test_in_memory_resets_on_new_instance(self, service):
        service.create_bill(_valid_bill())
        assert len(BillingService()._bills) == 0


# ===========================================================================
# 4. Validation
# ===========================================================================

class TestBillValidation:
    def test_missing_customer_id_fails(self, service):
        payload = _valid_bill()
        del payload["customer_id"]
        result = service.create_bill(payload)
        assert result["success"] is False
        assert "customer_id" in result["message"]

    def test_missing_customer_name_fails(self, service):
        payload = _valid_bill()
        del payload["customer_name"]
        assert service.create_bill(payload)["success"] is False

    def test_empty_items_fails(self, service):
        payload = _valid_bill()
        payload["items"] = []
        assert service.create_bill(payload)["success"] is False

    def test_zero_quantity_fails(self, service):
        payload = _valid_bill()
        payload["items"][0]["quantity"] = 0
        assert service.create_bill(payload)["success"] is False

    def test_negative_quantity_fails(self, service):
        payload = _valid_bill()
        payload["items"][0]["quantity"] = -1
        assert service.create_bill(payload)["success"] is False

    def test_zero_rate_fails(self, service):
        payload = _valid_bill()
        payload["items"][0]["rate"] = 0
        assert service.create_bill(payload)["success"] is False


# ===========================================================================
# 5. Stock Management
# ===========================================================================

class TestStock:
    def test_stock_deducted_after_bill(self, service):
        before = service.get_product_by_id(1)["stock"]
        service.create_bill(_valid_bill())
        assert service.get_product_by_id(1)["stock"] == before - 2

    def test_stock_restored_after_delete(self, service):
        before = service.get_product_by_id(1)["stock"]
        service.create_bill(_valid_bill())
        service.delete_bill("INV0001")
        assert service.get_product_by_id(1)["stock"] == before

    def test_stock_never_negative(self, service):
        payload = _valid_bill()
        payload["items"][0]["quantity"] = 99999
        service.create_bill(payload)
        assert service.get_product_by_id(1)["stock"] >= 0


# ===========================================================================
# 6. Bill Retrieval & Deletion
# ===========================================================================

class TestBillRetrievalDeletion:
    def test_get_all_bills_empty_initially(self, service):
        assert service.get_all_bills() == []

    def test_get_all_bills_newest_first(self, service):
        service.create_bill(_valid_bill())
        service.create_bill(_valid_bill())
        assert service.get_all_bills()[0]["bill_number"] == "INV0002"

    def test_get_bill_by_number(self, service):
        service.create_bill(_valid_bill())
        b = service.get_bill_by_number("INV0001")
        assert b is not None and b["bill_number"] == "INV0001"

    def test_get_bill_not_found(self, service):
        assert service.get_bill_by_number("INV9999") is None

    def test_delete_bill(self, service):
        service.create_bill(_valid_bill())
        assert service.delete_bill("INV0001")["success"] is True
        assert len(service._bills) == 0

    def test_delete_nonexistent_bill(self, service):
        assert service.delete_bill("INV9999")["success"] is False


# ===========================================================================
# 7. Dashboard Summary
# ===========================================================================

class TestDashboard:
    def test_summary_zero_bills(self, service):
        s = service.get_dashboard_summary()
        assert s["total_bills"] == 0
        assert s["total_sales"] == 0.0
        assert s["total_products"] == 545

    def test_summary_after_bill(self, service):
        service.create_bill(_valid_bill())
        s = service.get_dashboard_summary()
        assert s["total_bills"] == 1
        assert s["total_sales"] > 0


# ===========================================================================
# 8. Flask API Endpoints
# ===========================================================================

class TestAPI:
    def test_health(self, client):
        resp = client.get("/health")
        assert resp.status_code == 200
        assert resp.json["status"] == "ok"

    def test_get_products_count(self, client):
        resp = client.get("/products/")
        assert resp.status_code == 200
        assert resp.json["count"] == 545

    def test_get_products_has_data(self, client):
        assert "data" in client.get("/products/").json

    def test_get_customers(self, client):
        resp = client.get("/customers/")
        assert resp.status_code == 200
        assert resp.json["count"] >= 1

    def test_post_bill_success(self, client):
        resp = client.post("/bill/", json=_valid_bill())
        assert resp.status_code == 201
        assert resp.json["success"] is True

    def test_post_bill_invalid_json(self, client):
        resp = client.post("/bill/", data="not json", content_type="text/plain")
        assert resp.status_code == 400

    def test_post_bill_empty_items(self, client):
        payload = _valid_bill()
        payload["items"] = []
        resp = client.post("/bill/", json=payload)
        assert resp.status_code in (400, 422)

    def test_get_bills(self, client):
        client.post("/bill/", json=_valid_bill())
        assert client.get("/bills/").status_code == 200

    def test_404_unknown_endpoint(self, client):
        resp = client.get("/nonexistent/")
        assert resp.status_code == 404

    def test_method_not_allowed(self, client):
        assert client.delete("/products/").status_code == 405


# ===========================================================================
# 9. Hold Bill not implemented
# ===========================================================================

class TestHoldBill:
    def test_hold_bill_not_implemented(self, client):
        assert client.post("/bill/hold", json=_valid_bill()).status_code == 404

    def test_get_held_bills_not_implemented(self, client):
        assert client.get("/bill/held").status_code == 404

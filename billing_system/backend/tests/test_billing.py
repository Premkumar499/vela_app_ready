"""
Test suite for BillingService validation logic and Flask API endpoints.

Run:
    cd billing_system/backend
    pytest tests/ -v
"""

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import pytest
from app import create_app


@pytest.fixture
def client():
    app = create_app()
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


def _valid_bill():
    return {
        "customer_id": "00000000-0000-0000-0000-000000000000",
        "customer_name": "Walk-in Customer",
        "payment_type": "Cash",
        "sales_type": "Retail",
        "items": [
            {
                "product_id": "test-product-id",
                "product_name": "Test Product",
                "unit": "KG",
                "quantity": 2,
                "rate": 100.0,
                "gst_percent": 0,
                "discount_percent": 0,
            }
        ],
    }


# ===========================================================================
# 1. Bill Validation (input validation only — no DB calls)
# ===========================================================================

class TestBillValidation:
    """These test the validation layer in create_bill, not DB persistence."""

    def test_missing_customer_id_fails(self, client):
        payload = _valid_bill()
        del payload["customer_id"]
        resp = client.post("/bill/", json=payload)
        assert resp.status_code in (400, 422)

    def test_missing_customer_name_fails(self, client):
        payload = _valid_bill()
        del payload["customer_name"]
        resp = client.post("/bill/", json=payload)
        assert resp.status_code in (400, 422)

    def test_empty_items_fails(self, client):
        payload = _valid_bill()
        payload["items"] = []
        resp = client.post("/bill/", json=payload)
        assert resp.status_code in (400, 422)

    def test_zero_quantity_fails(self, client):
        payload = _valid_bill()
        payload["items"][0]["quantity"] = 0
        resp = client.post("/bill/", json=payload)
        assert resp.status_code in (400, 422)

    def test_negative_quantity_fails(self, client):
        payload = _valid_bill()
        payload["items"][0]["quantity"] = -1
        resp = client.post("/bill/", json=payload)
        assert resp.status_code in (400, 422)

    def test_zero_rate_fails(self, client):
        payload = _valid_bill()
        payload["items"][0]["rate"] = 0
        resp = client.post("/bill/", json=payload)
        assert resp.status_code in (400, 422)


# ===========================================================================
# 2. Flask API Endpoints
# ===========================================================================

class TestAPI:
    def test_health(self, client):
        resp = client.get("/health")
        assert resp.status_code == 200
        assert resp.json["status"] == "ok"

    def test_get_products_returns_200(self, client):
        resp = client.get("/products/")
        assert resp.status_code == 200
        assert "data" in resp.json

    def test_get_customers_returns_200(self, client):
        resp = client.get("/customers/")
        assert resp.status_code == 200
        assert "count" in resp.json

    def test_get_bills_returns_200(self, client):
        assert client.get("/bills/").status_code == 200

    def test_post_bill_invalid_json(self, client):
        resp = client.post("/bill/", data="not json", content_type="text/plain")
        assert resp.status_code == 400

    def test_404_unknown_endpoint(self, client):
        resp = client.get("/nonexistent/")
        assert resp.status_code == 404

    def test_method_not_allowed(self, client):
        assert client.delete("/products/").status_code == 405

    def test_hold_bill_not_implemented(self, client):
        assert client.post("/bill/hold", json=_valid_bill()).status_code == 404

    def test_get_held_bills_not_implemented(self, client):
        assert client.get("/bill/held").status_code == 404

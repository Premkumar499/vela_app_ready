"""
Bill and BillItem models.
"""

from dataclasses import dataclass, field
from typing import List, Optional
from datetime import datetime


@dataclass
class BillItem:
    product_id: int
    product_name: str
    unit: str
    quantity: float
    rate: float          # sale price per unit (no GST)
    discount_percent: float = 0.0

    # ------------------------------------------------------------------
    # Computed properties
    # ------------------------------------------------------------------

    @property
    def gross_amount(self) -> float:
        return round(self.rate * self.quantity, 2)

    @property
    def discount_amount(self) -> float:
        return round(self.gross_amount * self.discount_percent / 100, 2)

    @property
    def total(self) -> float:
        return round(self.gross_amount - self.discount_amount, 2)

    # ------------------------------------------------------------------
    # Serialisation
    # ------------------------------------------------------------------

    def to_dict(self) -> dict:
        return {
            "product_id": self.product_id,
            "product_name": self.product_name,
            "unit": self.unit,
            "quantity": self.quantity,
            "rate": self.rate,
            "discount_percent": self.discount_percent,
            "discount_amount": self.discount_amount,
            "total": self.total,
        }

    @classmethod
    def from_dict(cls, data: dict) -> "BillItem":
        return cls(
            product_id=data["product_id"],
            product_name=data["product_name"],
            unit=data.get("unit", "PCS"),
            quantity=float(data["quantity"]),
            rate=float(data["rate"]),
            discount_percent=float(data.get("discount_percent", 0)),
        )


@dataclass
class Bill:
    bill_number: str
    date: str                       # ISO-8601 string
    customer_id: int
    customer_name: str
    customer_phone: str = ""        # for internal records only
    payment_type: str = "Cash"      # "Cash" | "Credit" | "UPI"
    items: List[BillItem] = field(default_factory=list)
    remarks: str = ""
    sales_type: str = "Retail"
    through: str = ""               # salesman / agent
    area: str = ""
    price_list: str = "Retail"

    # ------------------------------------------------------------------
    # Computed totals
    # ------------------------------------------------------------------

    @property
    def subtotal(self) -> float:
        return round(sum(item.gross_amount for item in self.items), 2)

    @property
    def grand_total(self) -> float:
        return round(sum(item.total for item in self.items), 2)

    # ------------------------------------------------------------------
    # Serialisation
    # ------------------------------------------------------------------

    def to_dict(self) -> dict:
        return {
            "bill_number": self.bill_number,
            "date": self.date,
            "customer_id": self.customer_id,
            "customer_name": self.customer_name,
            "customer_phone": self.customer_phone,
            "payment_type": self.payment_type,
            "sales_type": self.sales_type,
            "through": self.through,
            "area": self.area,
            "price_list": self.price_list,
            "remarks": self.remarks,
            "items": [item.to_dict() for item in self.items],
            "subtotal": self.subtotal,
            "grand_total": self.grand_total,
            "item_count": len(self.items),
        }

    @classmethod
    def from_dict(cls, data: dict) -> "Bill":
        items = [BillItem.from_dict(i) for i in data.get("items", [])]
        return cls(
            bill_number=data["bill_number"],
            date=data.get("date", datetime.now().isoformat()),
            customer_id=data["customer_id"],
            customer_name=data["customer_name"],
            customer_phone=data.get("customer_phone", ""),
            payment_type=data.get("payment_type", "Cash"),
            items=items,
            remarks=data.get("remarks", ""),
            sales_type=data.get("sales_type", "Retail"),
            through=data.get("through", ""),
            area=data.get("area", ""),
            price_list=data.get("price_list", "Retail"),
        )

"""
Product model – plain Python dataclass.
No ORM dependency so the migration path to SQLAlchemy is straightforward:
replace the dataclass with a db.Model subclass and keep every other file intact.
"""

from dataclasses import dataclass, field
from typing import Optional


@dataclass
class Product:
    id: str            # UUID from Supabase (e.g. "0ddb5e4f-d5ce-...")
    name: str
    unit: str          # e.g. "KG", "PCS", "LTR"
    price: float       # sale price (final price, no GST)
    mrp: float         # maximum retail price
    stock: float       # current stock quantity (inventory.current_stock)
    category: str      # e.g. "Grocery", "Dairy"
    reserved: float = field(default=0.0)       # units currently held by bills
    available_stock: float = field(default=0.0)  # current_stock - reserved_stock
    description: Optional[str] = field(default="")
    image_url: Optional[str] = field(default=None)

    # ------------------------------------------------------------------
    # Serialisation
    # ------------------------------------------------------------------

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "name": self.name,
            "unit": self.unit,
            "price": self.price,
            "mrp": self.mrp,
            "stock": self.stock,
            "reserved": self.reserved,
            "available_stock": self.available_stock,
            "category": self.category,
            "description": self.description,
            "image_url": self.image_url,
        }

    @classmethod
    def from_dict(cls, data: dict) -> "Product":
        return cls(
            id=str(data["id"]),
            name=data["name"],
            unit=data["unit"],
            price=float(data["price"]),
            mrp=float(data.get("mrp", data["price"])),
            stock=float(data["stock"]),
            reserved=float(data.get("reserved", 0.0)),
            available_stock=float(data.get("available_stock", 0.0)),
            category=data.get("category", "General"),
            description=data.get("description", ""),
            image_url=data.get("image_url"),
        )

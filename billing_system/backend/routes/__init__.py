from .products import products_bp
from .customers import customers_bp
from .billing import billing_bp
from .history import history_bp
from .translate import translate_bp
from .bilingual_billing import bilingual_bp
from .auth import auth_bp
from .reservations import reservations_bp
from .drafts import drafts_bp
from .salesperson_bills import salesperson_bills_bp

__all__ = ["products_bp", "customers_bp", "billing_bp", "history_bp", "translate_bp", "bilingual_bp", "auth_bp", "reservations_bp", "drafts_bp", "salesperson_bills_bp"]

"""
Flask application entry point.

Run:
    pip install -r requirements.txt
    python app.py
"""

from flask import Flask, jsonify
from flask_cors import CORS

from config import Config
from routes import products_bp, customers_bp, billing_bp, history_bp, translate_bp, bilingual_bp, auth_bp, reservations_bp, drafts_bp, salesperson_bills_bp
from routes.invoice_export import invoice_export_bp


def create_app() -> Flask:
    app = Flask(__name__)
    app.config.from_object(Config)

    # -----------------------------------------------------------------------
    # CORS – allow Flutter web app running on any localhost port
    # -----------------------------------------------------------------------
    CORS(
        app,
        origins=Config.CORS_ORIGINS,
        supports_credentials=False,
        allow_headers=["Content-Type", "Accept", "Authorization"],
        methods=["GET", "POST", "DELETE", "OPTIONS"],
    )

    # -----------------------------------------------------------------------
    # Register blueprints
    # -----------------------------------------------------------------------
    app.register_blueprint(products_bp)
    app.register_blueprint(customers_bp)
    app.register_blueprint(billing_bp)
    app.register_blueprint(history_bp)
    app.register_blueprint(translate_bp)
    app.register_blueprint(bilingual_bp)
    app.register_blueprint(invoice_export_bp)
    app.register_blueprint(auth_bp)
    app.register_blueprint(reservations_bp)
    app.register_blueprint(drafts_bp)
    app.register_blueprint(salesperson_bills_bp)

    # -----------------------------------------------------------------------
    # Health-check endpoint
    # -----------------------------------------------------------------------
    @app.get("/health")
    def health():
        return jsonify({
            "status": "ok",
            "service": "ERP Billing API",
            "version": "1.0.0 (prototype)",
        }), 200

    # -----------------------------------------------------------------------
    # Global error handlers
    # -----------------------------------------------------------------------
    @app.errorhandler(404)
    def not_found(e):
        return jsonify({"success": False, "message": "Endpoint not found"}), 404

    @app.errorhandler(405)
    def method_not_allowed(e):
        return jsonify({"success": False, "message": "Method not allowed"}), 405

    @app.errorhandler(500)
    def internal_error(e):
        return jsonify({"success": False, "message": "Internal server error"}), 500

    return app


# ---------------------------------------------------------------------------
# Run directly
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    app = create_app()
    print("=" * 60)
    print("  ERP Billing API  –  Prototype Edition")
    print(f"  Listening on http://{Config.HOST}:{Config.PORT}")
    print("=" * 60)
    app.run(host=Config.HOST, port=Config.PORT, debug=Config.DEBUG)

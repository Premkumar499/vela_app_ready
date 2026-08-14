"""
Flask application entry point.

Run:
    pip install -r requirements.txt
    python app.py
"""

from flask import Flask, jsonify
from flask_cors import CORS

from config import Config
from routes import products_bp, customers_bp, billing_bp, history_bp, translate_bp, bilingual_bp, auth_bp, reservations_bp, drafts_bp, salesperson_bills_bp, warehouse_bp
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
        methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
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
    app.register_blueprint(warehouse_bp)

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

    @app.errorhandler(Exception)
    def handle_exception(e):
        # Prevent any unexpected crash from breaking the JSON API structure
        print(f"[ERROR] Unhandled Exception: {str(e)}", flush=True)
        return jsonify({
            "success": False,
            "message": "An unexpected error occurred. Please try again later.",
            "error": str(e) if app.debug else "Internal error"
        }), 500

    start_salesperson_bill_polling(app)

    return app


def start_salesperson_bill_polling(app):
    import time
    import threading
    import os
    import sys

    # If debug mode is on, Werkzeug starts two processes. We only run the polling thread
    # in the child process to avoid duplicate threads running.
    # However, if we are running under a production WSGI server (like Gunicorn or Waitress)
    # or the reloader is disabled, we want to run the thread regardless of app.debug.
    is_reloader_parent = app.debug and os.environ.get("WERKZEUG_RUN_MAIN") != "true"
    is_flask_or_direct = any(x in os.path.basename(sys.argv[0]).lower() for x in ["app.py", "flask"])

    if is_reloader_parent and is_flask_or_direct:
        return

    def poll_loop():
        # Delay start slightly to allow the server to boot up
        time.sleep(3)
        print("[SalespersonBillPolling] Background polling thread started.", flush=True)
        while True:
            try:
                from services.salesperson_bill_service import salesperson_bill_service
                pending_bills = salesperson_bill_service.list_pending()
                if pending_bills:
                    print(f"[SalespersonBillPolling] Found {len(pending_bills)} pending salesperson bills.", flush=True)
                    for row in pending_bills:
                        bill_id = row.get("id")
                        if bill_id:
                            print(f"[SalespersonBillPolling] Auto-processing bill ID: {bill_id}", flush=True)
                            result = salesperson_bill_service.push(bill_id)
                            print(f"[SalespersonBillPolling] Auto-processed result: {result}", flush=True)
            except Exception as e:
                print(f"[SalespersonBillPolling] Error in polling loop: {e}", flush=True)
            time.sleep(4)  # Poll every 4 seconds

    thread = threading.Thread(target=poll_loop, daemon=True)
    thread.start()


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

"""
Cross-System Concurrency Test
==============================
YOU run this on YOUR machine after your friend confirms their
GST_ERP system is connected to the same Supabase database.

This script simulates the real scenario:
  - YOUR system (NON_GST_ERP) reserves stock
  - YOUR FRIEND'S system (GST_ERP) tries to reserve the same stock
  - Both use the SAME shared database
  - The database row lock (SELECT FOR UPDATE) ensures correctness

No friend needs to be online — we simulate GST_ERP from here
using source_app='GST_ERP' directly in the shared database.

Run:
    cd billing_system/backend
    python tests/test_cross_system_concurrency.py
"""

import sys, os, time, threading, ast
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from dotenv import load_dotenv
load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"), override=True)
from supabase import create_client

URL = os.environ["SUPABASE_URL"]
KEY = os.environ["SUPABASE_SERVICE_KEY"]

PRODUCT_ID = "3355b354-3e25-4036-ad64-f9fee7875412"  # Avt Tea 1/2 Kg

# ── Helpers ────────────────────────────────────────────────────────────────────

def client():
    return create_client(URL, KEY)

def get_stock():
    r = client().table("inventory").select("current_stock, reserved_stock").eq("product_id", PRODUCT_ID).execute()
    return float(r.data[0]["current_stock"]), float(r.data[0]["reserved_stock"])

def set_stock(current, reserved=0):
    client().table("inventory").update({
        "current_stock": current, "reserved_stock": reserved
    }).eq("product_id", PRODUCT_ID).execute()

def rpc_reserve(source_app, bill_id, quantity, out, key):
    sb = client()
    try:
        r = sb.rpc("reserve_stock", {
            "p_product_id": PRODUCT_ID,
            "p_bill_id":    bill_id,
            "p_user_id":    "",
            "p_source_app": source_app,
            "p_quantity":   float(quantity),
        }).execute()
        data = r.data
        out[key] = data[0] if isinstance(data, list) and data else data
    except Exception as e:
        err = str(e)
        if "success" in err:
            try:
                out[key] = ast.literal_eval(err[err.index("{"):err.rindex("}")+1])
                return
            except Exception:
                pass
        out[key] = {"success": False, "error_code": "EXCEPTION", "message": err[:200]}

def cleanup(*bill_ids):
    sb = client()
    for bid in bill_ids:
        try:
            rows = sb.table("stock_reservations").select("id,status").eq("bill_id", bid).execute()
            for row in rows.data:
                if row["status"] == "ACTIVE":
                    sb.rpc("release_reservation", {"p_reservation_id": row["id"]}).execute()
            sb.table("stock_reservations").delete().eq("bill_id", bid).execute()
            sb.table("bill_drafts").delete().eq("id", bid).execute()
        except Exception:
            pass

def header(title):
    print(f"\n{'═'*58}")
    print(f"  {title}")
    print(f"{'═'*58}")

def check(condition, msg_pass, msg_fail):
    if condition:
        print(f"  ✓ {msg_pass}")
    else:
        raise AssertionError(f"✗ {msg_fail}")


# ==============================================================================
# CROSS-SYSTEM TEST 1
# NON_GST_ERP and GST_ERP both want 7 from stock=10
# Expected: exactly one wins, physical stock preserved
# ==============================================================================
def cross_test_1_one_wins():
    header("CROSS TEST 1: Both want 7, stock=10 → only one wins")

    set_stock(10, 0)
    ts = int(time.time() * 1000)
    bill_nongst = f"NONGST-C1-{ts}"
    bill_gst    = f"GST-C1-{ts}"

    results = {}
    t1 = threading.Thread(target=rpc_reserve, args=("NON_GST_ERP", bill_nongst, 7, results, "NON_GST"))
    t2 = threading.Thread(target=rpc_reserve, args=("GST_ERP",     bill_gst,    7, results, "GST"))
    t1.start(); t2.start()
    t1.join();  t2.join()

    nongst = results["NON_GST"]
    gst    = results["GST"]

    print(f"  NON_GST_ERP: success={nongst.get('success')} | error={nongst.get('error_code')} | remaining={nongst.get('remaining_available')}")
    print(f"  GST_ERP:     success={gst.get('success')}    | error={gst.get('error_code')}    | remaining={gst.get('remaining_available')}")

    current, reserved = get_stock()
    print(f"  DB stock after: current={current} reserved={reserved}")

    winners = [k for k, v in results.items() if v.get("success")]
    losers  = [k for k, v in results.items() if not v.get("success")]

    check(len(winners) == 1,           f"Exactly 1 winner: {winners[0]}",  f"Expected 1 winner, got {winners}")
    check(len(losers)  == 1,           f"Exactly 1 loser: INSUFFICIENT_STOCK", f"Expected 1 loser, got {losers}")
    check(current >= 0,                f"current_stock ≥ 0 ({current})",   f"current_stock went negative ({current})")
    check(current + reserved == 10,    f"Physical stock conserved (10)",    f"Stock leaked! current+reserved={current+reserved}")
    check(results[losers[0]].get("error_code") == "INSUFFICIENT_STOCK",
          "Loser got INSUFFICIENT_STOCK", f"Loser got wrong error: {results[losers[0]].get('error_code')}")

    cleanup(bill_nongst, bill_gst)
    set_stock(24, 0)
    print("  RESULT: PASSED")


# ==============================================================================
# CROSS-SYSTEM TEST 2
# NON_GST reserves 5, GST reserves 7, stock=12 — BOTH succeed
# ==============================================================================
def cross_test_2_both_succeed():
    header("CROSS TEST 2: NON_GST=5 + GST=7 = 12, stock=12 → both succeed")

    set_stock(12, 0)
    ts = int(time.time() * 1000)
    bill_nongst = f"NONGST-C2-{ts}"
    bill_gst    = f"GST-C2-{ts}"

    results = {}
    t1 = threading.Thread(target=rpc_reserve, args=("NON_GST_ERP", bill_nongst, 5, results, "NON_GST"))
    t2 = threading.Thread(target=rpc_reserve, args=("GST_ERP",     bill_gst,    7, results, "GST"))
    t1.start(); t2.start()
    t1.join();  t2.join()

    nongst = results["NON_GST"]
    gst    = results["GST"]

    print(f"  NON_GST_ERP: success={nongst.get('success')} qty={nongst.get('reserved_quantity')}")
    print(f"  GST_ERP:     success={gst.get('success')}    qty={gst.get('reserved_quantity')}")

    current, reserved = get_stock()
    print(f"  DB stock after: current={current} reserved={reserved}")

    check(nongst.get("success"),      "NON_GST_ERP succeeded",      f"NON_GST_ERP failed: {nongst.get('error_code')}")
    check(gst.get("success"),         "GST_ERP succeeded",          f"GST_ERP failed: {gst.get('error_code')}")
    check(current == 0,               "current_stock = 0",          f"current_stock = {current}, expected 0")
    check(reserved == 12,             "reserved_stock = 12",        f"reserved_stock = {reserved}, expected 12")

    cleanup(bill_nongst, bill_gst)
    set_stock(24, 0)
    print("  RESULT: PASSED")


# ==============================================================================
# CROSS-SYSTEM TEST 3
# NON_GST holds reservation, GST tries to cancel it — should fail
# source_app isolation: each app can only see its own reservations
# ==============================================================================
def cross_test_3_source_app_isolation():
    header("CROSS TEST 3: source_app isolation — GST cannot release NON_GST reservation")

    set_stock(10, 0)
    ts = int(time.time() * 1000)
    bill_nongst = f"NONGST-C3-{ts}"

    # NON_GST reserves
    r = client().rpc("reserve_stock", {
        "p_product_id": PRODUCT_ID, "p_bill_id": bill_nongst,
        "p_user_id": "", "p_source_app": "NON_GST_ERP", "p_quantity": 5.0
    }).execute()
    res_data = r.data[0] if isinstance(r.data, list) else r.data
    assert res_data.get("success"), f"Reserve failed: {res_data}"
    res_id = res_data["reservation_id"]
    print(f"  NON_GST_ERP reserved 5 units (res_id={res_id})")

    # GST tries to release NON_GST's bill using release_bill_reservations
    # It passes the NON_GST bill_id but with GST source_app
    # The RPC should either release 0 or respect source_app filtering
    r2 = client().rpc("release_bill_reservations", {
        "p_bill_id":    bill_nongst,
        "p_source_app": "GST_ERP",       # wrong source_app
    }).execute()
    release_data = r2.data[0] if isinstance(r2.data, list) else r2.data
    print(f"  GST_ERP tried to release NON_GST bill: released_count={release_data.get('released_count')}")

    current, reserved = get_stock()
    print(f"  DB stock after GST release attempt: current={current} reserved={reserved}")

    check(reserved == 5,
          "NON_GST reservation protected — reserved_stock still 5",
          f"SECURITY ISSUE: GST_ERP released NON_GST reservation! reserved={reserved}")

    # Now NON_GST properly cancels its own bill
    client().rpc("release_bill_reservations", {
        "p_bill_id": bill_nongst, "p_source_app": "NON_GST_ERP"
    }).execute()
    current2, reserved2 = get_stock()
    check(reserved2 == 0, "NON_GST self-release worked", f"reserved={reserved2}, expected 0")

    cleanup(bill_nongst)
    set_stock(24, 0)
    print("  RESULT: PASSED")


# ==============================================================================
# CROSS-SYSTEM TEST 4
# Verify stock_reservations rows show correct source_app per ERP
# This confirms the GST ERP's rows are visible and distinguishable
# ==============================================================================
def cross_test_4_reservation_rows_distinguishable():
    header("CROSS TEST 4: Reservations are labelled by source_app correctly")

    set_stock(12, 0)
    ts = int(time.time() * 1000)
    bill_nongst = f"NONGST-C4-{ts}"
    bill_gst    = f"GST-C4-{ts}"

    # Both reserve sequentially (not concurrent — just checking labels)
    client().rpc("reserve_stock", {
        "p_product_id": PRODUCT_ID, "p_bill_id": bill_nongst,
        "p_user_id": "", "p_source_app": "NON_GST_ERP", "p_quantity": 5.0
    }).execute()

    client().rpc("reserve_stock", {
        "p_product_id": PRODUCT_ID, "p_bill_id": bill_gst,
        "p_user_id": "", "p_source_app": "GST_ERP", "p_quantity": 4.0
    }).execute()

    # Read the rows
    rows = client().table("stock_reservations").select(
        "bill_id, source_app, quantity, status"
    ).in_("bill_id", [bill_nongst, bill_gst]).execute()

    print(f"  Reservation rows in DB:")
    for row in rows.data:
        print(f"    bill_id={row['bill_id'][-10:]}... source_app={row['source_app']} qty={row['quantity']} status={row['status']}")

    nongst_rows = [r for r in rows.data if r["source_app"] == "NON_GST_ERP"]
    gst_rows    = [r for r in rows.data if r["source_app"] == "GST_ERP"]

    check(len(nongst_rows) == 1, "NON_GST_ERP row exists with correct source_app", "NON_GST_ERP row missing")
    check(len(gst_rows)    == 1, "GST_ERP row exists with correct source_app",     "GST_ERP row missing")
    check(nongst_rows[0]["quantity"] == 5, "NON_GST qty=5",    f"NON_GST qty={nongst_rows[0]['quantity']}")
    check(gst_rows[0]["quantity"]    == 4, "GST qty=4",        f"GST qty={gst_rows[0]['quantity']}")

    cleanup(bill_nongst, bill_gst)
    set_stock(24, 0)
    print("  RESULT: PASSED")


# ==============================================================================
# CROSS-SYSTEM TEST 5 — Full lifecycle cross-system
# NON_GST creates draft → reserves → GST also reserves remaining →
# NON_GST completes → GST cancels → check final state
# ==============================================================================
def cross_test_5_full_lifecycle():
    header("CROSS TEST 5: Full lifecycle — NON_GST completes, GST cancels")

    set_stock(15, 0)
    ts = int(time.time() * 1000)
    bill_nongst = f"NONGST-C5-{ts}"
    bill_gst    = f"GST-C5-{ts}"
    sb = client()

    # NON_GST: create draft + reserve 7
    sb.table("bill_drafts").insert({"id": bill_nongst, "source_app": "NON_GST_ERP", "status": "ACTIVE"}).execute()
    r1 = sb.rpc("reserve_stock", {"p_product_id": PRODUCT_ID, "p_bill_id": bill_nongst,
                                   "p_user_id": "", "p_source_app": "NON_GST_ERP", "p_quantity": 7.0}).execute()
    assert (r1.data[0] if isinstance(r1.data, list) else r1.data).get("success")
    print(f"  NON_GST_ERP reserved 7  → current={get_stock()[0]} reserved={get_stock()[1]}")

    # GST: create draft + reserve 5 (remaining=8, takes 5)
    sb.table("bill_drafts").insert({"id": bill_gst, "source_app": "GST_ERP", "status": "ACTIVE"}).execute()
    r2 = sb.rpc("reserve_stock", {"p_product_id": PRODUCT_ID, "p_bill_id": bill_gst,
                                   "p_user_id": "", "p_source_app": "GST_ERP", "p_quantity": 5.0}).execute()
    assert (r2.data[0] if isinstance(r2.data, list) else r2.data).get("success")
    print(f"  GST_ERP     reserved 5  → current={get_stock()[0]} reserved={get_stock()[1]}")

    # NON_GST: COMPLETE (bill saved) → reserved_stock -= 7, current stays
    c1 = sb.rpc("complete_bill_reservations", {"p_bill_id": bill_nongst, "p_source_app": "NON_GST_ERP"}).execute()
    sb.table("bill_drafts").update({"status": "COMPLETED"}).eq("id", bill_nongst).execute()
    current, reserved = get_stock()
    print(f"  NON_GST_ERP COMPLETED   → current={current} reserved={reserved}")
    check(reserved == 5,  "Only GST reservation remains (5)", f"reserved={reserved}, expected 5")

    # GST: CANCEL (bill abandoned) → current_stock += 5, reserved_stock -= 5
    c2 = sb.rpc("release_bill_reservations", {"p_bill_id": bill_gst, "p_source_app": "GST_ERP"}).execute()
    sb.table("bill_drafts").update({"status": "CANCELLED"}).eq("id", bill_gst).execute()
    current, reserved = get_stock()
    print(f"  GST_ERP     CANCELLED   → current={current} reserved={reserved}")
    check(reserved == 0,   "All reservations settled",        f"reserved={reserved}, expected 0")
    check(current == 8,    "current_stock = 15 - 7 = 8",     f"current={current}, expected 8")

    cleanup(bill_nongst, bill_gst)
    set_stock(24, 0)
    print("  RESULT: PASSED")


# ==============================================================================
# SUMMARY
# ==============================================================================
if __name__ == "__main__":
    print("\n" + "═"*58)
    print("  NON_GST_ERP × GST_ERP — Cross-System Concurrency Tests")
    print("  Shared Supabase DB:", URL)
    print("  Product: Avt Tea 1/2 Kg")
    print("  Note: stock is temporarily modified, restored after each test")
    print("═"*58)

    tests = [
        ("CROSS TEST 1 — Only one wins when both exceed stock",   cross_test_1_one_wins),
        ("CROSS TEST 2 — Both succeed when total fits",           cross_test_2_both_succeed),
        ("CROSS TEST 3 — source_app isolation",                   cross_test_3_source_app_isolation),
        ("CROSS TEST 4 — Reservation rows labelled correctly",    cross_test_4_reservation_rows_distinguishable),
        ("CROSS TEST 5 — Full lifecycle",                         cross_test_5_full_lifecycle),
    ]

    passed = failed = 0
    for name, fn in tests:
        try:
            fn()
            passed += 1
        except AssertionError as e:
            print(f"\n  ✗ FAILED: {e}")
            failed += 1
        except Exception as e:
            print(f"\n  ✗ ERROR: {type(e).__name__}: {e}")
            failed += 1

    print(f"\n{'═'*58}")
    print(f"  Final: {passed} passed  |  {failed} failed")
    print(f"{'═'*58}\n")
    sys.exit(0 if failed == 0 else 1)

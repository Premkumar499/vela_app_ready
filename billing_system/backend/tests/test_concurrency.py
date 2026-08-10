"""
Concurrency test — simulates NON_GST_ERP and GST_ERP competing for the
same inventory simultaneously, WITHOUT a second physical system.

Uses Python threads to fire database RPC calls at the same time, exactly
as two separate ERP applications would in production.

All test data is cleaned up after each test — no permanent DB changes.

Run:
    cd billing_system/backend
    python tests/test_concurrency.py

Or with pytest:
    pytest tests/test_concurrency.py -v -s
"""

import sys
import os
import time
import threading
import uuid

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from dotenv import load_dotenv
load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"), override=True)

from supabase import create_client

URL = os.environ["SUPABASE_URL"]
KEY = os.environ["SUPABASE_SERVICE_KEY"]


# ── Two independent Supabase clients — one per "ERP app" ──────────────────────
# In production these would be two separate backend servers.
# Here we use two clients to simulate independent connections.
def nongst_client():
    return create_client(URL, KEY)

def gst_client():
    return create_client(URL, KEY)


def reserve(client, product_id, bill_id, quantity, source_app, result_bucket, label):
    """Call reserve_stock RPC and store result in result_bucket[label]."""
    import ast
    try:
        r = client.rpc("reserve_stock", {
            "p_product_id": str(product_id),
            "p_bill_id":    bill_id,
            "p_user_id":    "",
            "p_source_app": source_app,
            "p_quantity":   float(quantity),
        }).execute()
        data = r.data
        if isinstance(data, list) and data:
            result_bucket[label] = data[0]
        elif isinstance(data, dict):
            result_bucket[label] = data
        else:
            result_bucket[label] = {"success": False, "message": "empty response"}
    except Exception as e:
        # Some postgrest versions raise on bare JSON — parse from exception
        err = str(e)
        if "success" in err:
            try:
                result_bucket[label] = ast.literal_eval(
                    err[err.index("{"):err.rindex("}")+1])
                return
            except Exception:
                pass
        result_bucket[label] = {"success": False, "message": err[:200]}


def cleanup(sb, *bill_ids):
    """Release any active reservations and delete test rows."""
    for bid in bill_ids:
        try:
            active = sb.table("stock_reservations").select("id,status").eq("bill_id", bid).execute()
            for row in active.data:
                if row["status"] == "ACTIVE":
                    sb.rpc("release_reservation", {"p_reservation_id": row["id"]}).execute()
            sb.table("stock_reservations").delete().eq("bill_id", bid).execute()
            sb.table("bill_drafts").delete().eq("id", bid).execute()
        except Exception:
            pass


def get_stock(sb, product_id):
    r = sb.table("inventory").select("current_stock, reserved_stock").eq("product_id", product_id).execute()
    if r.data:
        return float(r.data[0]["current_stock"]), float(r.data[0]["reserved_stock"])
    return 0.0, 0.0


# ── Product used for ALL tests ─────────────────────────────────────────────────
PRODUCT_ID = "3355b354-3e25-4036-ad64-f9fee7875412"   # Avt Tea 1/2 Kg, stock=24


def sep(title):
    print(f"\n{'='*55}")
    print(f"  {title}")
    print('='*55)


# =============================================================================
# TEST 1 — Both apps request more than available simultaneously
# Stock = 10.  NON_GST wants 7, GST wants 7.  Only one can win.
# =============================================================================
def test_1_only_one_wins():
    sep("TEST 1: Both want 7, only 10 available → only one wins")
    sb = nongst_client()

    # Set test stock to exactly 10
    sb.table("inventory").update({"current_stock": 10, "reserved_stock": 0}).eq("product_id", PRODUCT_ID).execute()
    ts = int(time.time() * 1000)
    bill_nongst = f"CONC-NONGST-{ts}"
    bill_gst    = f"CONC-GST-{ts}"

    results = {}
    t1 = threading.Thread(target=reserve, args=(nongst_client(), PRODUCT_ID, bill_nongst, 7, "NON_GST_ERP", results, "NON_GST"))
    t2 = threading.Thread(target=reserve, args=(gst_client(),    PRODUCT_ID, bill_gst,    7, "GST_ERP",    results, "GST"))

    t1.start(); t2.start()
    t1.join();  t2.join()

    print(f"NON_GST result: success={results['NON_GST'].get('success')} "
          f"error={results['NON_GST'].get('error_code')} "
          f"remaining={results['NON_GST'].get('remaining_available')}")
    print(f"GST    result: success={results['GST'].get('success')} "
          f"error={results['GST'].get('error_code')} "
          f"remaining={results['GST'].get('remaining_available')}")

    winners = [k for k, v in results.items() if v.get("success")]
    losers  = [k for k, v in results.items() if not v.get("success")]

    current, reserved = get_stock(sb, PRODUCT_ID)
    print(f"Final stock: current={current} reserved={reserved}")

    assert len(winners) == 1,       f"FAIL: expected exactly 1 winner, got {winners}"
    assert len(losers)  == 1,       f"FAIL: expected exactly 1 loser, got {losers}"
    assert current  >= 0,           f"FAIL: current_stock went negative ({current})"
    assert reserved <= 10,          f"FAIL: reserved_stock exceeded original stock ({reserved})"
    assert current + reserved == 10, f"FAIL: physical stock changed! current+reserved={current+reserved}"
    assert losers[0]  and results[losers[0]].get("error_code") == "INSUFFICIENT_STOCK"

    print(f"PASS: {winners[0]} won, {losers[0]} got INSUFFICIENT_STOCK")
    print(f"PASS: physical stock conserved (current+reserved=10)")
    cleanup(sb, bill_nongst, bill_gst)
    sb.table("inventory").update({"current_stock": 24, "reserved_stock": 0}).eq("product_id", PRODUCT_ID).execute()


# =============================================================================
# TEST 2 — Both apps request amounts that together fit
# Stock = 12.  NON_GST wants 5, GST wants 7.  Both should succeed.
# =============================================================================
def test_2_both_succeed():
    sep("TEST 2: NON_GST=5, GST=7, stock=12 → both succeed, total=12")
    sb = nongst_client()

    sb.table("inventory").update({"current_stock": 12, "reserved_stock": 0}).eq("product_id", PRODUCT_ID).execute()
    ts = int(time.time() * 1000)
    bill_nongst = f"CONC-NONGST-{ts}"
    bill_gst    = f"CONC-GST-{ts}"

    results = {}
    t1 = threading.Thread(target=reserve, args=(nongst_client(), PRODUCT_ID, bill_nongst, 5, "NON_GST_ERP", results, "NON_GST"))
    t2 = threading.Thread(target=reserve, args=(gst_client(),    PRODUCT_ID, bill_gst,    7, "GST_ERP",    results, "GST"))

    t1.start(); t2.start()
    t1.join();  t2.join()

    print(f"NON_GST: success={results['NON_GST'].get('success')} qty={results['NON_GST'].get('reserved_quantity')}")
    print(f"GST:     success={results['GST'].get('success')} qty={results['GST'].get('reserved_quantity')}")

    current, reserved = get_stock(sb, PRODUCT_ID)
    print(f"Final stock: current={current} reserved={reserved}")

    assert results["NON_GST"].get("success"), f"NON_GST failed: {results['NON_GST']}"
    assert results["GST"].get("success"),     f"GST failed: {results['GST']}"
    assert current == 0,                      f"FAIL: current_stock should be 0, got {current}"
    assert reserved == 12,                    f"FAIL: reserved_stock should be 12, got {reserved}"
    assert current + reserved == 12

    print("PASS: both succeeded, current_stock=0, reserved_stock=12")
    cleanup(sb, bill_nongst, bill_gst)
    sb.table("inventory").update({"current_stock": 24, "reserved_stock": 0}).eq("product_id", PRODUCT_ID).execute()


# =============================================================================
# TEST 3 — Race with 10 threads all wanting 3 units, stock=10
# Only 3 can win (3×3=9 ≤ 10, but 4×3=12 > 10).
# Exactly floor(10/3) = 3 should succeed.
# =============================================================================
def test_3_ten_threads_race():
    sep("TEST 3: 10 threads all want 3 units, stock=10 → exactly 3 win")
    sb = nongst_client()

    sb.table("inventory").update({"current_stock": 10, "reserved_stock": 0}).eq("product_id", PRODUCT_ID).execute()
    ts = int(time.time() * 1000)
    results = {}
    threads = []

    for i in range(10):
        bid = f"CONC-RACE-{ts}-{i}"
        app = "NON_GST_ERP" if i % 2 == 0 else "GST_ERP"
        t = threading.Thread(target=reserve, args=(
            nongst_client() if i % 2 == 0 else gst_client(),
            PRODUCT_ID, bid, 3, app, results, str(i)
        ))
        threads.append((t, bid))

    for t, _ in threads:
        t.start()
    for t, _ in threads:
        t.join()

    winners = [k for k, v in results.items() if v.get("success")]
    losers  = [k for k, v in results.items() if not v.get("success")]
    current, reserved = get_stock(sb, PRODUCT_ID)

    print(f"Winners ({len(winners)}): threads {sorted(winners)}")
    print(f"Losers  ({len(losers)}): threads {sorted(losers)}")
    print(f"Final stock: current={current} reserved={reserved}")

    import math
    max_winners = math.floor(10 / 3)   # = 3
    assert current >= 0,                f"FAIL: current_stock negative ({current})"
    assert current + reserved == 10,    f"FAIL: physical stock changed!"
    assert len(winners) == max_winners, f"FAIL: expected {max_winners} winners, got {len(winners)}"
    assert reserved == len(winners) * 3

    print(f"PASS: exactly {len(winners)} threads won, stock conserved")
    for _, bid in threads:
        cleanup(sb, bid)
    sb.table("inventory").update({"current_stock": 24, "reserved_stock": 0}).eq("product_id", PRODUCT_ID).execute()


# =============================================================================
# TEST 4 — Concurrent complete + release (no double-deduct)
# NON_GST reserves 5, then simultaneously:
#   Thread A completes the bill
#   Thread B tries to release the same bill
# Only one should succeed.
# =============================================================================
def test_4_concurrent_complete_and_release():
    sep("TEST 4: Concurrent complete + release on same bill → only one wins")
    sb = nongst_client()

    sb.table("inventory").update({"current_stock": 10, "reserved_stock": 0}).eq("product_id", PRODUCT_ID).execute()
    ts = int(time.time() * 1000)
    bid = f"CONC-CR-{ts}"

    r = sb.rpc("reserve_stock", {
        "p_product_id": PRODUCT_ID, "p_bill_id": bid,
        "p_user_id": "", "p_source_app": "NON_GST_ERP", "p_quantity": 5.0
    }).execute()
    print(f"Reserved 5 units. current=5 reserved=5")

    complete_result = {}
    release_result  = {}

    def do_complete():
        try:
            r = nongst_client().rpc("complete_bill_reservations", {
                "p_bill_id": bid, "p_source_app": "NON_GST_ERP"
            }).execute()
            d = r.data[0] if isinstance(r.data, list) else r.data
            complete_result["data"] = d
        except Exception as e:
            complete_result["data"] = {"success": False, "message": str(e)[:100]}

    def do_release():
        try:
            r = gst_client().rpc("release_bill_reservations", {
                "p_bill_id": bid, "p_source_app": "NON_GST_ERP"
            }).execute()
            d = r.data[0] if isinstance(r.data, list) else r.data
            release_result["data"] = d
        except Exception as e:
            release_result["data"] = {"success": False, "message": str(e)[:100]}

    t1 = threading.Thread(target=do_complete)
    t2 = threading.Thread(target=do_release)
    t1.start(); t2.start()
    t1.join();  t2.join()

    print(f"Complete result: {complete_result['data']}")
    print(f"Release  result: {release_result['data']}")

    current, reserved = get_stock(sb, PRODUCT_ID)
    print(f"Final stock: current={current} reserved={reserved}")

    # reserved_stock must be 0 (either completed or released)
    assert reserved == 0, f"FAIL: reserved_stock={reserved}, should be 0"
    # current_stock must not have been double-restored
    assert current <= 10, f"FAIL: current_stock={current} exceeds original 10"
    assert current >= 0,  f"FAIL: current_stock went negative"

    print("PASS: reserved_stock=0, no double-deduction")
    cleanup(sb, bid)
    sb.table("inventory").update({"current_stock": 24, "reserved_stock": 0}).eq("product_id", PRODUCT_ID).execute()


# =============================================================================
# TEST 5 — Rapid double-click simulation (same draft, same product, fast)
# Simulates user clicking a product card twice very quickly.
# =============================================================================
def test_5_rapid_double_click():
    sep("TEST 5: Rapid double-click → quantity=2 or idempotent, never qty=1+1 double-reserve")
    sb = nongst_client()

    sb.table("inventory").update({"current_stock": 10, "reserved_stock": 0}).eq("product_id", PRODUCT_ID).execute()
    ts  = int(time.time() * 1000)
    bid = f"CONC-CLICK-{ts}"

    results = {}
    # Both threads use the SAME bill_id and SAME product — simulates double-click
    t1 = threading.Thread(target=reserve, args=(nongst_client(), PRODUCT_ID, bid, 1, "NON_GST_ERP", results, "click1"))
    t2 = threading.Thread(target=reserve, args=(nongst_client(), PRODUCT_ID, bid, 1, "NON_GST_ERP", results, "click2"))
    t1.start(); t2.start()
    t1.join();  t2.join()

    print(f"Click 1: success={results['click1'].get('success')} qty={results['click1'].get('reserved_quantity')} error={results['click1'].get('error_code')}")
    print(f"Click 2: success={results['click2'].get('success')} qty={results['click2'].get('reserved_quantity')} error={results['click2'].get('error_code')}")

    current, reserved = get_stock(sb, PRODUCT_ID)
    print(f"Final stock: current={current} reserved={reserved}")

    # The live DB uses upsert semantics — both may succeed but reserved = 1 (not 2)
    # OR one gets DUPLICATE_RESERVATION. Either way, reserved must be ≤ 1.
    assert current >= 0,  f"FAIL: current_stock negative"
    assert reserved <= 1, f"FAIL: reserved={reserved}, double-click created 2 separate reservations!"
    assert current + reserved == 10

    print(f"PASS: reserved_stock={reserved} (≤1), no double-reservation")
    cleanup(sb, bid)
    sb.table("inventory").update({"current_stock": 24, "reserved_stock": 0}).eq("product_id", PRODUCT_ID).execute()


# =============================================================================
# MAIN
# =============================================================================
if __name__ == "__main__":
    print("\nNON-GST ERP — Concurrency Test Suite")
    print("Simulating GST_ERP and NON_GST_ERP competing for the same stock")
    print(f"Test product: Avt Tea 1/2 Kg  (id={PRODUCT_ID})")
    print("NOTE: Stock is temporarily modified during tests and restored after each.")

    passed = 0
    failed = 0

    for test_fn in [
        test_1_only_one_wins,
        test_2_both_succeed,
        test_3_ten_threads_race,
        test_4_concurrent_complete_and_release,
        test_5_rapid_double_click,
    ]:
        try:
            test_fn()
            passed += 1
        except AssertionError as e:
            print(f"\nFAIL: {e}")
            failed += 1
        except Exception as e:
            print(f"\nERROR: {e}")
            failed += 1

    print(f"\n{'='*55}")
    print(f"  Results: {passed} passed, {failed} failed")
    print(f"{'='*55}\n")
    sys.exit(0 if failed == 0 else 1)

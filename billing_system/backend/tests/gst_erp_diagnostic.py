"""
GST ERP Diagnostic Script
=========================
Your friend runs this on THEIR system to verify:
  1. They connect to the SAME Supabase database
  2. They use source_app = 'GST_ERP'
  3. Their reserve_stock RPC call signature matches
  4. Their bill_drafts integration works
  5. Their stock_reservations table is shared

Share this file with your friend. They run:
    python gst_erp_diagnostic.py

Then share the output with you.
"""

import sys

print("=" * 60)
print("  GST ERP — Shared Database Diagnostic")
print("=" * 60)

# ── Step 1: Check Supabase connection ─────────────────────────
print("\n[1] Checking Supabase connection...")
try:
    from supabase import create_client
except ImportError:
    print("  FAIL: supabase-py not installed. Run: pip install supabase")
    sys.exit(1)

# Your friend fills these in from THEIR .env
SUPABASE_URL = input("  Enter your SUPABASE_URL: ").strip()
SUPABASE_KEY = input("  Enter your SUPABASE_SERVICE_KEY: ").strip()

try:
    sb = create_client(SUPABASE_URL, SUPABASE_KEY)
    print("  OK: Supabase client created")
except Exception as e:
    print(f"  FAIL: Cannot create client: {e}")
    sys.exit(1)

# ── Step 2: Verify it's the SAME database ─────────────────────
print("\n[2] Verifying shared database tables exist...")
REQUIRED_TABLES = ["stock_reservations", "inventory", "bill_drafts"]
missing = []
for table in REQUIRED_TABLES:
    try:
        r = sb.table(table).select("*").limit(1).execute()
        print(f"  OK: {table} exists")
    except Exception as e:
        print(f"  FAIL: {table} missing or inaccessible: {e}")
        missing.append(table)

if missing:
    print(f"\n  PROBLEM: Tables missing: {missing}")
    print("  FIX: Make sure you are connecting to the SAME Supabase project as NON_GST_ERP")
    print(f"  Expected URL: https://bvbbrmeodshclwwvvtbc.supabase.co")
    print(f"  Your URL:     {SUPABASE_URL}")
    if SUPABASE_URL != "https://bvbbrmeodshclwwvvtbc.supabase.co":
        print("  !! URLs do not match — you are on a DIFFERENT database !!")

# ── Step 3: Check source_app value ────────────────────────────
print("\n[3] Checking source_app value...")
SOURCE_APP = input("  What source_app value does your system use? (should be GST_ERP): ").strip()
if SOURCE_APP != "GST_ERP":
    print(f"  WARN: source_app='{SOURCE_APP}' — expected 'GST_ERP'")
    print("  FIX: Change your source_app constant to 'GST_ERP'")
else:
    print(f"  OK: source_app = {SOURCE_APP}")

# ── Step 4: Test reserve_stock RPC signature ──────────────────
print("\n[4] Testing reserve_stock RPC (will immediately release)...")
PRODUCT_ID = "3355b354-3e25-4036-ad64-f9fee7875412"  # shared test product
import time, ast
DRAFT_ID = f"GST-DIAG-{int(time.time() * 1000)}"

reserve_result = None
try:
    r = sb.rpc("reserve_stock", {
        "p_product_id": PRODUCT_ID,
        "p_bill_id":    DRAFT_ID,
        "p_user_id":    "",
        "p_source_app": SOURCE_APP,
        "p_quantity":   1.0,
    }).execute()
    data = r.data
    if isinstance(data, list) and data:
        reserve_result = data[0]
    elif isinstance(data, dict):
        reserve_result = data
    print(f"  OK: reserve_stock called successfully")
    print(f"  Result: {reserve_result}")
except Exception as e:
    err = str(e)
    # Try to extract from APIError
    if "success" in err:
        try:
            reserve_result = ast.literal_eval(err[err.index("{"):err.rindex("}")+1])
        except Exception:
            pass
    if reserve_result:
        print(f"  OK (parsed from exception): {reserve_result}")
    else:
        print(f"  FAIL: reserve_stock error: {err[:300]}")
        print("  FIX: Check your RPC param names — should be p_product_id, p_bill_id, p_user_id, p_source_app, p_quantity")

# ── Step 5: Release the test reservation ──────────────────────
if reserve_result and reserve_result.get("success"):
    res_id = reserve_result.get("reservation_id")
    print(f"\n[5] Releasing test reservation {res_id}...")
    try:
        sb.rpc("release_reservation", {"p_reservation_id": res_id}).execute()
        print("  OK: released")
    except Exception as e:
        print(f"  WARN: release failed (check manually): {e}")
    # cleanup
    sb.table("stock_reservations").delete().eq("bill_id", DRAFT_ID).execute()
    sb.table("bill_drafts").delete().eq("id", DRAFT_ID).execute()
elif reserve_result and not reserve_result.get("success"):
    print(f"\n[5] Reserve failed (no cleanup needed). Error: {reserve_result.get('error_code')}")
    if reserve_result.get("error_code") == "INSUFFICIENT_STOCK":
        print("  NOTE: Test product has no stock. This is expected if stock=0.")
        print("  Concurrency tests will still work once stock is present.")

# ── Step 6: Check bill_drafts source_app constraint ───────────
print("\n[6] Testing bill_drafts insert with GST_ERP source_app...")
TEST_DRAFT_ID = f"GST-DRAFT-DIAG-{int(time.time() * 1000)}"
try:
    r = sb.table("bill_drafts").insert({
        "id":         TEST_DRAFT_ID,
        "source_app": SOURCE_APP,
        "status":     "ACTIVE",
    }).execute()
    print(f"  OK: bill_drafts accepts source_app={SOURCE_APP}")
    sb.table("bill_drafts").delete().eq("id", TEST_DRAFT_ID).execute()
except Exception as e:
    print(f"  FAIL: {e}")
    if "check constraint" in str(e).lower():
        print("  FIX: bill_drafts check constraint does not allow this source_app value")
        print(f"  Run in Supabase SQL Editor:")
        print(f"    ALTER TABLE bill_drafts DROP CONSTRAINT bill_drafts_status_check;")
        print(f"    -- Then re-add with correct values including {SOURCE_APP}")

# ── Step 7: Check inventory columns ───────────────────────────
print("\n[7] Checking inventory table columns...")
try:
    r = sb.table("inventory").select("product_id, current_stock, reserved_stock").limit(1).execute()
    if r.data:
        print(f"  OK: inventory has current_stock and reserved_stock columns")
        print(f"  Sample: {r.data[0]}")
    else:
        print("  WARN: inventory table is empty")
except Exception as e:
    print(f"  FAIL: {e}")
    print("  FIX: Run migration 0005 in Supabase SQL Editor")

# ── Step 8: Summary ───────────────────────────────────────────
print("\n" + "=" * 60)
print("  DIAGNOSTIC COMPLETE")
print("=" * 60)
print("""
Share this full output with your NON_GST_ERP developer.
They will use it to run the live cross-system concurrency test.

Key values needed:
  - Your SUPABASE_URL (confirm it matches NON_GST_ERP)
  - Your source_app value
  - Whether reserve_stock succeeded or failed
  - Any errors above
""")

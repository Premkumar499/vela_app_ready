import os
import sys
import uuid
import time
import threading
from dotenv import load_dotenv

# Ensure backend imports work
backend_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.append(backend_dir)

from services.reservation_service import reservation_service, _get_supabase

def run_production_tests():
    sb = _get_supabase()
    
    # 1. Fetch/Ensure a test product exists in the DB
    prod_resp = sb.table("products").select("product_id, product_name").limit(1).execute()
    if not prod_resp.data:
        print("[-] Production check failed: No products found in the database.")
        sys.exit(1)
        
    product_id = prod_resp.data[0]["product_id"]
    product_name = prod_resp.data[0]["product_name"]
    print(f"[+] Using product for verification: '{product_name}' ({product_id})")
    
    # Get current stock state
    stock_info = reservation_service.get_stock_info(product_id)
    if not stock_info.get("success"):
        print(f"[-] Failed to fetch stock info: {stock_info.get('message')}")
        sys.exit(1)
        
    original_current = stock_info["current_stock"]
    original_reserved = stock_info["reserved_stock"]
    print(f"[+] Initial Stock State - Current: {original_current}, Reserved: {original_reserved}")
    
    # Setup sufficient stock for testing
    test_start_current = max(original_current, 50.0)
    sb.table("inventory").update({
        "current_stock": test_start_current,
        "reserved_stock": original_reserved
    }).eq("product_id", product_id).execute()
    print(f"[+] Setup test stock: Current set to {test_start_current}")
    
    try:
        # -------------------------------------------------------------------------
        # SCENARIO 1: Simple Atomic Stock Reservation (Success Path)
        # -------------------------------------------------------------------------
        print("\n--- Running Scenario 1: Atomic Stock Reservation ---")
        test_bill_1 = f"PROD-TEST-{int(time.time())}-1"
        res1 = reservation_service.reserve_stock(
            product_id=product_id,
            bill_id=test_bill_1,
            quantity=5.0
        )
        
        if not res1.get("success"):
            print(f"[-] Scenario 1 Failed: {res1.get('message')}")
            sys.exit(1)
            
        reservation_id_1 = res1.get("reservation_id")
        print(f"[+] Scenario 1 Success: Reserved 5.0 units. Reservation ID: {reservation_id_1}")
        
        # Verify inventory table reflected changes
        stock_info = reservation_service.get_stock_info(product_id)
        assert stock_info["current_stock"] == test_start_current - 5.0
        assert stock_info["reserved_stock"] == original_reserved + 5.0
        print("[+] Verified Scenario 1 DB balance changes.")
        
        # -------------------------------------------------------------------------
        # SCENARIO 2: Insufficient Stock Prevention (Failure Path)
        # -------------------------------------------------------------------------
        print("\n--- Running Scenario 2: Insufficient Stock Protection ---")
        test_bill_2 = f"PROD-TEST-{int(time.time())}-2"
        over_request = stock_info["current_stock"] + 10.0
        res2 = reservation_service.reserve_stock(
            product_id=product_id,
            bill_id=test_bill_2,
            quantity=over_request
        )
        
        if res2.get("success"):
            print("[-] Scenario 2 Failed: Reserved more stock than available!")
            sys.exit(1)
        else:
            print(f"[+] Scenario 2 Success: Blocked over-reservation. Message: {res2.get('message')}")
            
        # -------------------------------------------------------------------------
        # SCENARIO 3: Concurrency Race Condition (Simultaneous Reservation Requests)
        # -------------------------------------------------------------------------
        print("\n--- Running Scenario 3: Real-Time Parallel Concurrency Race ---")
        # Temporarily set current stock to exactly 10 units for the race test
        sb.table("inventory").update({"current_stock": 10.0}).eq("product_id", product_id).execute()
        
        race_results = []
        barrier = threading.Barrier(2)
        
        def race_worker(bill_suffix, quantity):
            bill_id = f"PROD-RACE-{int(time.time())}-{bill_suffix}"
            barrier.wait() # Coordinate execution at the exact same millisecond
            res = reservation_service.reserve_stock(
                product_id=product_id,
                bill_id=bill_id,
                quantity=quantity
            )
            race_results.append((bill_id, res))
            
        # Thread A wants 7 units, Thread B wants 7 units (Total 14, but only 10 available)
        # Only one thread must succeed; the other must get rejected.
        t_a = threading.Thread(target=race_worker, args=("A", 7.0))
        t_b = threading.Thread(target=race_worker, args=("B", 7.0))
        
        t_a.start()
        t_b.start()
        t_a.join()
        t_b.join()
        
        success_threads = [r for r in race_results if r[1].get("success") is True]
        fail_threads = [r for r in race_results if r[1].get("success") is False]
        
        print(f"[+] Race completed. Success count: {len(success_threads)}, Failure count: {len(fail_threads)}")
        for bill, res in race_results:
            print(f"    - Bill {bill}: Success={res.get('success')}, Msg={res.get('message') or 'Success'}")
            
        if len(success_threads) != 1 or len(fail_threads) != 1:
            print("[-] Scenario 3 Failed: Race condition permitted duplicate reservations or blocked both!")
            sys.exit(1)
        else:
            print("[+] Scenario 3 Success: Transaction isolation and FOR UPDATE locking successfully prevented double selling.")
            
        # -------------------------------------------------------------------------
        # SCENARIO 4: Reservation Release (Stock Restoration)
        # -------------------------------------------------------------------------
        print("\n--- Running Scenario 4: Reservation Release (Restoration) ---")
        winner_res_id = success_threads[0][1].get("reservation_id")
        release_res = reservation_service.release_reservation(winner_res_id)
        
        if not release_res.get("success"):
            print(f"[-] Scenario 4 Failed: {release_res.get('message')}")
            sys.exit(1)
        else:
            print("[+] Scenario 4 Success: Released winning race reservation. Stock restored.")
            
    finally:
        # -------------------------------------------------------------------------
        # CLEANUP & RESET
        # -------------------------------------------------------------------------
        print("\n--- Running Cleanup and Restoring Original Stock state ---")
        # Try to release Scenario 1 reservation if created
        try:
            if 'reservation_id_1' in locals():
                reservation_service.release_reservation(reservation_id_1)
        except Exception:
            pass
        
        # Restore original database quantities
        sb.table("inventory").update({
            "current_stock": original_current,
            "reserved_stock": original_reserved
        }).eq("product_id", product_id).execute()
        
        # Delete test reservation records
        sb.table("stock_reservations").delete().like("bill_id", "PROD-TEST-%").execute()
        sb.table("stock_reservations").delete().like("bill_id", "PROD-RACE-%").execute()
        
        print("[+] Cleanup complete. Database restored successfully.")
        
    print("\n[★★★] PRODUCTION READINESS VERIFICATION PASSED SUCCESSFULLY! [★★★]")

if __name__ == "__main__":
    run_production_tests()

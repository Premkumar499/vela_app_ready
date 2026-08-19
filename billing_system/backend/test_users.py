import os
from dotenv import load_dotenv
from supabase import create_client

def main():
    _env_path = os.path.join(os.path.dirname(__file__), ".env")
    load_dotenv(_env_path, override=True)
    url = os.getenv("SUPABASE_URL", "")
    key = os.getenv("SUPABASE_SERVICE_KEY") or os.getenv("SUPABASE_SECRET_KEY") or ""
    if not url or not key:
        print("SUPABASE_URL or key not set in .env")
        return
    
    sb = create_client(url, key)
    resp = sb.table("users").select("full_name, mobile_number, role_id, is_active").execute()
    users = resp.data or []
    
    role_names = {1: "Admin", 2: "Admin", 3: "Billing Employee", 4: "Warehouse Manager"}
    
    print(f"\nFound {len(users)} users:")
    for u in users:
        role = role_names.get(u.get("role_id"), f"Role {u.get('role_id')}")
        print(f"- {u.get('full_name')} | Mobile: {u.get('mobile_number')} | Role: {role} | Active: {u.get('is_active')}")

if __name__ == "__main__":
    main()

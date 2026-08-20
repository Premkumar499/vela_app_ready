# 6. Supabase Database

Supabase (PostgreSQL) is the persistence layer. There are **two generations** of schema:

1. **Production schema** — `supabase/migrations/0001_init.sql` (canonical, ER-model).
2. **Live schema** — `billing_system/backend/supabase/migrations/0002_billing_tables.sql`
   + `0003_storage_buckets_policy.sql` (the tables the running app actually writes to).

The app currently uses **generation 2** (`erp_billing_system*` tables). The full
migration plan and import script for switching to generation 1 are documented in
`SUPABASE_DATABASE_ARCHITECTURE.md`.

---

## 6.1 Live schema (what the app uses today)

### `erp_billing_system` — user bill headers
| column | type | notes |
|--------|------|-------|
| `bill_id` | uuid PK | `gen_random_uuid()` |
| `business_name` | varchar(100) | default `'VELA AGENCY'` |
| `bill_no` | varchar(50) UNIQUE | e.g. `2026AUG08A161` |
| `bill_date` | date | |
| `bill_time` | time | |
| `payment_mode` | varchar(30) | CASH / CREDIT / UPI |
| `total_items` | integer | |
| `total_quantity` | numeric(10,2) | |
| `grand_total` | numeric(12,2) | |
| `created_at` | timestamptz | |

### `erp_billing_system_items` — user bill lines
`bill_item_id` uuid PK · `bill_id` uuid FK → `erp_billing_system` **ON DELETE CASCADE** ·
`sno` · `description` · `quantity` · `rate` · `amount`.

### `erp_billing_system_company` — company invoice headers
`invoice_id` uuid PK · `invoice_no` varchar UNIQUE · `invoice_date` · `invoice_time` ·
`customer_name` · `customer_phone` · `payment_mode` · `transaction_id` · `upi_id` ·
`total_amount` · `amount_in_words` · `created_at`.

### `erp_billing_system_company_items` — company invoice lines
`item_id` uuid PK · `invoice_id` uuid FK → `erp_billing_system_company`
**ON DELETE CASCADE** · `sno` · `description` · `unit` · `quantity` · `rate` · `amount`.

**RLS:** these tables have RLS **disabled** (see `0002`) so the service-role backend
can read/write freely.

### Storage buckets (`0003_storage_buckets_policy.sql`)
- `erp_billing_system` — customer bill PDFs (non-public, 50 MB limit, `application/pdf`).
- `erp_billing_system_company` — company invoice PDFs (same limits).
- Both buckets get a `service_role` full-access policy on `storage.objects`.

---

## 6.2 Production schema (`supabase/migrations/0001_init.sql`)

Designed to replace the JSON/in-memory storage with a proper relational model and to
support direct Flutter→Supabase access later.

### Tables

| Table | Purpose |
|-------|---------|
| `invoice_series` | Atomic counter per series (`INV`, padding 4 → `INV0001`) |
| `products` | Catalogue: name, unit, price, mrp, stock, category, description, barcode, is_active |
| `customers` | Buyer ledger: phone, address, area, gstin, credit_limit, balance, is_active |
| `bills` | Sale header: bill_number, customer snapshot, payment/sales type, computed totals, bill_date, status |
| `bill_items` | Sale lines: product snapshot, qty, rate, discount, gross/total |
| `held_bills` | "Hold" feature: full cart snapshot as JSONB |
| `audit_log` | Who did what (`CREATE` / `VOID` / hold operations) |

### Indexes & triggers
- `set_updated_at()` trigger updates `updated_at` on UPDATE for tables that have it.
- GIN trigram index on `products.name`; indexes on `category`, `barcode`, `bill_date`,
  `customer_id`, `created_at`, `payment_type`, etc.

### DB functions

**`next_invoice_number(p_series)`** — atomic, concurrency-safe numbering:
```sql
UPDATE invoice_series SET current_number = current_number + 1
WHERE series_prefix = p_series
RETURNING current_number, padding;
```
Returns `series + lpad(num, padding, '0')` (e.g. `INV0033`).

**`create_bill(...)`** — one transaction that does everything:
1. Validates ≥1 item and positive qty/rate.
2. Gets next invoice number.
3. Inserts `bills` header.
4. Loops lines: **atomic stock deduction** (`WHERE stock >= qty`, refuses overselling),
   computes gross/discount/total, inserts `bill_items`.
5. Updates computed totals on the header.
6. Writes an `audit_log` row.
7. Returns the full bill (header + items) as JSONB.

**`void_bill(bill_number)`** — restores stock, marks `voided`, writes audit row.

### Reporting views
- `v_daily_sales` — `bill_date`, bill count, sales, discounts, qty (active bills only).
- `v_top_products` — qty sold + revenue per product (active bills only).

### RLS
All 7 tables have RLS enabled with a permissive `app_all_<table>` policy for
`authenticated` users. When the Flask backend uses the **service-role key**, RLS is
bypassed automatically. RLS matters only if the Flutter app later talks directly to
Supabase with an anon/user key.

---

## 6.3 Data migration plan (current → production)

`SUPABASE_DATABASE_ARCHITECTURE.md` §7 provides a one-time loader that:
1. Upserts the 545-product catalogue (`services/sample_data.py`) preserving ids.
2. Upserts customers.
3. Re-inserts the existing bills from `data/bills.json` (header + items).
4. Syncs `invoice_series` to the max invoice number so the next number continues.

### `create_bill()` as the atomic answer to current bugs
Today's flow does three steps (number → insert → deduct stock) that can race or
partially fail. The DB function wraps everything in one atomic transaction — the
same guarantee as a SQLAlchemy session, and it makes **stock survive restarts**.

---

## 6.4 Helper tools

### `check_db.py`
Verifies that bills appear in **both** `erp_billing_system` and
`erp_billing_system_company`, compares them, and lists PDFs in both storage buckets.
Useful after a bug-fix to confirm end-to-end persistence.

Run:
```bash
python3 check_db.py   # reads billing_system/backend/.env
```

### `.env` variables (backend)
```
SUPABASE_URL=https://XXXX.supabase.co
SUPABASE_SERVICE_KEY=sb_secret_xxx    # (or SUPABASE_SECRET_KEY)
```

> ⚠️ Never commit the service key or put it in the Flutter client.

## Related docs

- [01 — Project Overview](01_project_overview.md)
- [04 — Backend Services](04_backend_services.md)
- [15 — Known Issues & Roadmap](15_known_issues_roadmap.md)
- [Supabase Connected Tables](supabase_tables_connected.md)
- [Supabase Stock Concurrency Setup Guide](supabase_concurrency_setup.md)

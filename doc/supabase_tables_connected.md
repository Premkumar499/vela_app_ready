# Supabase Connection & Tables — ERP Billing (NO GST)

> Analysis of **which Supabase tables this project is connected to, migrated, and linked**.
> Data collected from `billing_system/backend/supabase/migrations/*.sql` + live code usage (`routes/`, `services/`).

---

## 1. Connected Project

| Item | Value |
|---|---|
| **Supabase URL** | `https://bvbbrmeodshclwwvvtbc.supabase.co` (from `billing_system/backend/.env`) |
| **Auth mode** | Service Role / Secret Key (backend only, RLS bypassed), anon key allowed for `salesperson_bills` INSERT |
| **Storage buckets** | `erp_billing_system`, `erp_billing_system_company` (invoice PDFs), `product_image` (product photos) |

> Note: The DB is **shared with the GST ERP app**. Tables like `products`, `inventory`, `customers`, `bill_drafts`, `stock_reservations`, `bill_sequence`, `units`, `categories`, `brands`, `users` are common/shared contracts between `NON_GST_ERP` and `GST_ERP` (`source_app` column distinguishes them).

---

## 2. Table List — 13 tables used by this app

| # | Table | Purpose | Created by Migration |
|---|-------|---------|----------------------|
| 1 | `erp_billing_system` | User / customer bill header | `0002_billing_tables.sql`, `0007` |
| 2 | `erp_billing_system_items` | User bill line items | `0002_billing_tables.sql`, `0007` |
| 3 | `erp_billing_system_company` | Company invoice header | `0002_billing_tables.sql`, `0007` |
| 4 | `erp_billing_system_company_items` | Company invoice line items | `0002_billing_tables.sql`, `0007` |
| 5 | `products` | Product catalogue (shared with GST ERP) | external/shared schema |
| 6 | `inventory` | Stock per product (`current_stock`, `reserved_stock`) | external/shared, altered in `0005` |
| 7 | `customers` | Customer ledger | external/shared schema |
| 8 | `bill_drafts` | Billing session/draft tracker | external/shared schema |
| 9 | `stock_reservations` | Stock reservation / hold records | `0005_stock_reservations.sql`, `0011`, `0012` |
| 10 | `salesperson_bills` | Salesman pending-bill inbox | `0009_salesperson_bills.sql` |
| 11 | `bill_sequence` | Atomic bill numbering per prefix | `0010_next_bill_number.sql` |
| 12 | `users` | Login users (mobile = password) | external/shared schema |
| 13 | `categories`, `units`, `brands` (reference tables) | Product category / unit / brand names | external/shared schema |

---

## 3. Table Details & Links (ERD)

```
users ──┐ (auth)
bill_drafts 1 ──► stock_reservations (bill_id = draft id) ──► inventory ──► products
products 1 ──► erp_billing_system_items.product_id
products 1 ──► erp_billing_system_company_items.product_id
erp_billing_system 1 ──► erp_billing_system_items (bill_id, CASCADE)
erp_billing_system_company 1 ──► erp_billing_system_company_items (invoice_id, CASCADE)
```

### 3.1 `erp_billing_system` (user bill header)
| Column | Type | Notes |
|---|---|---|
| `bill_id` | UUID PK | `gen_random_uuid()` |
| `business_name` | VARCHAR(100) | default `VELA AGENCY` |
| `bill_no` | VARCHAR(50) UNIQUE | e.g. `INV0045` — minted via `next_bill_number()` |
| `bill_date`, `bill_time` | DATE, TIME | |
| `payment_mode` | VARCHAR(30) | Cash / Credit / UPI / Card |
| `customer_name`, `customer_phone` | TEXT | snapshot (added 0007) |
| `sales_type` | TEXT | Retail / Wholesale / Credit (0007) |
| `through` (salesman), `area`, `remarks` | TEXT | (0007) |
| `draft_bill_id` | TEXT | links to `bill_drafts.id` (0007) |
| `total_items`, `total_quantity`, `grand_total` | INT / NUMERIC | |
| `created_at` | TIMESTAMPTZ | |

### 3.2 `erp_billing_system_items` (user bill lines)
| Column | Type | Notes |
|---|---|---|
| `bill_item_id` | UUID PK | |
| `bill_id` | UUID FK → `erp_billing_system.bill_id` | `ON DELETE CASCADE` |
| `sno` | INTEGER | line order |
| `description` | VARCHAR(255) | product name snapshot |
| `quantity`, `rate`, `amount` | NUMERIC | |
| `product_id` | UUID FK → `products.product_id` | `ON DELETE SET NULL` (0007/0008) |
| `discount_percent` | NUMERIC(5,2) | (0007) |

### 3.3 `erp_billing_system_company` (company invoice header)
| Column | Type | Notes |
|---|---|---|
| `invoice_id` | UUID PK | |
| `invoice_no` | VARCHAR(50) UNIQUE | |
| `invoice_date`, `invoice_time` | DATE, TIME | |
| `customer_name`, `customer_phone` | VARCHAR | |
| `payment_mode`, `transaction_id`, `upi_id` | VARCHAR | |
| `total_amount`, `amount_in_words` | NUMERIC / TEXT | |
| `sales_type`, `through`, `area`, `remarks`, `draft_bill_id` | TEXT | (0007) |
| `created_at` | TIMESTAMPTZ | |

### 3.4 `erp_billing_system_company_items` (company invoice lines)
| Column | Type | Notes |
|---|---|---|
| `item_id` | UUID PK | |
| `invoice_id` | UUID FK → `erp_billing_system_company.invoice_id` | `ON DELETE CASCADE` |
| `sno`, `description`, `unit`, `quantity`, `rate`, `amount` | | |
| `product_id` | UUID FK → `products.product_id` | `ON DELETE SET NULL` (0007/0008) |
| `discount_percent` | NUMERIC(5,2) | (0007) |

### 3.5 `products` (shared catalogue — read for billing)
Columns used by code: `product_id` (UUID), `product_name`, `selling_price`, `sku`, `product_image`, `gst_percentage` (filter `= 0` for NON-GST), plus FKs `category_id → categories`, `unit_id → units`, `brand_id → brands`. Read via `products(..., categories(name), units(unit_name), brands(brand_name))`.

### 3.6 `inventory` (shared stock)
| Column | Type | Notes |
|---|---|---|
| `product_id` | UUID PK / FK → products | |
| `current_stock` | NUMERIC(10,2) | available stock |
| `reserved_stock` | NUMERIC(10,2) DEFAULT 0 | added `0005` |
| `version` | BIGINT DEFAULT 0 | optimistic lock (0005) |
| `updated_at` | TIMESTAMPTZ | (0005) |

### 3.7 `customers` (shared)
Columns used: `customer_id` (UUID), `name`, `phone`, `email`, `address`.

### 3.8 `bill_drafts` (shared session tracker)
| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | e.g. `DRAFT-1749481234567` |
| `source_app` | TEXT | `NON_GST_ERP` / `GST_ERP` |
| `status` | TEXT | `ACTIVE` → `COMPLETED` / `CANCELLED` |
| `created_by`, `completed_at`, `cancelled_at`, `updated_at` | | |

### 3.9 `stock_reservations` (reservations + holds)
| Column | Type | Notes |
|---|---|---|
| `id` | UUID PK | |
| `product_id` | UUID | no FK (shared contract) |
| `bill_id` | TEXT | draft id or real bill no |
| `user_id` | TEXT | |
| `source_app` | TEXT CHECK | `NON_GST_ERP` / `GST_ERP` |
| `quantity` | NUMERIC(10,2) CHECK > 0 | |
| `status` | TEXT CHECK | `ACTIVE`, `COMPLETED`, `RELEASED`, `EXPIRED`, `HELD` (HELD added 0011) |
| `reserved_at`, `expires_at` (nullable, 0012) | TIMESTAMPTZ | ACTIVE = 2h default; HELD = NULL |
| `released_at`, `completed_at`, `created_at`, `updated_at` | TIMESTAMPTZ | |

### 3.10 `salesperson_bills` (admin inbox)
| Column | Type | Notes |
|---|---|---|
| `id` | UUID PK | |
| `salesman_id` | INTEGER | |
| `submitted_by` | TEXT | |
| `customer_id`, `customer_name`, `customer_phone` | | |
| `payment_type`, `sales_type`, `price_list` | VARCHAR | with CHECKs |
| `items` | JSONB | exact line items for `create_bill()` |
| `grand_total` | NUMERIC(12,2) | |
| `status` | TEXT CHECK | `PENDING` / `PROCESSED` / `ERROR` |
| `created_at`, `updated_at`, `processed_at` | TIMESTAMPTZ | |
- RLS: `anon` → INSERT only; `service_role` → full access

### 3.11 `bill_sequence` (atomic numbering)
| Column | Type | Notes |
|---|---|---|
| `prefix` | TEXT PK | e.g. hourly prefix |
| `last_seq` | INTEGER DEFAULT 0 | incremented under row lock |

### 3.12 `users` (login)
Columns used: `user_id`, `role_id` (1=Admin, 3=Billing Employee, 4=Stock In-Charge), `warehouse_id`, `mobile_number` (login credential), `full_name`, `is_active`.

---

## 4. RPC Functions (called via `.rpc()`)

| Function | Migration | Purpose |
|---|---|---|
| `reserve_stock(...)` | 0005 | Reserve + deduct stock atomically (ACTIVE 2h) |
| `release_reservation(...)` | 0005 | Release reservation, restore stock |
| `complete_reservation(...)` | 0005 | Finalize reservation (bill saved) |
| `expire_stale_reservations()` | 0005 | Expire ACTIVE past `expires_at` |
| `release_bill_reservations(...)` | 0005 | Release all reservations for a bill |
| `complete_bill_reservations(...)` | 0005 | Complete all reservations for a bill |
| `update_reservation(...)` | 0006 | Adjust ACTIVE reservation quantity atomically |
| `next_bill_number(p_prefix)` | 0010 | Atomic bill numbering from `bill_sequence` |
| `hold_stock(...)` | 0011 | Hold stock WITHOUT deducting `current_stock` |
| `release_hold(...)` | 0011 | Stock-out: deduct `current_stock` + `reserved_stock` |
| `cancel_hold(...)` | 0011 | Cancel hold, reserved_stock only |
| `update_hold(...)` | 0011 | Change HELD quantity |
| `cancel_bill_holds(...)` | 0011 | Cancel all holds for a bill |
| `expire_stale_holds(hours, source_app)` | 0011 | Expire abandoned `DRAFT-*` holds |
| `link_holds_to_bill(...)` | 0011 | Attach draft holds to real bill number |

---

## 5. RLS / Security Status

| Table | RLS | Policy |
|---|---|---|
| `erp_billing_system` (+items) | Enabled | service_role full access (0004) |
| `erp_billing_system_company` (+items) | Enabled | service_role full access (0004) |
| `salesperson_bills` | Enabled | anon INSERT only; service_role ALL (0009) |
| `stock_reservations` | Disabled | service-role backend access (0005) |
| `products`, `inventory`, `customers`, `users`, `bill_drafts`, reference tables | shared/GST schema | controlled by shared project |

---

## 6. Flow Summary (how the tables are linked at runtime)

1. **Login** → `users` (mobile_number lookup)
2. **Start billing session** → `bill_drafts` (ACTIVE) — id becomes `bill_id`
3. **Add items** → `reserve_stock` / `hold_stock` → `stock_reservations` (ACTIVE/HELD) + `inventory` counters
4. **Save bill** → `next_bill_number()` (`bill_sequence`) → `erp_billing_system` + `erp_billing_system_items` AND `erp_billing_system_company` + `erp_billing_system_company_items` → `complete_bill_reservations` / `link_holds_to_bill`, draft → COMPLETED
5. **Cancel bill** → `release_bill_reservations` / `cancel_bill_holds`, draft → CANCELLED
6. **Stock out** (HELD flow) → `release_hold` deducts real stock
7. **Salesman submission** → `salesperson_bills` (PENDING) → admin processes → PROCESSED/delete
8. **PDFs** → stored in buckets `erp_billing_system` / `erp_billing_system_company`

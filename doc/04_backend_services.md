# 4. Backend — Services

Services hold the business logic layer between the routes and the database.

## 4.1 `BillingService` — `services/billing_service.py`

The core service used by most routes. It is instantiated once at module load and
exported as the module-level singleton `billing_service`.

### Startup behaviour

`BillingService.__init__` does three things:
1. Loads **products** from Supabase (`products` + `inventory` + `categories`, `units`,
   `brands` relations) into `self._products`.
2. Loads **customers** from Supabase into `self._customers` (always prefixed with the
   **Walk-in Customer** pseudo-customer).
3. Seeds an hourly in-memory invoice counter from the highest bill number already in DB.

If the DB is unreachable, it falls back to `SAMPLE_PRODUCTS` / `SAMPLE_CUSTOMERS`
from `sample_data.py` (with the Walk-in customer added).

### Invoice numbering

Format: `YYYY + MMM(upper) + DD + A + HH + sequence`, e.g. `2026AUG08A161`.

- `_seed_hour_counter()` — scans `erp_billing_system` for the current hour prefix and
  sets `_hour_seq` to the max sequence found.
- `_next_bill_number()` — on hour rollover re-seeds from the DB, then increments the
  in-memory counter and returns `prefix + seq`.
- After a delete, the counter is re-seeded so the next number continues from the real max.

### Public methods

| Method | Purpose |
|--------|---------|
| `get_all_products()` | All products as dicts |
| `get_product_by_id(id)` | One product or `None` |
| `get_products_by_category(cat)` | Filter by category |
| `search_products(q)` | Case-insensitive name/category search |
| `get_all_customers()` | All customers as dicts |
| `get_customer_by_id(id)` | One customer or `None` |
| `search_customers(q)` | Search by name / phone / area |
| `create_customer(name, phone, email, address)` | Insert into Supabase `customers`; returns `{success, data}` |
| `create_bill(payload)` | **Main flow** — save a bill (see below) |
| `get_all_bills()` | All bills newest-first with items |
| `get_bill_by_number(bill_number)` | Single bill or `None` |
| `delete_bill(bill_number)` | Remove bill + company invoice + storage PDFs |
| `get_dashboard_summary()` | Totals for the dashboard |

### `create_bill(payload)` flow

1. Validate payload via `_validate_bill_payload` (customer name + ≥1 item with positive
   qty/rate). On failure returns `{success: false, message}`.
2. Generate the next bill number.
3. Compute `grand_total` = Σ `rate × qty × (1 − discount%)`.
4. Build the user-bill header + line rows and insert into
   `erp_billing_system` + `erp_billing_system_items`.
5. Build the company-invoice header + line rows and insert into
   `erp_billing_system_company` + `erp_billing_system_company_items`
   (wrapped in its own try/except — a company-insert failure is only a warning).
6. Deduct stock **in memory** (`_deduct_stock`).
7. Build a `Bill` object and return `{success: true, bill_number, bill}`.

Header row (user bill): `business_name="VELA AGENCY"`, `bill_no`, `bill_date`,
`bill_time`, `payment_mode`, `total_items`, `total_quantity`, `grand_total`.

Company header adds: `customer_name`, `customer_phone`, `payment_mode`,
`transaction_id = bill_number`, `upi_id`, `total_amount`, `amount_in_words`
(via `_amount_in_words`).

### `_amount_in_words(amount)`

Converts a rupee amount to Indian English words, e.g.
`1379.71 → "One Thousand Three Hundred Seventy Nine Rupees and Seventy One Paise Only"`.
Used for the printed company invoice.

### Bill read/deletion

- `get_all_bills` / `get_bill_by_number` select `erp_billing_system` with its items
  (`erp_billing_system_items(*)`) and map rows back into the exact shape the Flutter
  `Bill` model expects via `_row_to_bill_dict`. It enriches items with the `unit` from
  the company-items table and the `customer_name` from the company header.
- `delete_bill` deletes from both tables (items cascade via `ON DELETE CASCADE`), removes
  the PDF from both Storage buckets, and re-seeds the hour counter.

### Stock handling

`_deduct_stock` / `_restore_stock` mutate the in-memory `Product.stock` (clamped ≥ 0).
Stock is **not** persisted — it resets on server restart (a known limitation, see
[15 — Known Issues](15_known_issues_roadmap.md)). The canonical Supabase schema solves
this with the `create_bill()` DB function.

## 4.2 `language_utils.py` — `services/language_utils.py`

Local multilingual language detection + transliteration engine (no external API).

### `Language` enum
- `english` = `"en"`, `tamil` = `"ta"`, `tanglish` = `"ta-en"`.

### Key functions

| Function | Purpose |
|----------|---------|
| `detect_language(text)` | Detect `english` / `tamil` / `tanglish` |
| `transliterate_tanglish_to_tamil(text)` | Phonetic English → Tamil script |
| `normalize_query(text)` | Normalise a search query (transliterate Tanglish → Tamil) |

### Detection heuristics
- **Tamil Unicode** (`U+0B80–U+0BFF`) present + no ASCII → `tamil`.
- Mixed Tamil + ASCII → `tanglish`.
- ASCII only: a `TANGLISH_KEYWORDS` keyword match (e.g. `arisi`, `vengayam`, `kadalai`)
  or a syllable-coverage score ≥ 0.40 → `tanglish`, else `english`.

### `TANGLISH_MAP`
A ~120-entry mapping of English syllables to Tamil letters (e.g. `"ka"→"க"`,
`"aa"→"ஆ"`, `"kadalai"→…`). Transliteration sorts by longest key first so compound
syllables win over single letters.

## 4.3 `sample_data.py` — `services/sample_data.py`

Bundled fallback data used when Supabase is unreachable.

| Export | Contents |
|--------|----------|
| `SAMPLE_PRODUCTS` | Full 545-item offline fallback catalogue. Used whenever Supabase is unreachable so the POS stays usable (live products are DB-driven). |
| `SAMPLE_CUSTOMERS` | Single Walk-in Customer fallback. |

> Note: `tests/test_billing.py` still expects 545 products — those tests assume the
> DB is available or use older behaviour. See [13 — Testing](13_testing_qa.md).

## Related docs

- [03 — Backend API Routes](03_backend_routes.md)
- [05 — Backend Models](05_backend_models.md)
- [06 — Supabase Database](06_supabase_database.md)

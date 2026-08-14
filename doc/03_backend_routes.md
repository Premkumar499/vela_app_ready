# 3. Backend — API Routes

All endpoints are implemented as Flask blueprints registered in `app.py`.
Response envelopes follow the pattern `{"success": bool, "data": …} ` or
`{"success": bool, "message": …}`.

## 3.1 Products — `routes/products.py` (`/products`)

Backed by `BillingService`.

| Method | Path | Query params | Description |
|--------|------|--------------|-------------|
| GET | `/products/` | `category` · `search` | List all products (filter by category or name/category search) |
| GET | `/products/<product_id>` | — | Single product by UUID |

Responses: `200` with `{success, data, count}` / `404` when not found.

> Products are loaded once from Supabase at startup and cached in memory
> (`BillingService._products`). There is currently **no create/update/delete**
> endpoint for products.

## 3.2 Customers — `routes/customers.py` (`/customers`)

| Method | Path | Query params | Description |
|--------|------|--------------|-------------|
| GET | `/customers/` | `search` | List customers (search by name / phone / area) |
| GET | `/customers/<customer_id>` | — | Single customer |
| POST | `/customers/` | — | Create a customer (inserts into Supabase) |

**POST body** (`create_customer`):
```json
{ "name": "string (required)", "phone": "", "email": "", "address": "" }
```
- `400` if name missing.
- `201` with the created customer on success; `500` on DB failure.

## 3.3 Billing — `routes/billing.py` (`/bill`)

| Method | Path | Description |
|--------|------|-------------|
| POST | `/bill/` | Create a new bill |

**POST body:**
```json
{
  "customer_id": 1,
  "customer_name": "Walk-in Customer",
  "payment_type": "Cash",
  "sales_type": "Retail",
  "remarks": "",
  "through": "",
  "area": "",
  "price_list": "Retail",
  "items": [
    { "product_id": 1, "product_name": "BACKING SODA", "unit": "KG",
      "quantity": 2, "rate": 225.00, "discount_percent": 0 }
  ]
}
```

- `400` — invalid/missing JSON body.
- `422` — validation failed (message includes reasons).
- `201` — success, returns `{success, message, bill_number, bill}`.

`BillingService.create_bill()` performs the actual work (see [04](04_backend_services.md)).

## 3.4 History — `routes/history.py` (`/bills`)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/bills/` | All bills, newest first (`{success, data, count}`) |
| GET | `/bills/<bill_number>` | Single bill (`404` when missing) |
| DELETE | `/bills/<bill_number>` | Delete bill + company invoice + storage PDFs |
| GET | `/bills/summary` | Dashboard totals `{total_bills, total_sales, total_products, total_customers}` |

## 3.5 Translation — `routes/translate.py` (`/translate/`)

Local, API-key-free translation endpoint that converts English/Tanglish text to
Tamil script using the built-in transliteration engine (`services/language_utils.py`).

| Method | Path | Description |
|--------|------|-------------|
| POST | `/translate/` | Translate a list of strings |

**Body:** `{ "texts": ["Rice", "Arisi"], "target": "ta" }`
**Response:** `{ "success": true, "translations": ["ரைஸ்", "அரிசி"] }`

Used by `BilingualBillDashboard` to show Tamil item descriptions on the receipt.

## 3.6 Bilingual Billing — `routes/bilingual_billing.py` (`/api/bilingual`)

A **simplified, in-memory** bill API (no database). State resets on server restart.

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/bilingual/bills` | Create a simple bill (`94001`, `94002`, …) |
| GET | `/api/bilingual/bills` | List all simple bills (newest first) |
| GET | `/api/bilingual/bills/<bill_no>` | Get one bill (`404` when missing) |
| DELETE | `/api/bilingual/bills/<bill_no>` | Delete one bill |
| GET | `/api/bilingual/generate-bill-number` | Next bill number + date/time without creating a bill |

Bill shape: `{billNo, date (dd/MM/yyyy), time (hh:mm AM/PM), paymentMode, customerName, items}`.

> This is a secondary/legacy surface. The main app uses `/bill/` + `/bills/`.

## 3.7 Invoice Export — `routes/invoice_export.py` (`/invoice-export`)

Converts invoice images to PDF and/or generates company invoices server-side, then
uploads to Supabase Storage.

**Buckets:**
- `erp_billing_system` — customer cash bill (simple receipt)
- `erp_billing_system_company` — company GST invoice

| Method | Path | Description |
|--------|------|-------------|
| POST | `/invoice-export/save` | Base64 image → PDF → upload (customer bills) |
| POST | `/invoice-export/generate-company/<invoice_number>` | Server-side company invoice PDF from DB (or fallback payload) → upload |
| GET | `/invoice-export/list/<bucket>` | List PDFs in a bucket |
| GET | `/invoice-export/download/<bucket>/<invoice_number>` | Signed URL (60 min) for a PDF |

### `POST /invoice-export/save`
Body: `{ "invoice_number": "2026AUG08A161", "image_data": "<base64 PNG/JPEG>", "is_company_invoice": false }`
- Converts the image to a single A4 PDF (centred, scaled) via Pillow + ReportLab.
- Uploads to the bucket selected by `is_company_invoice`.
- Also writes a local PNG copy under `backend/invoices/…` for debugging.
- `201` returns `{success, message, file_name, bucket, url, pdf_size}`.

### `POST /invoice-export/generate-company/<invoice_number>`
- Primary path: reads header + items from `erp_billing_system_company` and builds a
  pixel-perfect VELA AGENCY PDF (logo, BILL TO, items table, payment details, bank
  details, signature, footer).
- Fallback path: if no DB row, builds from a JSON body payload.
- Uploads `invoice_number.pdf` to `erp_billing_system_company`.
- `201` returns `{success, message, file_name, bucket, url, pdf_size}`.

### `GET /invoice-export/list/<bucket>` & `/download/<bucket>/<invoice_number>`
- `list` returns metadata + public URLs for all `.pdf` files in the bucket.
- `download` returns a signed URL valid for 3600 seconds.

### Internal helpers
- `_image_bytes_to_pdf(image_bytes)` — Pillow → single-page A4 PDF.
- `_generate_company_invoice_pdf(invoice_no)` — DB-driven PDF (primary).
- `_generate_company_invoice_pdf_from_payload(invoice_no, payload)` — fallback PDF.
- `_get_supabase()` — reads `.env` and returns an authenticated client.

## 3.8 Stock Holds — `routes/reservations.py` (`/reservations`)

Stock-hold system (migration `0011_stock_holds.sql`). Bills **hold** stock
(`reserved_stock` up, `current_stock` untouched); only the stock-out person's
`release-hold` ever decreases `current_stock`. `source_app='NON_GST_ERP'` rows
only — never touches the friend's GST_ERP app.

| Method | Path | Description |
|--------|------|-------------|
| POST | `/reservations/hold` | Hold stock for one bill line (`reserved_stock` only) |
| POST | `/reservations/release-hold` | Stock-out: `current_stock` AND `reserved_stock` down, status `RELEASED` — the ONLY place `current_stock` decreases |
| POST | `/reservations/cancel-hold` | Cancel a single hold (`reserved_stock` freed, no stock change) |
| POST | `/reservations/update-hold` | Change a HELD reservation's quantity atomically |
| POST | `/reservations/cancel-bill-holds` | Cancel all holds for a bill (bill deleted/cancelled) |
| POST | `/reservations/expire-stale-holds` | Expire abandoned `DRAFT-*` holds older than `hours` (default 2). Real-bill holds never expire |
| GET | `/reservations/held` | Reserve table: HELD holds grouped by bill + product/inventory/company joins — **only used by the Stock In-Charge (role_id 4), lands on `/stock-out` after login** |
| GET | `/reservations/stock/<product_id>` | Live `current_stock` / `reserved_stock` for a product |

`/reservations/hold` body: `{product_id, bill_id, quantity, user_id?}` —
`400` on missing/zero fields, `409` on insufficient stock.
`/reservations/held` returns `{success, count, data: [{bill_number, customer_name,
customer_phone, payment_mode, sales_type, through, area, total_amount, invoice_date,
invoice_time, created_at, total_quantity, items: [{reservation_id, product_id, name,
unit, quantity, reserved_at, current_stock, reserved_stock, available_stock}]}]}`.
Draft bills (`DRAFT-*`) get empty customer fields.

Legacy reserve/release/update/complete endpoints remain for GST_ERP compatibility;
the NON_GST app uses the hold endpoints above.

## Endpoint summary (quick reference)

```
GET    /health
GET    /products/              [?category=&search=]
GET    /products/<id>
GET    /customers/             [?search=]
GET    /customers/<id>
POST   /customers/
POST   /bill/
GET    /bills/
GET    /bills/<bill_number>
DELETE /bills/<bill_number>
GET    /bills/summary
POST   /translate/
POST   /api/bilingual/bills
GET    /api/bilingual/bills
GET    /api/bilingual/bills/<bill_no>
DELETE /api/bilingual/bills/<bill_no>
GET    /api/bilingual/generate-bill-number
POST   /invoice-export/save
POST   /invoice-export/generate-company/<invoice_number>
GET    /invoice-export/list/<bucket>
GET    /invoice-export/download/<bucket>/<invoice_number>
POST   /reservations/hold
POST   /reservations/release-hold
POST   /reservations/cancel-hold
POST   /reservations/update-hold
POST   /reservations/cancel-bill-holds
POST   /reservations/expire-stale-holds
GET    /reservations/held
GET    /reservations/stock/<product_id>
```

## Related docs

- [02 — Backend App & Config](02_backend_app.md)
- [04 — Backend Services](04_backend_services.md)
- [09 — Frontend Services](09_frontend_services.md)

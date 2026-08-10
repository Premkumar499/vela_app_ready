-- ================================================================
-- Migration 0009: Salesperson pending-bills inbox
--
-- Flow:
--   1. Salesperson (or any submitter) INSERTs a bill request here.
--   2. Admin reads PENDING rows, validates, and pushes the bill
--      through the existing create_bill flow, which generates BOTH
--      the user bill PDF and the company bill PDF.
--   3. After the PDFs are sent, the row is DELETEd from this table
--      (or marked PROCESSED then pruned).
--
-- The items column stores the exact line items the backend expects
-- (product_id, product_name, unit, quantity, rate) so the row can be
-- handed straight to BillingService.create_bill().
--
-- Run once in Supabase SQL Editor. Safe to re-run.
-- ================================================================

CREATE TABLE IF NOT EXISTS salesperson_bills (
    id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    salesman_id     INTEGER       NOT NULL DEFAULT 0,
    submitted_by    TEXT          NOT NULL DEFAULT '',
    customer_id     BIGINT        DEFAULT 0,
    customer_name   VARCHAR(150)  NOT NULL DEFAULT 'Walk-in Customer',
    customer_phone  VARCHAR(20)   NOT NULL DEFAULT '',
    payment_type    VARCHAR(30)   NOT NULL DEFAULT 'Cash'
                                  CHECK (payment_type IN ('Cash', 'Credit', 'UPI')),
    sales_type      VARCHAR(30)   NOT NULL DEFAULT 'Retail'
                                  CHECK (sales_type IN ('Retail', 'Wholesale', 'Credit')),
    price_list      VARCHAR(30)   NOT NULL DEFAULT 'Retail',
    items           JSONB         NOT NULL,
    grand_total     NUMERIC(12,2) NOT NULL DEFAULT 0,
    status          TEXT          NOT NULL DEFAULT 'PENDING'
                                  CHECK (status IN ('PENDING', 'PROCESSED', 'ERROR')),
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    processed_at    TIMESTAMPTZ
);

-- Migrate an already-created old-shape table to the new shape
ALTER TABLE salesperson_bills
    DROP COLUMN IF EXISTS through,
    DROP COLUMN IF EXISTS area,
    DROP COLUMN IF EXISTS total_quantity,
    DROP COLUMN IF EXISTS remarks,
    ADD COLUMN IF NOT EXISTS salesman_id INTEGER NOT NULL DEFAULT 0;

-- Indexes for the admin inbox
CREATE INDEX IF NOT EXISTS idx_salesperson_bills_status      ON salesperson_bills(status);
CREATE INDEX IF NOT EXISTS idx_salesperson_bills_created_at  ON salesperson_bills(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_salesperson_bills_salesman    ON salesperson_bills(salesman_id);

-- ----------------------------------------------------------------
-- Table-level grants (needed alongside the RLS policies)
-- ----------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON salesperson_bills TO service_role;
GRANT INSERT ON salesperson_bills TO anon;

-- ----------------------------------------------------------------
-- Row Level Security
--   anon        (salesman app)  → INSERT only — can submit, cannot read/see others
--   service_role (backend)      → full access — reads PENDING, deletes after PDF sent
-- ----------------------------------------------------------------
ALTER TABLE salesperson_bills ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "salesman submit bill" ON salesperson_bills;
CREATE POLICY "salesman submit bill"
ON salesperson_bills
FOR INSERT
TO anon
WITH CHECK (true);

DROP POLICY IF EXISTS "service role full access salesperson_bills" ON salesperson_bills;
CREATE POLICY "service role full access salesperson_bills"
ON salesperson_bills
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- Make sure PostgREST sees the new table immediately
NOTIFY pgrst, 'reload schema';
-- ================================================================
-- Migration 0008: Add salesman / session columns to ERP billing tables
--
-- Root-cause fix for PGRST204:
--   "Could not find the 'area' column of 'erp_billing_system'"
--
-- The backend (billing_service.create_bill) inserts the salesman-input
-- fields (customer_name, customer_phone, sales_type, through, area,
-- remarks, draft_bill_id) and per-line product_id, but these columns were
-- never added to the live database.  This migration brings the live schema
-- in line with the code.  Safe to re-run (all use IF NOT EXISTS).
-- ================================================================

-- ----------------------------------------------------------------
-- 1. erp_billing_system  (user / customer bill header)
-- ----------------------------------------------------------------
ALTER TABLE erp_billing_system
    ADD COLUMN IF NOT EXISTS customer_name    VARCHAR(150) DEFAULT '',
    ADD COLUMN IF NOT EXISTS customer_phone   VARCHAR(20)  DEFAULT '',
    ADD COLUMN IF NOT EXISTS sales_type       VARCHAR(30)  DEFAULT 'Retail',
    ADD COLUMN IF NOT EXISTS through          VARCHAR(100) DEFAULT '',
    ADD COLUMN IF NOT EXISTS area             VARCHAR(100) DEFAULT '',
    ADD COLUMN IF NOT EXISTS remarks          TEXT         DEFAULT '',
    ADD COLUMN IF NOT EXISTS draft_bill_id    TEXT         DEFAULT '';

-- ----------------------------------------------------------------
-- 2. erp_billing_system_items  (user bill line items)
-- ----------------------------------------------------------------
ALTER TABLE erp_billing_system_items
    ADD COLUMN IF NOT EXISTS product_id UUID REFERENCES products(product_id) ON DELETE SET NULL;

-- ----------------------------------------------------------------
-- 3. erp_billing_system_company  (company invoice header)
--    customer_name / customer_phone already exist on this table.
-- ----------------------------------------------------------------
ALTER TABLE erp_billing_system_company
    ADD COLUMN IF NOT EXISTS sales_type     VARCHAR(30)  DEFAULT 'Retail',
    ADD COLUMN IF NOT EXISTS through        VARCHAR(100) DEFAULT '',
    ADD COLUMN IF NOT EXISTS area           VARCHAR(100) DEFAULT '',
    ADD COLUMN IF NOT EXISTS remarks        TEXT         DEFAULT '',
    ADD COLUMN IF NOT EXISTS draft_bill_id  TEXT         DEFAULT '';

-- ----------------------------------------------------------------
-- 4. erp_billing_system_company_items  (company invoice line items)
-- ----------------------------------------------------------------
ALTER TABLE erp_billing_system_company_items
    ADD COLUMN IF NOT EXISTS product_id UUID REFERENCES products(product_id) ON DELETE SET NULL;

-- ----------------------------------------------------------------
-- Refresh the PostgREST schema cache so inserts succeed immediately.
-- ----------------------------------------------------------------
NOTIFY pgrst, 'reload schema';

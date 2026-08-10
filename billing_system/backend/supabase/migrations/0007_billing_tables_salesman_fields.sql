-- ================================================================
-- Migration 0007: Add missing salesman-input fields to billing tables
--
-- Adds all fields that the salesman actually inputs during billing
-- but were not being stored in the database.
--
-- Run once in Supabase SQL Editor.
-- Safe to re-run (uses ADD COLUMN IF NOT EXISTS).
-- ================================================================


-- ----------------------------------------------------------------
-- 1. erp_billing_system  (user/customer bill header)
--    Missing: customer_name, customer_phone, sales_type,
--             through (salesman), area, remarks
-- ----------------------------------------------------------------
ALTER TABLE erp_billing_system
    ADD COLUMN IF NOT EXISTS customer_name    TEXT,
    ADD COLUMN IF NOT EXISTS customer_phone   TEXT,
    ADD COLUMN IF NOT EXISTS sales_type       TEXT    DEFAULT 'Retail',
    ADD COLUMN IF NOT EXISTS through          TEXT,
    ADD COLUMN IF NOT EXISTS area             TEXT,
    ADD COLUMN IF NOT EXISTS remarks          TEXT,
    ADD COLUMN IF NOT EXISTS draft_bill_id    TEXT;

-- ----------------------------------------------------------------
-- 2. erp_billing_system_items  (user bill line items)
--    Missing: product_id (for traceability), discount_percent
-- ----------------------------------------------------------------
ALTER TABLE erp_billing_system_items
    ADD COLUMN IF NOT EXISTS product_id       UUID,
    ADD COLUMN IF NOT EXISTS discount_percent NUMERIC(5,2) DEFAULT 0;

-- ----------------------------------------------------------------
-- 3. erp_billing_system_company  (company invoice header)
--    Missing: sales_type, through, area, remarks, draft_bill_id
-- ----------------------------------------------------------------
ALTER TABLE erp_billing_system_company
    ADD COLUMN IF NOT EXISTS sales_type       TEXT    DEFAULT 'Retail',
    ADD COLUMN IF NOT EXISTS through          TEXT,
    ADD COLUMN IF NOT EXISTS area             TEXT,
    ADD COLUMN IF NOT EXISTS remarks          TEXT,
    ADD COLUMN IF NOT EXISTS draft_bill_id    TEXT;

-- ----------------------------------------------------------------
-- 4. erp_billing_system_company_items  (company invoice line items)
--    Missing: product_id, discount_percent
-- ----------------------------------------------------------------
ALTER TABLE erp_billing_system_company_items
    ADD COLUMN IF NOT EXISTS product_id       UUID,
    ADD COLUMN IF NOT EXISTS discount_percent NUMERIC(5,2) DEFAULT 0;


-- ================================================================
-- Reference: What each field means
-- ================================================================
--
-- HEADER FIELDS:
--   customer_name    → "Walk-in Customer" or selected customer name
--   customer_phone   → optional, entered by salesman
--   sales_type       → "Retail" | "Wholesale" | "Credit"
--   through          → salesman / agent name
--   area             → delivery area / customer area
--   remarks          → free text note
--   draft_bill_id    → links to bill_drafts.id (reservation session)
--
-- LINE ITEM FIELDS:
--   product_id       → UUID from products table (for traceability)
--   discount_percent → per-item discount entered by salesman
--
-- ================================================================

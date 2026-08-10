-- =============================================================
-- Migration 0007: Add missing columns to billing tables
-- Run once in Supabase SQL Editor
-- =============================================================

-- ---------------------------------------------------------------
-- 1. erp_billing_system – add salesman / session fields
-- ---------------------------------------------------------------
ALTER TABLE erp_billing_system
  ADD COLUMN IF NOT EXISTS customer_name  VARCHAR(150) DEFAULT '',
  ADD COLUMN IF NOT EXISTS customer_phone VARCHAR(20)  DEFAULT '',
  ADD COLUMN IF NOT EXISTS sales_type     VARCHAR(30)  DEFAULT 'Retail',
  ADD COLUMN IF NOT EXISTS through        VARCHAR(100) DEFAULT '',
  ADD COLUMN IF NOT EXISTS area           VARCHAR(100) DEFAULT '',
  ADD COLUMN IF NOT EXISTS remarks        TEXT         DEFAULT '',
  ADD COLUMN IF NOT EXISTS draft_bill_id  TEXT         DEFAULT '';

-- ---------------------------------------------------------------
-- 2. erp_billing_system_items – add product link
-- ---------------------------------------------------------------
ALTER TABLE erp_billing_system_items
  ADD COLUMN IF NOT EXISTS product_id UUID REFERENCES products(product_id) ON DELETE SET NULL;

-- ---------------------------------------------------------------
-- 3. erp_billing_system_company_items – add product link
-- ---------------------------------------------------------------
ALTER TABLE erp_billing_system_company_items
  ADD COLUMN IF NOT EXISTS product_id UUID REFERENCES products(product_id) ON DELETE SET NULL;

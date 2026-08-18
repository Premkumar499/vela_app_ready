-- ================================================================
-- Migration 0014: Completed bills payment and balance tracking
--
-- Run once in Supabase SQL Editor. Safe to re-run.
-- ================================================================

-- 1. Alter erp_billing_system to add payment tracking fields
ALTER TABLE erp_billing_system 
  ADD COLUMN IF NOT EXISTS amount_paid NUMERIC(12,2) NOT NULL DEFAULT 0.00,
  ADD COLUMN IF NOT EXISTS balance NUMERIC(12,2) GENERATED ALWAYS AS (grand_total - amount_paid) STORED;

-- 2. Alter erp_billing_system_company to add payment tracking fields
ALTER TABLE erp_billing_system_company 
  ADD COLUMN IF NOT EXISTS amount_paid NUMERIC(12,2) NOT NULL DEFAULT 0.00,
  ADD COLUMN IF NOT EXISTS balance NUMERIC(12,2) GENERATED ALWAYS AS (total_amount - amount_paid) STORED;

-- Make sure PostgREST sees the new schema immediately
NOTIFY pgrst, 'reload schema';

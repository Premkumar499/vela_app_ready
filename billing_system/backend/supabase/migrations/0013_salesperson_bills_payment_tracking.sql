-- ================================================================
-- Migration 0013: Salesperson bills payment and balance tracking
--
-- Run once in Supabase SQL Editor. Safe to re-run.
-- ================================================================

-- 1. Alter salesperson_bills to add payment tracking fields
ALTER TABLE salesperson_bills 
  ADD COLUMN IF NOT EXISTS amount_paid NUMERIC(12,2) NOT NULL DEFAULT 0.00,
  ADD COLUMN IF NOT EXISTS balance NUMERIC(12,2) GENERATED ALWAYS AS (grand_total - amount_paid) STORED;

-- Make sure PostgREST sees the new schema immediately
NOTIFY pgrst, 'reload schema';

-- =============================================================
-- Migration 0012: Allow NULL expires_at on stock_reservations
-- HELD rows are inserted with expires_at = NULL (real-bill holds
-- must persist until release/cancel). Migration 0005 declared the
-- column NOT NULL, which made hold_stock fail with a not-null
-- violation. ACTIVE reservations keep their 2-hour default.
-- Run once in Supabase SQL Editor. Safe to re-run.
-- =============================================================
ALTER TABLE stock_reservations ALTER COLUMN expires_at DROP NOT NULL;

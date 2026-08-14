-- ================================================================
-- Migration 0010: DB-backed atomic bill numbering
--
-- Adds the next_bill_number(p_prefix) RPC that BillingService calls
-- in _next_bill_number(). Without it the backend falls back to an
-- in-process counter, which produces duplicate bill_no values when
-- more than one worker/process mints bills (auto-polling + API).
--
-- Atomicity: the upsert row-lock on bill_sequence(prefix) serializes
-- concurrent callers, so two callers never receive the same sequence.
-- A fresh hour prefix seeds from the max existing bill_no in
-- erp_billing_system for that prefix.
--
-- Run once in Supabase SQL Editor. Safe to re-run.
-- ================================================================

CREATE TABLE IF NOT EXISTS bill_sequence (
    prefix   TEXT        PRIMARY KEY,
    last_seq INTEGER     NOT NULL DEFAULT 0
);

CREATE OR REPLACE FUNCTION public.next_bill_number(p_prefix TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    next_seq INTEGER;
BEGIN
    INSERT INTO bill_sequence (prefix, last_seq)
    VALUES (
        p_prefix,
        (
            SELECT COALESCE(
                MAX(CAST(SUBSTRING(bill_no FROM LENGTH(p_prefix) + 1) AS INTEGER)),
                0
            ) + 1
            FROM erp_billing_system
            WHERE bill_no LIKE p_prefix || '%'
              AND SUBSTRING(bill_no FROM LENGTH(p_prefix) + 1) ~ '^[0-9]+$'
        )
    )
    ON CONFLICT (prefix)
    DO UPDATE SET last_seq = bill_sequence.last_seq + 1
    RETURNING last_seq INTO next_seq;

    RETURN next_seq;
END;
$$;

GRANT EXECUTE ON FUNCTION public.next_bill_number(TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.next_bill_number(TEXT) TO anon;

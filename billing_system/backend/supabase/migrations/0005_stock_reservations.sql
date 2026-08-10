-- =============================================================
-- Migration 0005: Stock Reservation + Concurrency System
-- Shared contract between NON_GST_ERP and GST_ERP applications
-- Run once in Supabase SQL Editor
-- =============================================================

-- ---------------------------------------------------------------
-- 1. Add reservation columns to inventory table (if not exist)
-- ---------------------------------------------------------------
ALTER TABLE inventory
  ADD COLUMN IF NOT EXISTS reserved_stock  NUMERIC(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS version         BIGINT        NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS updated_at      TIMESTAMPTZ   DEFAULT NOW();

-- ---------------------------------------------------------------
-- 2. Shared stock_reservations table
-- Used by BOTH NON_GST_ERP and GST_ERP applications
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS stock_reservations (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id       UUID         NOT NULL,
    bill_id          TEXT         NOT NULL,
    user_id          TEXT,
    source_app       TEXT         NOT NULL CHECK (source_app IN ('NON_GST_ERP', 'GST_ERP')),
    quantity         NUMERIC(10,2) NOT NULL CHECK (quantity > 0),
    status           TEXT         NOT NULL DEFAULT 'ACTIVE'
                                  CHECK (status IN ('ACTIVE', 'COMPLETED', 'RELEASED', 'EXPIRED')),
    reserved_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    expires_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW() + INTERVAL '2 hours',
    released_at      TIMESTAMPTZ,
    completed_at     TIMESTAMPTZ,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stock_reservations_product_id ON stock_reservations(product_id);
CREATE INDEX IF NOT EXISTS idx_stock_reservations_bill_id    ON stock_reservations(bill_id);
CREATE INDEX IF NOT EXISTS idx_stock_reservations_status     ON stock_reservations(status);
CREATE INDEX IF NOT EXISTS idx_stock_reservations_expires_at ON stock_reservations(expires_at);

-- ---------------------------------------------------------------
-- 3. Disable RLS so service-role backend can access freely
-- ---------------------------------------------------------------
ALTER TABLE stock_reservations DISABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------
-- 4. reserve_stock RPC
-- Atomically reserves stock using SELECT ... FOR UPDATE row locking.
-- Shared contract: both ERP apps call this same function.
-- Parameters:
--   p_product_id  UUID
--   p_bill_id     TEXT
--   p_user_id     TEXT
--   p_source_app  TEXT  ('NON_GST_ERP' or 'GST_ERP')
--   p_quantity    NUMERIC
-- Returns JSON with: success, reservation_id, product_id,
--                    reserved_quantity, remaining_available,
--                    error_code, message
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION reserve_stock(
    p_product_id  UUID,
    p_bill_id     TEXT,
    p_user_id     TEXT,
    p_source_app  TEXT,
    p_quantity    NUMERIC
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_stock  NUMERIC(10,2);
    v_reserved_stock NUMERIC(10,2);
    v_reservation_id UUID;
    v_existing_count INTEGER;
BEGIN
    -- ── Validate quantity ───────────────────────────────────────────
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RETURN json_build_object(
            'success',            false,
            'reservation_id',     NULL,
            'product_id',         p_product_id,
            'reserved_quantity',  0,
            'remaining_available', 0,
            'error_code',         'INVALID_QUANTITY',
            'message',            'Quantity must be greater than 0'
        );
    END IF;

    -- ── Validate source_app ─────────────────────────────────────────
    IF p_source_app NOT IN ('NON_GST_ERP', 'GST_ERP') THEN
        RETURN json_build_object(
            'success',            false,
            'reservation_id',     NULL,
            'product_id',         p_product_id,
            'reserved_quantity',  0,
            'remaining_available', 0,
            'error_code',         'RESERVATION_FAILED',
            'message',            'Invalid source_app. Must be NON_GST_ERP or GST_ERP'
        );
    END IF;

    -- ── Lock inventory row (prevents concurrent modifications) ──────
    SELECT current_stock, reserved_stock
      INTO v_current_stock, v_reserved_stock
      FROM inventory
     WHERE product_id = p_product_id
       FOR UPDATE;

    -- ── Product not found ───────────────────────────────────────────
    IF NOT FOUND THEN
        RETURN json_build_object(
            'success',            false,
            'reservation_id',     NULL,
            'product_id',         p_product_id,
            'reserved_quantity',  0,
            'remaining_available', 0,
            'error_code',         'PRODUCT_NOT_FOUND',
            'message',            'Product not found in inventory'
        );
    END IF;

    -- ── Check for duplicate active reservation (same bill + product) ─
    SELECT COUNT(*) INTO v_existing_count
      FROM stock_reservations
     WHERE product_id = p_product_id
       AND bill_id    = p_bill_id
       AND status     = 'ACTIVE';

    IF v_existing_count > 0 THEN
        RETURN json_build_object(
            'success',            false,
            'reservation_id',     NULL,
            'product_id',         p_product_id,
            'reserved_quantity',  0,
            'remaining_available', v_current_stock,
            'error_code',         'DUPLICATE_RESERVATION',
            'message',            'An active reservation already exists for this product and bill'
        );
    END IF;

    -- ── Check available stock (current_stock IS the available stock) ─
    IF p_quantity > v_current_stock THEN
        RETURN json_build_object(
            'success',            false,
            'reservation_id',     NULL,
            'product_id',         p_product_id,
            'reserved_quantity',  0,
            'remaining_available', v_current_stock,
            'error_code',         'INSUFFICIENT_STOCK',
            'message',            format('Only %s units are currently available', v_current_stock)
        );
    END IF;

    -- ── Deduct from current_stock, add to reserved_stock ───────────
    UPDATE inventory
       SET current_stock  = current_stock  - p_quantity,
           reserved_stock = reserved_stock + p_quantity,
           version        = version + 1,
           updated_at     = NOW()
     WHERE product_id = p_product_id;

    -- ── Insert reservation record ───────────────────────────────────
    INSERT INTO stock_reservations (
        product_id, bill_id, user_id, source_app,
        quantity, status, reserved_at, expires_at
    ) VALUES (
        p_product_id, p_bill_id, p_user_id, p_source_app,
        p_quantity, 'ACTIVE', NOW(), NOW() + INTERVAL '2 hours'
    )
    RETURNING id INTO v_reservation_id;

    RETURN json_build_object(
        'success',            true,
        'reservation_id',     v_reservation_id,
        'product_id',         p_product_id,
        'reserved_quantity',  p_quantity,
        'remaining_available', (v_current_stock - p_quantity),
        'error_code',         NULL,
        'message',            'Stock reserved successfully'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'success',            false,
        'reservation_id',     NULL,
        'product_id',         p_product_id,
        'reserved_quantity',  0,
        'remaining_available', 0,
        'error_code',         'RESERVATION_FAILED',
        'message',            SQLERRM
    );
END;
$$;

-- ---------------------------------------------------------------
-- 5. release_reservation RPC
-- Releases an ACTIVE reservation and restores stock atomically.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION release_reservation(
    p_reservation_id UUID,
    p_source_app     TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_product_id UUID;
    v_quantity   NUMERIC(10,2);
    v_status     TEXT;
BEGIN
    -- Lock the reservation row
    SELECT product_id, quantity, status
      INTO v_product_id, v_quantity, v_status
      FROM stock_reservations
     WHERE id = p_reservation_id
       FOR UPDATE;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success',    false,
            'error_code', 'RESERVATION_NOT_FOUND',
            'message',    'Reservation not found'
        );
    END IF;

    IF v_status != 'ACTIVE' THEN
        RETURN json_build_object(
            'success',    false,
            'error_code', 'RESERVATION_NOT_ACTIVE',
            'message',    format('Cannot release reservation with status %s', v_status)
        );
    END IF;

    -- Restore stock
    UPDATE inventory
       SET current_stock  = current_stock  + v_quantity,
           reserved_stock = reserved_stock - v_quantity,
           version        = version + 1,
           updated_at     = NOW()
     WHERE product_id = v_product_id;

    -- Mark reservation as released
    UPDATE stock_reservations
       SET status      = 'RELEASED',
           released_at = NOW(),
           updated_at  = NOW()
     WHERE id = p_reservation_id;

    RETURN json_build_object(
        'success',    true,
        'error_code', NULL,
        'message',    'Reservation released successfully'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'success',    false,
        'error_code', 'RESERVATION_FAILED',
        'message',    SQLERRM
    );
END;
$$;

-- ---------------------------------------------------------------
-- 6. complete_reservation RPC
-- Completes an ACTIVE reservation (bill finalized).
-- current_stock remains unchanged (already deducted at reserve time).
-- Only reserved_stock is decremented.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION complete_reservation(
    p_reservation_id UUID,
    p_source_app     TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_product_id UUID;
    v_quantity   NUMERIC(10,2);
    v_status     TEXT;
BEGIN
    SELECT product_id, quantity, status
      INTO v_product_id, v_quantity, v_status
      FROM stock_reservations
     WHERE id = p_reservation_id
       FOR UPDATE;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success',    false,
            'error_code', 'RESERVATION_NOT_FOUND',
            'message',    'Reservation not found'
        );
    END IF;

    IF v_status != 'ACTIVE' THEN
        RETURN json_build_object(
            'success',    false,
            'error_code', 'RESERVATION_NOT_ACTIVE',
            'message',    format('Cannot complete reservation with status %s', v_status)
        );
    END IF;

    -- Remove from reserved_stock only; current_stock was already deducted
    UPDATE inventory
       SET reserved_stock = reserved_stock - v_quantity,
           version        = version + 1,
           updated_at     = NOW()
     WHERE product_id = v_product_id;

    UPDATE stock_reservations
       SET status       = 'COMPLETED',
           completed_at = NOW(),
           updated_at   = NOW()
     WHERE id = p_reservation_id;

    RETURN json_build_object(
        'success',    true,
        'error_code', NULL,
        'message',    'Reservation completed successfully'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'success',    false,
        'error_code', 'RESERVATION_FAILED',
        'message',    SQLERRM
    );
END;
$$;

-- ---------------------------------------------------------------
-- 7. expire_stale_reservations RPC
-- Expires ACTIVE reservations past their expires_at timestamp.
-- Call this periodically (e.g. via pg_cron or on product load).
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION expire_stale_reservations()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_expired_count INTEGER := 0;
    v_row RECORD;
BEGIN
    FOR v_row IN
        SELECT id, product_id, quantity
          FROM stock_reservations
         WHERE status = 'ACTIVE'
           AND expires_at < NOW()
         FOR UPDATE SKIP LOCKED
    LOOP
        UPDATE inventory
           SET current_stock  = current_stock  + v_row.quantity,
               reserved_stock = reserved_stock - v_row.quantity,
               version        = version + 1,
               updated_at     = NOW()
         WHERE product_id = v_row.product_id;

        UPDATE stock_reservations
           SET status      = 'EXPIRED',
               released_at = NOW(),
               updated_at  = NOW()
         WHERE id = v_row.id;

        v_expired_count := v_expired_count + 1;
    END LOOP;

    RETURN json_build_object(
        'success',       true,
        'expired_count', v_expired_count,
        'message',       format('Expired %s stale reservations', v_expired_count)
    );
END;
$$;

-- ---------------------------------------------------------------
-- 8. release_bill_reservations RPC
-- Releases ALL active reservations for a given bill atomically.
-- Called when a bill is cancelled.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION release_bill_reservations(
    p_bill_id    TEXT,
    p_source_app TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_released_count INTEGER := 0;
    v_row RECORD;
BEGIN
    FOR v_row IN
        SELECT id, product_id, quantity
          FROM stock_reservations
         WHERE bill_id = p_bill_id
           AND status  = 'ACTIVE'
         FOR UPDATE
    LOOP
        UPDATE inventory
           SET current_stock  = current_stock  + v_row.quantity,
               reserved_stock = reserved_stock - v_row.quantity,
               version        = version + 1,
               updated_at     = NOW()
         WHERE product_id = v_row.product_id;

        UPDATE stock_reservations
           SET status      = 'RELEASED',
               released_at = NOW(),
               updated_at  = NOW()
         WHERE id = v_row.id;

        v_released_count := v_released_count + 1;
    END LOOP;

    RETURN json_build_object(
        'success',        true,
        'released_count', v_released_count,
        'message',        format('Released %s reservations for bill %s', v_released_count, p_bill_id)
    );
END;
$$;

-- ---------------------------------------------------------------
-- 9. complete_bill_reservations RPC
-- Completes ALL active reservations for a given bill atomically.
-- Called when a bill is finalized/saved.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION complete_bill_reservations(
    p_bill_id    TEXT,
    p_source_app TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_completed_count INTEGER := 0;
    v_row RECORD;
BEGIN
    FOR v_row IN
        SELECT id, product_id, quantity
          FROM stock_reservations
         WHERE bill_id = p_bill_id
           AND status  = 'ACTIVE'
         FOR UPDATE
    LOOP
        -- Only decrement reserved_stock; current_stock already removed at reservation
        UPDATE inventory
           SET reserved_stock = reserved_stock - v_row.quantity,
               version        = version + 1,
               updated_at     = NOW()
         WHERE product_id = v_row.product_id;

        UPDATE stock_reservations
           SET status       = 'COMPLETED',
               completed_at = NOW(),
               updated_at   = NOW()
         WHERE id = v_row.id;

        v_completed_count := v_completed_count + 1;
    END LOOP;

    RETURN json_build_object(
        'success',          true,
        'completed_count',  v_completed_count,
        'message',          format('Completed %s reservations for bill %s', v_completed_count, p_bill_id)
    );
END;
$$;

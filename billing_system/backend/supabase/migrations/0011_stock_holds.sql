-- =============================================================
-- Migration 0011: Stock Hold system (NON_GST_ERP)
-- Bill holds stock (current_stock untouched); only the stock-out
-- person's release_hold reduces current_stock.
-- Shared inventory with GST_ERP; existing RPCs untouched.
-- Run once in Supabase SQL Editor. Safe to re-run.
-- =============================================================

-- ---------------------------------------------------------------
-- 1. Add 'HELD' to the status enum (idempotent swap)
-- ---------------------------------------------------------------
ALTER TABLE stock_reservations DROP CONSTRAINT IF EXISTS stock_reservations_status_check;
ALTER TABLE stock_reservations ADD CONSTRAINT stock_reservations_status_check
  CHECK (status IN ('ACTIVE','COMPLETED','RELEASED','EXPIRED','HELD'));

-- ---------------------------------------------------------------
-- 2. hold_stock RPC
-- Reserves stock WITHOUT deducting current_stock (unlike reserve_stock).
-- Only reserved_stock increases. Row-locked with SELECT ... FOR UPDATE.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION hold_stock(
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

    -- ── Check for duplicate HELD reservation (same bill + product) ──
    SELECT COUNT(*) INTO v_existing_count
      FROM stock_reservations
     WHERE product_id = p_product_id
       AND bill_id    = p_bill_id
       AND status     = 'HELD';

    IF v_existing_count > 0 THEN
        RETURN json_build_object(
            'success',            false,
            'reservation_id',     NULL,
            'product_id',         p_product_id,
            'reserved_quantity',  0,
            'remaining_available', (v_current_stock - v_reserved_stock),
            'error_code',         'DUPLICATE_RESERVATION',
            'message',            'A hold already exists for this product and bill'
        );
    END IF;

    -- ── Check available stock (current_stock - reserved_stock) ──────
    IF p_quantity > (v_current_stock - v_reserved_stock) THEN
        RETURN json_build_object(
            'success',            false,
            'reservation_id',     NULL,
            'product_id',         p_product_id,
            'reserved_quantity',  0,
            'remaining_available', (v_current_stock - v_reserved_stock),
            'error_code',         'INSUFFICIENT_STOCK',
            'message',            format('Only %s units are currently available', (v_current_stock - v_reserved_stock))
        );
    END IF;

    -- ── Only reserved_stock increases; current_stock stays untouched ──
    UPDATE inventory
       SET reserved_stock = reserved_stock + p_quantity,
           version        = version + 1,
           updated_at     = NOW()
     WHERE product_id = p_product_id;

    -- ── Insert HELD reservation (no expiry - persists until release/cancel) ──
    INSERT INTO stock_reservations (
        product_id, bill_id, user_id, source_app,
        quantity, status, reserved_at, expires_at
    ) VALUES (
        p_product_id, p_bill_id, p_user_id, p_source_app,
        p_quantity, 'HELD', NOW(), NULL
    )
    RETURNING id INTO v_reservation_id;

    RETURN json_build_object(
        'success',            true,
        'reservation_id',     v_reservation_id,
        'product_id',         p_product_id,
        'reserved_quantity',  p_quantity,
        'remaining_available', (v_current_stock - v_reserved_stock - p_quantity),
        'error_code',         NULL,
        'message',            'Stock held successfully'
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
-- 3. release_hold RPC
-- Stock-out action: deducts current_stock AND reserved_stock.
-- The ONLY place current_stock decreases in the NON_GST flow.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION release_hold(
    p_reservation_id UUID,
    p_source_app     TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_status        TEXT;
    v_product_id    UUID;
    v_quantity      NUMERIC(10,2);
    v_current_stock NUMERIC(10,2);
BEGIN
    -- ── Lock the reservation row ────────────────────────────────────
    SELECT status, product_id, quantity
      INTO v_status, v_product_id, v_quantity
      FROM stock_reservations
     WHERE id = p_reservation_id
       AND source_app = p_source_app
       FOR UPDATE;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success',        false,
            'error_code',     'RESERVATION_NOT_FOUND',
            'message',        'Hold not found'
        );
    END IF;

    IF v_status <> 'HELD' THEN
        RETURN json_build_object(
            'success',        false,
            'error_code',     'RESERVATION_NOT_ACTIVE',
            'message',        format('Cannot release hold with status %s', v_status)
        );
    END IF;

    -- ── Lock inventory row and guard against insufficient stock ─────
    SELECT current_stock
      INTO v_current_stock
      FROM inventory
     WHERE product_id = v_product_id
       FOR UPDATE;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success',        false,
            'error_code',     'PRODUCT_NOT_FOUND',
            'message',        'Product not found in inventory'
        );
    END IF;

    IF v_quantity > v_current_stock THEN
        RETURN json_build_object(
            'success',        false,
            'error_code',     'INSUFFICIENT_STOCK',
            'message',        format('Only %s units in stock, cannot release %s', v_current_stock, v_quantity)
        );
    END IF;

    -- ── Deduct both counters ────────────────────────────────────────
    UPDATE inventory
       SET current_stock  = current_stock  - v_quantity,
           reserved_stock = reserved_stock - v_quantity,
           version        = version + 1,
           updated_at     = NOW()
     WHERE product_id = v_product_id;

    UPDATE stock_reservations
       SET status      = 'RELEASED',
           released_at = NOW(),
           updated_at  = NOW()
     WHERE id = p_reservation_id;

    RETURN json_build_object(
        'success',            true,
        'reservation_id',     p_reservation_id,
        'product_id',         v_product_id,
        'released_quantity',  v_quantity,
        'remaining_available', (v_current_stock - v_quantity),
        'error_code',         NULL,
        'message',            'Hold released, stock deducted'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'success',        false,
        'reservation_id', p_reservation_id,
        'error_code',     'RESERVATION_FAILED',
        'message',        SQLERRM
    );
END;
$$;

-- ---------------------------------------------------------------
-- 4. cancel_hold RPC
-- Cancels a hold WITHOUT touching current_stock (reserved_stock only).
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION cancel_hold(
    p_reservation_id UUID,
    p_source_app     TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_status     TEXT;
    v_product_id UUID;
    v_quantity   NUMERIC(10,2);
BEGIN
    SELECT status, product_id, quantity
      INTO v_status, v_product_id, v_quantity
      FROM stock_reservations
     WHERE id = p_reservation_id
       AND source_app = p_source_app
       FOR UPDATE;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success',        false,
            'error_code',     'RESERVATION_NOT_FOUND',
            'message',        'Hold not found'
        );
    END IF;

    IF v_status <> 'HELD' THEN
        RETURN json_build_object(
            'success',        false,
            'error_code',     'RESERVATION_NOT_ACTIVE',
            'message',        format('Cannot cancel hold with status %s', v_status)
        );
    END IF;

    UPDATE inventory
       SET reserved_stock = reserved_stock - v_quantity,
           version        = version + 1,
           updated_at     = NOW()
     WHERE product_id = v_product_id;

    UPDATE stock_reservations
       SET status      = 'EXPIRED',
           released_at = NOW(),
           updated_at  = NOW()
     WHERE id = p_reservation_id;

    RETURN json_build_object(
        'success',           true,
        'reservation_id',    p_reservation_id,
        'cancelled_quantity', v_quantity,
        'error_code',        NULL,
        'message',           'Hold cancelled'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'success',        false,
        'reservation_id', p_reservation_id,
        'error_code',     'RESERVATION_FAILED',
        'message',        SQLERRM
    );
END;
$$;

-- ---------------------------------------------------------------
-- 5. update_hold RPC
-- Atomically changes a HELD reservation's quantity.
-- Delta applies to reserved_stock only (current_stock never moves).
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_hold(
    p_reservation_id UUID,
    p_new_quantity   NUMERIC,
    p_source_app     TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_old_quantity  NUMERIC(10,2);
    v_product_id    UUID;
    v_delta         NUMERIC(10,2);
    v_current_stock NUMERIC(10,2);
    v_reserved_stock NUMERIC(10,2);
BEGIN
    IF p_new_quantity IS NULL OR p_new_quantity <= 0 THEN
        RETURN json_build_object(
            'success',    false,
            'error_code', 'INVALID_QUANTITY',
            'message',    'new_quantity must be greater than 0'
        );
    END IF;

    SELECT quantity, product_id
      INTO v_old_quantity, v_product_id
      FROM stock_reservations
     WHERE id = p_reservation_id
       AND source_app = p_source_app
       FOR UPDATE;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success',    false,
            'error_code', 'RESERVATION_NOT_FOUND',
            'message',    'Hold not found'
        );
    END IF;

    v_delta := p_new_quantity - v_old_quantity;

    IF v_delta = 0 THEN
        RETURN json_build_object(
            'success',             true,
            'reservation_id',      p_reservation_id,
            'old_quantity',        v_old_quantity,
            'new_quantity',        p_new_quantity,
            'remaining_available', 0,
            'error_code',          NULL,
            'message',             'No change'
        );
    END IF;

    SELECT current_stock, reserved_stock
      INTO v_current_stock, v_reserved_stock
      FROM inventory
     WHERE product_id = v_product_id
       FOR UPDATE;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success',    false,
            'error_code', 'PRODUCT_NOT_FOUND',
            'message',    'Product not found in inventory'
        );
    END IF;

    IF v_delta > 0 AND v_delta > (v_current_stock - v_reserved_stock) THEN
        RETURN json_build_object(
            'success',             false,
            'error_code',          'INSUFFICIENT_STOCK',
            'message',             format('Only %s additional units are available', (v_current_stock - v_reserved_stock)),
            'remaining_available', (v_current_stock - v_reserved_stock)
        );
    END IF;

    UPDATE inventory
       SET reserved_stock = reserved_stock + v_delta,
           version        = version + 1,
           updated_at     = NOW()
     WHERE product_id = v_product_id;

    UPDATE stock_reservations
       SET quantity   = p_new_quantity,
           updated_at = NOW()
     WHERE id = p_reservation_id;

    RETURN json_build_object(
        'success',             true,
        'reservation_id',      p_reservation_id,
        'old_quantity',        v_old_quantity,
        'new_quantity',        p_new_quantity,
        'remaining_available', (v_current_stock - v_reserved_stock - v_delta),
        'error_code',          NULL,
        'message',             'Hold updated'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'success',        false,
        'reservation_id', p_reservation_id,
        'error_code',     'RESERVATION_FAILED',
        'message',        SQLERRM
    );
END;
$$;

-- ---------------------------------------------------------------
-- 6. cancel_bill_holds RPC
-- Cancels ALL HELD reservations for a bill (bill cancelled / deleted).
-- reserved_stock only; current_stock never changes.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION cancel_bill_holds(
    p_bill_id    TEXT,
    p_source_app TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_row   RECORD;
    v_count INTEGER := 0;
BEGIN
    FOR v_row IN
        SELECT id, product_id, quantity
          FROM stock_reservations
         WHERE bill_id = p_bill_id
           AND status  = 'HELD'
           AND source_app = p_source_app
         FOR UPDATE
    LOOP
        UPDATE inventory
           SET reserved_stock = reserved_stock - v_row.quantity,
               version        = version + 1,
               updated_at     = NOW()
         WHERE product_id = v_row.product_id;

        UPDATE stock_reservations
           SET status      = 'EXPIRED',
               released_at = NOW(),
               updated_at  = NOW()
         WHERE id = v_row.id;

        v_count := v_count + 1;
    END LOOP;

    RETURN json_build_object(
        'success',        true,
        'cancelled_count', v_count,
        'message',        format('Cancelled %s holds for bill %s', v_count, p_bill_id)
    );
END;
$$;

-- ---------------------------------------------------------------
-- 7. expire_stale_holds RPC
-- Cancels only abandoned DRAFT-* holds older than p_hours.
-- Real-bill holds never expire.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION expire_stale_holds(
    p_hours      NUMERIC DEFAULT 2,
    p_source_app TEXT    DEFAULT 'NON_GST_ERP'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_row   RECORD;
    v_count INTEGER := 0;
BEGIN
    FOR v_row IN
        SELECT id, product_id, quantity
          FROM stock_reservations
         WHERE status       = 'HELD'
           AND source_app   = p_source_app
           AND bill_id      LIKE 'DRAFT-%'
           AND reserved_at  < NOW() - (p_hours || ' hours')::interval
         FOR UPDATE SKIP LOCKED
    LOOP
        UPDATE inventory
           SET reserved_stock = reserved_stock - v_row.quantity,
               version        = version + 1,
               updated_at     = NOW()
         WHERE product_id = v_row.product_id;

        UPDATE stock_reservations
           SET status      = 'EXPIRED',
               released_at = NOW(),
               updated_at  = NOW()
         WHERE id = v_row.id;

        v_count := v_count + 1;
    END LOOP;

    RETURN json_build_object(
        'success',      true,
        'expired_count', v_count,
        'message',      format('Expired %s stale draft holds', v_count)
    );
END;
$$;

-- ---------------------------------------------------------------
-- 8. link_holds_to_bill RPC
-- Attaches HELD reservations from a draft id to the real bill number
-- when the bill is saved.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION link_holds_to_bill(
    p_old_bill_id TEXT,
    p_new_bill_id TEXT,
    p_source_app  TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    UPDATE stock_reservations
       SET bill_id    = p_new_bill_id,
           updated_at = NOW()
     WHERE bill_id     = p_old_bill_id
       AND status      = 'HELD'
       AND source_app  = p_source_app;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN json_build_object(
        'success',     true,
        'linked_count', v_count,
        'message',     format('Linked %s holds to bill %s', v_count, p_new_bill_id)
    );
END;
$$;

NOTIFY pgrst, 'reload schema';

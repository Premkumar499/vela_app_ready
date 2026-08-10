-- =============================================================
-- Migration 0006: update_reservation RPC
-- Atomically adjusts an existing ACTIVE reservation quantity.
-- Shared contract: both NON_GST_ERP and GST_ERP use this function.
--
-- IMPORTANT: Run this in Supabase SQL Editor before using
-- the quantity-change feature in the POS screen.
--
-- Why a dedicated RPC instead of release + re-reserve?
-- A separate release followed by a new reserve_stock call creates a
-- race-condition window where another app can grab the freed stock
-- before the re-reserve lands.  This function holds the inventory
-- row lock for the entire delta operation.
--
-- NOTE on existing RPC signatures in this DB:
--   release_reservation(p_reservation_id)          -- no p_source_app
--   complete_reservation(p_reservation_id)         -- no p_source_app
--   All others use p_ prefix params.
--
-- Parameters:
--   p_reservation_id   UUID   – the ACTIVE reservation to modify
--   p_new_quantity     NUMERIC – the desired new quantity
--   p_source_app       TEXT   – 'NON_GST_ERP' | 'GST_ERP'
--
-- Returns JSON:
--   success, reservation_id, product_id, old_quantity, new_quantity,
--   remaining_available, error_code, message
-- =============================================================

CREATE OR REPLACE FUNCTION update_reservation(
    p_reservation_id  UUID,
    p_new_quantity    NUMERIC,
    p_source_app      TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_product_id     UUID;
    v_old_quantity   NUMERIC(10,2);
    v_status         TEXT;
    v_current_stock  NUMERIC(10,2);
    v_delta          NUMERIC(10,2);
BEGIN
    -- ── Validate new quantity ───────────────────────────────────────
    IF p_new_quantity IS NULL OR p_new_quantity <= 0 THEN
        RETURN json_build_object(
            'success',             false,
            'reservation_id',      p_reservation_id,
            'product_id',          NULL,
            'old_quantity',        0,
            'new_quantity',        0,
            'remaining_available', 0,
            'error_code',          'INVALID_QUANTITY',
            'message',             'New quantity must be greater than 0'
        );
    END IF;

    -- ── Lock the reservation row ────────────────────────────────────
    SELECT product_id, quantity, status
      INTO v_product_id, v_old_quantity, v_status
      FROM stock_reservations
     WHERE id = p_reservation_id
       FOR UPDATE;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success',             false,
            'reservation_id',      p_reservation_id,
            'product_id',          NULL,
            'old_quantity',        0,
            'new_quantity',        0,
            'remaining_available', 0,
            'error_code',          'RESERVATION_NOT_FOUND',
            'message',             'Reservation not found'
        );
    END IF;

    IF v_status != 'ACTIVE' THEN
        RETURN json_build_object(
            'success',             false,
            'reservation_id',      p_reservation_id,
            'product_id',          v_product_id,
            'old_quantity',        v_old_quantity,
            'new_quantity',        p_new_quantity,
            'remaining_available', 0,
            'error_code',          'RESERVATION_NOT_ACTIVE',
            'message',             format('Cannot update reservation with status %s', v_status)
        );
    END IF;

    -- ── Lock the inventory row ──────────────────────────────────────
    SELECT current_stock
      INTO v_current_stock
      FROM inventory
     WHERE product_id = v_product_id
       FOR UPDATE;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success',             false,
            'reservation_id',      p_reservation_id,
            'product_id',          v_product_id,
            'old_quantity',        v_old_quantity,
            'new_quantity',        p_new_quantity,
            'remaining_available', 0,
            'error_code',          'PRODUCT_NOT_FOUND',
            'message',             'Product not found in inventory'
        );
    END IF;

    -- ── Compute delta: positive = increase, negative = decrease ────
    v_delta := p_new_quantity - v_old_quantity;

    -- ── If increasing, check there is enough available stock ────────
    IF v_delta > 0 AND v_delta > v_current_stock THEN
        RETURN json_build_object(
            'success',             false,
            'reservation_id',      p_reservation_id,
            'product_id',          v_product_id,
            'old_quantity',        v_old_quantity,
            'new_quantity',        p_new_quantity,
            'remaining_available', v_current_stock,
            'error_code',          'INSUFFICIENT_STOCK',
            'message',             format('Only %s additional units are available (need %s more)',
                                          v_current_stock, v_delta)
        );
    END IF;

    -- ── Apply delta to inventory ────────────────────────────────────
    -- Increasing: current_stock ↓, reserved_stock ↑
    -- Decreasing: current_stock ↑, reserved_stock ↓
    UPDATE inventory
       SET current_stock  = current_stock  - v_delta,
           reserved_stock = reserved_stock + v_delta,
           version        = version + 1,
           updated_at     = NOW()
     WHERE product_id = v_product_id;

    -- ── Update reservation quantity and reset expiry ────────────────
    UPDATE stock_reservations
       SET quantity    = p_new_quantity,
           expires_at  = NOW() + INTERVAL '2 hours',
           updated_at  = NOW()
     WHERE id = p_reservation_id;

    RETURN json_build_object(
        'success',             true,
        'reservation_id',      p_reservation_id,
        'product_id',          v_product_id,
        'old_quantity',        v_old_quantity,
        'new_quantity',        p_new_quantity,
        'remaining_available', (v_current_stock - v_delta),
        'error_code',          NULL,
        'message',             format('Reservation updated from %s to %s units',
                                      v_old_quantity, p_new_quantity)
    );

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'success',             false,
        'reservation_id',      p_reservation_id,
        'product_id',          NULL,
        'old_quantity',        0,
        'new_quantity',        0,
        'remaining_available', 0,
        'error_code',          'RESERVATION_FAILED',
        'message',             SQLERRM
    );
END;
$$;

# Supabase Stock Concurrency Setup Guide

This guide details how the system prevents overselling using atomic PostgreSQL row locking. 

For example: **If a product has 50 units in stock, and you reserve 30 units, your friend's system will only be allowed to select up to 20 units (not more than 20).**

---

## 1. How It Works (Concurrency Mechanics)

Stock reservations use a Postgres database-level transaction function (`reserve_stock`) executed in Supabase:
1. **Row-Level Locking:** When you try to reserve stock, Postgres performs `SELECT current_stock FROM inventory WHERE product_id = p_product_id FOR UPDATE;`. This locks the inventory row, forcing other concurrent requests for the same product to wait until your transaction decides to commit or rollback.
2. **Atomic Verification:** Inside that locked transaction, the database checks if `requested_quantity <= current_stock`.
   - If **yes**, it deducts the quantity from `current_stock`, adds it to `reserved_stock`, inserts a record in `stock_reservations` with status `ACTIVE` (with a 2-hour expiry), and commits the transaction.
   - If **no**, it immediately rolls back and returns an `INSUFFICIENT_STOCK` error.
3. **Friend's Reservation:** Because your transaction is committed, the available stock is now `20`. When your friend attempts to reserve `25`, the check `25 > 20` fails, and they get blocked. If they reserve `20` or less, it succeeds.

---

## 2. Supabase Database Schema & Function Setup

Run the following SQL in your **Supabase SQL Editor** to deploy the concurrency control system on your friend's database:

```sql
-- ---------------------------------------------------------------
-- 1. Ensure inventory columns are present
-- ---------------------------------------------------------------
ALTER TABLE inventory
  ADD COLUMN IF NOT EXISTS reserved_stock  NUMERIC(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS version         BIGINT        NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS updated_at      TIMESTAMPTZ   DEFAULT NOW();

-- ---------------------------------------------------------------
-- 2. Create the stock_reservations log table
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

-- Indices for rapid concurrent lookups
CREATE INDEX IF NOT EXISTS idx_stock_reservations_product_id ON stock_reservations(product_id);
CREATE INDEX IF NOT EXISTS idx_stock_reservations_bill_id    ON stock_reservations(bill_id);
CREATE INDEX IF NOT EXISTS idx_stock_reservations_status     ON stock_reservations(status);
CREATE INDEX IF NOT EXISTS idx_stock_reservations_expires_at ON stock_reservations(expires_at);

-- Disable Row-Level Security so the backend services can manage stock reservations
ALTER TABLE stock_reservations DISABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------
-- 3. Atomic stock reservation RPC (reserve_stock)
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
    -- Validate quantity
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

    -- Validate source application identifier
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

    -- Lock the product's inventory row to block other concurrent updates
    SELECT current_stock, reserved_stock
      INTO v_current_stock, v_reserved_stock
      FROM inventory
     WHERE product_id = p_product_id
       FOR UPDATE;

    -- Handle missing product
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

    -- Check if this specific bill already reserved this product
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

    -- Perform stock check
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

    -- Deduct live stock and increment reserved stock
    UPDATE inventory
       SET current_stock  = current_stock  - p_quantity,
           reserved_stock = reserved_stock + p_quantity,
           version        = version + 1,
           updated_at     = NOW()
     WHERE product_id = p_product_id;

    -- Insert active reservation
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
```

---

## 3. Python Integration Example

Call the RPC function from your Python backend services like so:

```python
def reserve_product_stock(supabase_client, product_uuid, bill_id, quantity, user_uuid=None):
    """
    Safely reserve stock using the database-level lock.
    """
    response = supabase_client.rpc(
        "reserve_stock",
        {
            "p_product_id": product_uuid,
            "p_bill_id": bill_id,
            "p_user_id": user_uuid or "",
            "p_source_app": "NON_GST_ERP",
            "p_quantity": float(quantity)
        }
    ).execute()
    
    # The database function returns JSON which gets parsed into a list or dict
    result = response.data
    if isinstance(result, list):
        result = result[0]
        
    return result
```

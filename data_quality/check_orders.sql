-- =============================================================================
-- DATA QUALITY CHECK: bronze.orders
-- Layer   : Bronze → Silver
-- Table   : bronze.orders
-- Author  : Salman
-- Date    : 2026-05-02
-- Purpose : Validate data before loading into silver layer
-- =============================================================================
-- Table context:
--   The orders table contains header information for each customer order.
--   Primary key is order_id (one row per order).
--   Some date columns can be NULL depending on order status:
--     - order_approved_at           : NULL if order was cancelled before approval
--     - order_delivered_carrier_date: NULL if order never reached the carrier
--     - order_delivered_customer_date: NULL if order never reached the customer
--   order_purchase_timestamp and order_estimated_delivery_date must not be NULL.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. PRIMARY KEY CHECK
--    Expectation : no result (no duplicates, no NULLs)
-- -----------------------------------------------------------------------------

SELECT
    order_id,
    COUNT(*) AS total
FROM workspace.bronze.orders
GROUP BY order_id
HAVING COUNT(*) > 1
    OR order_id IS NULL;

-- Result: no result ✓


-- -----------------------------------------------------------------------------
-- 2. NULL CHECK — mandatory columns
--    Context     : only order_purchase_timestamp and order_estimated_delivery_date
--                  must not be NULL. Other date columns can be NULL depending
--                  on order lifecycle status.
--    Expectation : 0
-- -----------------------------------------------------------------------------

-- 2a. order_purchase_timestamp — must not be NULL
SELECT COUNT(*) AS null_count
FROM workspace.bronze.orders
WHERE order_purchase_timestamp IS NULL;

-- Result: 0 ✓

-- 2b. order_estimated_delivery_date — must not be NULL
SELECT COUNT(*) AS null_count
FROM workspace.bronze.orders
WHERE order_estimated_delivery_date IS NULL;

-- Result: 0 ✓

-- 2c. Nullable columns — log counts
SELECT COUNT(*) AS null_approved
FROM workspace.bronze.orders
WHERE order_approved_at IS NULL;
-- Result: 160 — expected for orders cancelled before approval

SELECT COUNT(*) AS null_carrier
FROM workspace.bronze.orders
WHERE order_delivered_carrier_date IS NULL;
-- Result: 1,783 — expected for orders that never reached the carrier

SELECT COUNT(*) AS null_customer
FROM workspace.bronze.orders
WHERE order_delivered_customer_date IS NULL;
-- Result: 2,965 — expected for orders that never reached the customer


-- -----------------------------------------------------------------------------
-- 3. DATE VALIDITY CHECK — all date columns
--    Expectation : no result
-- -----------------------------------------------------------------------------

SELECT COUNT(*) AS invalid_purchase
FROM workspace.bronze.orders
WHERE order_purchase_timestamp < '2000-01-01'
   OR order_purchase_timestamp > current_timestamp();
-- Result: no result ✓

SELECT COUNT(*) AS invalid_approved
FROM workspace.bronze.orders
WHERE order_approved_at < '2000-01-01'
   OR order_approved_at > current_timestamp();
-- Result: no result ✓

SELECT COUNT(*) AS invalid_carrier
FROM workspace.bronze.orders
WHERE order_delivered_carrier_date < '2000-01-01'
   OR order_delivered_carrier_date > current_timestamp();
-- Result: no result ✓

SELECT COUNT(*) AS invalid_customer
FROM workspace.bronze.orders
WHERE order_delivered_customer_date < '2000-01-01'
   OR order_delivered_customer_date > current_timestamp();
-- Result: no result ✓

SELECT COUNT(*) AS invalid_estimated
FROM workspace.bronze.orders
WHERE order_estimated_delivery_date < '2000-01-01'
   OR order_estimated_delivery_date > current_timestamp();
-- Result: no result ✓


-- -----------------------------------------------------------------------------
-- 4. ORDER STATUS VALID VALUES CHECK
--    Context     : order_status must only contain known valid lifecycle values
--    Expectation : only values from the Olist order lifecycle
-- -----------------------------------------------------------------------------

SELECT DISTINCT order_status
FROM workspace.bronze.orders;

-- Result: approved, delivered, created, processing,
--         invoiced, unavailable, canceled, shipped ✓
-- All 8 values are valid Olist order lifecycle statuses


-- -----------------------------------------------------------------------------
-- 5. DATE-STATUS CONSISTENCY CHECK
--    Context     : NULL date columns must be consistent with order_status
--    Expectation : no result for anomalies
-- -----------------------------------------------------------------------------

-- 5a. Anomaly: delivered but customer_date is NULL
SELECT COUNT(*) AS inconsistent
FROM workspace.bronze.orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NULL;
-- Result: 8 rows ⚠️ — known issue, cannot be fixed

-- 5b. Anomaly: shipped but carrier_date is NULL
SELECT COUNT(*) AS inconsistent
FROM workspace.bronze.orders
WHERE order_status = 'shipped'
  AND order_delivered_carrier_date IS NULL;
-- Result: 0 ✓

-- 5c. Expected: canceled with approved_at NULL
SELECT COUNT(*) AS canceled_null
FROM workspace.bronze.orders
WHERE order_status = 'canceled'
  AND order_approved_at IS NULL;
-- Result: 141 — expected, order cancelled before approval ✓


-- =============================================================================
-- SUMMARY
-- =============================================================================
-- | No | Check                              | Column                    | Result       |
-- |----|------------------------------------|--------------------------  |--------------|
-- |  1 | Duplicate/NULL primary key         | order_id                  | Clean ✓      |
-- |  2 | NULL — order_purchase_timestamp    | order_purchase_timestamp  | Clean ✓      |
-- |  2 | NULL — order_estimated_delivery    | order_estimated_delivery_ | Clean ✓      |
-- |    |                                    | date                      |              |
-- |  2 | NULL — order_approved_at           | order_approved_at         | ⚠️ 160 rows  |
-- |  2 | NULL — carrier_date               | order_delivered_carrier_  | ⚠️ 1783 rows |
-- |    |                                    | date                      |              |
-- |  2 | NULL — customer_date              | order_delivered_customer_ | ⚠️ 2965 rows |
-- |    |                                    | date                      |              |
-- |  3 | Date validity all columns          | all date columns          | Clean ✓      |
-- |  4 | Order status valid values          | order_status              | Clean ✓      |
-- |  5 | delivered but customer_date NULL   | order_status,             | ⚠️ 8 rows    |
-- |    |                                    | order_delivered_customer_ |              |
-- |    |                                    | date                      |              |
-- |  5 | shipped but carrier_date NULL      | order_status,             | Clean ✓      |
-- |    |                                    | order_delivered_carrier_  |              |
-- |    |                                    | date                      |              |
-- |  5 | canceled with approved_at NULL     | order_status,             | Expected ✓   |
-- |    |                                    | order_approved_at         |              |
-- =============================================================================
-- CONCLUSION:
--   Table is relatively clean. NULL date values are expected behavior based on
--   order lifecycle. No transformations required in silver layer.
--
-- KNOWN ISSUE:
--   8 orders with status 'delivered' have NULL order_delivered_customer_date.
--   This is a source data anomaly that cannot be fixed.
--   Impact: delivery time analysis for these 8 orders will be inaccurate.
-- =============================================================================

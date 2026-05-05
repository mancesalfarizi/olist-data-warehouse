-- =============================================================================
-- DATA QUALITY CHECK: bronze.order_items
-- Layer   : Bronze → Silver
-- Table   : bronze.order_items
-- Author  : Salman
-- Date    : 2026-05-02
-- Purpose : Validate data before loading into silver layer
-- =============================================================================
-- Table context:
--   The order_items table contains details of items within each order.
--   One order can have more than one item, indicated by the order_item_id column.
--   Primary key is a composite key: (order_id, order_item_id).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. PRIMARY KEY CHECK (COMPOSITE)
--    Context     : PK is the combination of order_id + order_item_id.
--                  One order_id can appear more than once because one order
--                  can have multiple items — this is EXPECTED, not a duplicate.
--    Expectation : no result
-- -----------------------------------------------------------------------------

SELECT
    order_id,
    order_item_id,
    COUNT(*) AS cnt
FROM workspace.bronze.order_items
GROUP BY order_id, order_item_id
HAVING COUNT(*) > 1
    OR order_id IS NULL;

-- Result: no result ✓


-- -----------------------------------------------------------------------------
-- 2. NULL CHECK — all columns
--    Expectation : 0
-- -----------------------------------------------------------------------------

SELECT COUNT(*) AS null_count
FROM workspace.bronze.order_items
WHERE order_id            IS NULL
   OR order_item_id       IS NULL
   OR product_id          IS NULL
   OR seller_id           IS NULL
   OR shipping_limit_date IS NULL
   OR price               IS NULL
   OR freight_value       IS NULL;

-- Result: 0 ✓


-- -----------------------------------------------------------------------------
-- 3. PRICE & FREIGHT VALUE CHECK
--    Context     : price must not be zero or negative,
--                  freight_value must not be negative (can be zero for free shipping)
--    Expectation : no result
-- -----------------------------------------------------------------------------

SELECT COUNT(*) AS invalid_count
FROM workspace.bronze.order_items
WHERE price <= 0
   OR freight_value < 0;

-- Result: no result ✓


-- -----------------------------------------------------------------------------
-- 4. SHIPPING DATE VALIDITY CHECK
--    Context     : shipping_limit_date must be within a reasonable date range
--    Expectation : no result
-- -----------------------------------------------------------------------------

SELECT COUNT(*) AS invalid_date
FROM workspace.bronze.order_items
WHERE shipping_limit_date < '2000-01-01'
   OR shipping_limit_date > '2030-01-01';

-- Result: no result ✓


-- -----------------------------------------------------------------------------
-- 5. UNWANTED SPACES CHECK
--    Columns checked : order_id, product_id, seller_id
--    Expectation     : no result
-- -----------------------------------------------------------------------------

SELECT COUNT(*) AS space_count
FROM workspace.bronze.order_items
WHERE order_id   != TRIM(order_id)
   OR product_id != TRIM(product_id)
   OR seller_id  != TRIM(seller_id);

-- Result: no result ✓


-- =============================================================================
-- SUMMARY
-- =============================================================================
-- | No | Check                              | Column                  | Result  |
-- |----|------------------------------------|-----------------------  |---------|
-- |  1 | Duplicate/NULL composite key       | order_id, order_item_id | Clean ✓ |
-- |  2 | NULL check all columns             | all columns             | Clean ✓ |
-- |  3 | Negative/zero price & freight      | price, freight_value    | Clean ✓ |
-- |  4 | Shipping date validity             | shipping_limit_date     | Clean ✓ |
-- |  5 | Unwanted spaces                    | order_id, product_id,   | Clean ✓ |
-- |    |                                    | seller_id               |         |
-- =============================================================================
-- CONCLUSION: No issues found. Table is ready to load into silver layer
--             without additional transformations (other than adding dwh_create_date).
-- =============================================================================

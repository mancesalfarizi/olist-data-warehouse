-- =============================================================================
-- DATA QUALITY CHECK: bronze.products
-- Layer   : Bronze → Silver
-- Table   : bronze.products
-- Author  : Salman
-- Date    : 2026-05-02
-- Purpose : Validate data before loading into silver layer
-- =============================================================================
-- Table context:
--   The products table contains information about products sold on the Olist
--   platform. Primary key is product_id (one row per product).
--   Some columns can be NULL based on source data conditions.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. PRIMARY KEY CHECK
--    Expectation : no result (no duplicates, no NULLs)
-- -----------------------------------------------------------------------------

SELECT
    product_id,
    COUNT(*) AS cnt
FROM workspace.bronze.products
GROUP BY product_id
HAVING COUNT(*) > 1
    OR product_id IS NULL;

-- Result: no result ✓


-- -----------------------------------------------------------------------------
-- 2. NULL CHECK — all columns
--    Context     : several columns found to have NULLs in two distinct patterns
--    Expectation : log counts and patterns per column
-- -----------------------------------------------------------------------------

SELECT
    COUNT(*)                                                                AS total,
    SUM(CASE WHEN product_category_name      IS NULL THEN 1 ELSE 0 END)    AS null_category,
    SUM(CASE WHEN product_name_lenght        IS NULL THEN 1 ELSE 0 END)    AS null_name_len,
    SUM(CASE WHEN product_description_lenght IS NULL THEN 1 ELSE 0 END)    AS null_desc_len,
    SUM(CASE WHEN product_photos_qty         IS NULL THEN 1 ELSE 0 END)    AS null_photos,
    SUM(CASE WHEN product_weight_g           IS NULL THEN 1 ELSE 0 END)    AS null_weight,
    SUM(CASE WHEN product_length_cm          IS NULL THEN 1 ELSE 0 END)    AS null_length,
    SUM(CASE WHEN product_height_cm          IS NULL THEN 1 ELSE 0 END)    AS null_height,
    SUM(CASE WHEN product_width_cm           IS NULL THEN 1 ELSE 0 END)    AS null_width
FROM workspace.bronze.products;

-- Result: 32,951 total rows
-- Two NULL patterns found:
--
-- Pattern 1 (610 rows):
--   null_category = 610, null_name_len = 610, null_desc_len = 610, null_photos = 610
--   → Products with no category or description info at all
--   → Fix: COALESCE(product_category_name, 'unknown') in silver layer
--
-- Pattern 2 (2 rows):
--   null_weight = 2, null_length = 2, null_height = 2, null_width = 2
--   → Products with no dimension/weight data
--   → Must be retained — these product_id are referenced by transactions
--   → Left as NULL in silver layer (cannot be imputed)


-- -----------------------------------------------------------------------------
-- 3. NULL DETAIL — pattern 2 (dimension/weight NULL)
--    Context     : investigate products with NULL dimensions/weight
-- -----------------------------------------------------------------------------

SELECT *
FROM workspace.bronze.products
WHERE product_weight_g  IS NULL
   OR product_length_cm IS NULL
   OR product_height_cm IS NULL
   OR product_width_cm  IS NULL;

-- Result: 2 rows
-- product_id: 09ff539a... → has category 'bebes', NULL dimensions
-- product_id: 5eb564652... → all columns NULL (ghost record)

-- Check if the all-NULL product_id exists in order_items
SELECT COUNT(*) AS total_orders
FROM workspace.bronze.order_items
WHERE product_id = '5eb564652db742ff8f28759cd8d2652a';

-- Result: 17 → must be retained, 17 transactions reference this product


-- -----------------------------------------------------------------------------
-- 4. UNWANTED SPACES CHECK
--    Column checked : product_category_name
--    Expectation    : no result
-- -----------------------------------------------------------------------------

SELECT COUNT(*) AS space_count
FROM workspace.bronze.products
WHERE product_category_name != TRIM(product_category_name);

-- Result: no result ✓


-- -----------------------------------------------------------------------------
-- 5. NUMERIC VALUE VALIDITY CHECK
--    Context     : numeric columns must not be negative or zero
--                  (products must have weight and dimensions > 0)
--    Expectation : no result
-- -----------------------------------------------------------------------------

SELECT COUNT(*) AS invalid_numeric
FROM workspace.bronze.products
WHERE product_weight_g  <= 0
   OR product_length_cm <= 0
   OR product_height_cm <= 0
   OR product_width_cm  <= 0
   OR product_photos_qty < 0;

-- Result: 4 rows ⚠️
-- Detail: 4 products with product_weight_g = 0 (category: cama_mesa_banho)
-- product_id:
--   81781c0fed9fe1ad6e8c81fca1e1cb08
--   8038040ee2a71048d4bdbbdc985b69ab
--   36ba42dd187055e1fbe943b2d11430ca
--   e673e90efa65a5409ff4196c038bb5af

-- Check if these products exist in order_items
SELECT COUNT(*) AS total_orders
FROM workspace.bronze.order_items
WHERE product_id IN (
    '81781c0fed9fe1ad6e8c81fca1e1cb08',
    '8038040ee2a71048d4bdbbdc985b69ab',
    '36ba42dd187055e1fbe943b2d11430ca',
    'e673e90efa65a5409ff4196c038bb5af'
);

-- Result: 8 → must be retained, 8 transactions reference these products
-- Fix: left as-is in silver layer, recorded as known issue


-- =============================================================================
-- SUMMARY
-- =============================================================================
-- | No | Check                          | Column                   | Result        |
-- |----|--------------------------------|--------------------------|---------------|
-- |  1 | Duplicate/NULL primary key     | product_id               | Clean ✓       |
-- |  2 | NULL category & description    | product_category_name,   | ⚠️ 610 rows   |
-- |    |                                | name_lenght, desc_lenght,|               |
-- |    |                                | photos_qty               |               |
-- |  2 | NULL dimensions/weight         | weight_g, length_cm,     | ⚠️ 2 rows     |
-- |    |                                | height_cm, width_cm      |               |
-- |  4 | Unwanted spaces                | product_category_name    | Clean ✓       |
-- |  5 | Zero/negative numeric values   | product_weight_g         | ⚠️ 4 rows     |
-- =============================================================================
-- CONCLUSION:
--   Table contains several issues that have been handled:
--   - product_category_name NULL (610 rows) → replaced with 'unknown' in silver
--   - NULL dimensions/weight (2 rows) → retained as NULL, must be kept
--     (product_id referenced by 17 transactions in order_items)
--   - product_weight_g = 0 (4 rows) → retained as-is, must be kept
--     (product_id referenced by 8 transactions in order_items)
--
-- KNOWN LIMITATION:
--   - Weight/dimension analysis will be inaccurate for 6 products
--     (2 NULL + 4 weight=0) totaling 25 referenced transactions.
--   - Category-based analysis will not be accurate for 610 products
--     labeled as 'unknown'.
-- =============================================================================

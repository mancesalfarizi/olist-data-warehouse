-- =============================================================================
-- DATA QUALITY CHECK: bronze.customers
-- Layer   : Bronze → Silver
-- Table   : bronze.customers
-- Author  : Salman
-- Date    : 2026-05-02
-- Purpose : Validate data before loading into silver layer
-- =============================================================================
-- Columns skipped from certain checks:
--   - customer_unique_id      : not a PK, duplicates allowed (1 unique customer
--                               can have many customer_id); NULL check still applied
--   - customer_zip_code_prefix: numeric, not relevant for space/encoding checks
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. PRIMARY KEY CHECK
--    Expectation : no result (no duplicates, no NULLs)
-- -----------------------------------------------------------------------------

SELECT
    customer_id,
    COUNT(*) AS total
FROM workspace.bronze.customers
GROUP BY customer_id
HAVING COUNT(*) > 1
    OR customer_id IS NULL;

-- Result: no result ✓


-- -----------------------------------------------------------------------------
-- 2. NULL CHECK: customer_unique_id
--    Context     : not a PK, but must not be NULL — used to identify unique
--                  customers across multiple orders
--    Expectation : 0
-- -----------------------------------------------------------------------------

SELECT COUNT(*) AS null_count
FROM workspace.bronze.customers
WHERE customer_unique_id IS NULL;

-- Result: 0 ✓


-- -----------------------------------------------------------------------------
-- 3. UNWANTED SPACES CHECK
--    Columns checked : customer_city, customer_state
--    Columns skipped : customer_unique_id, customer_zip_code_prefix (numeric)
--    Expectation     : no result
-- -----------------------------------------------------------------------------

-- 3a. customer_city
SELECT customer_city
FROM workspace.bronze.customers
WHERE customer_city != TRIM(customer_city);

-- Result: no result ✓

-- 3b. customer_state
SELECT customer_state
FROM workspace.bronze.customers
WHERE customer_state != TRIM(customer_state);

-- Result: no result ✓


-- -----------------------------------------------------------------------------
-- 4. ENCODING / CORRUPT CHARACTER CHECK
--    Column checked : customer_city
--    Context        : geolocation dataset was found to have corrupt encoding
--                     (e.g. 's├úo paulo') — checking if same issue exists here
--    Expectation    : no result
-- -----------------------------------------------------------------------------

SELECT DISTINCT customer_city
FROM workspace.bronze.customers
WHERE customer_city LIKE '%├%'
   OR customer_city LIKE '%└%'
   OR customer_city LIKE '%┬%';

-- Result: no result ✓
-- Note: city names like 'mogi-guacu', 'varre-sai' are valid (not anomalies)


-- -----------------------------------------------------------------------------
-- 5. ZIP CODE RANGE CHECK
--    Context     : valid Brazilian ZIP codes range from 1000 to 99999
--    Expectation : no result
-- -----------------------------------------------------------------------------

SELECT customer_zip_code_prefix
FROM workspace.bronze.customers
WHERE customer_zip_code_prefix < 1000
   OR customer_zip_code_prefix > 99999;

-- Result: no result ✓


-- -----------------------------------------------------------------------------
-- 6. STATE VALIDITY CHECK
--    Context     : customer_state must be 2 characters and uppercase (e.g. SP, RJ)
--    Expectation : no result
-- -----------------------------------------------------------------------------

SELECT DISTINCT customer_state
FROM workspace.bronze.customers
WHERE LENGTH(customer_state) != 2
   OR customer_state != UPPER(customer_state);

-- Result: no result ✓


-- =============================================================================
-- SUMMARY
-- =============================================================================
-- | No | Check                          | Column                   | Result   |
-- |----|--------------------------------|--------------------------|----------|
-- |  1 | Duplicate / NULL primary key   | customer_id              | Clean ✓  |
-- |  2 | NULL check                     | customer_unique_id       | Clean ✓  |
-- |  3 | Unwanted spaces                | customer_city            | Clean ✓  |
-- |  3 | Unwanted spaces                | customer_state           | Clean ✓  |
-- |  4 | Encoding / corrupt characters  | customer_city            | Clean ✓  |
-- |  5 | ZIP code range (1000–99999)    | customer_zip_code_prefix | Clean ✓  |
-- |  6 | State validity (2 char, upper) | customer_state           | Clean ✓  |
-- =============================================================================
-- CONCLUSION: No issues found. Table is ready to load into silver layer
--             without additional transformations (other than adding dwh_create_date).
-- =============================================================================

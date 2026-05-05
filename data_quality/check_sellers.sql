-- =============================================================================
-- DATA QUALITY CHECK: bronze.sellers
-- Layer   : Bronze → Silver
-- Table   : bronze.sellers
-- Author  : Salman
-- Date    : 2026-05-02
-- Purpose : Validate data before loading into silver layer
-- =============================================================================
-- Table context:
--   The sellers table contains information about sellers on the Olist platform.
--   Primary key is seller_id (one row per seller).
--   seller_city was found to have many format inconsistencies, but following
--   medallion architecture best practice, the column is retained in silver layer.
--   City enrichment will be done in gold layer via join to silver.geolocation
--   using seller_zip_code_prefix as the join key.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. PRIMARY KEY CHECK
--    Expectation : no result (no duplicates, no NULLs)
-- -----------------------------------------------------------------------------

SELECT
    seller_id,
    COUNT(*) AS cnt
FROM workspace.bronze.sellers
GROUP BY seller_id
HAVING COUNT(*) > 1
    OR seller_id IS NULL;

-- Result: no result ✓


-- -----------------------------------------------------------------------------
-- 2. NULL CHECK — all columns
--    Expectation : 0
-- -----------------------------------------------------------------------------

SELECT COUNT(*) AS null_count
FROM workspace.bronze.sellers
WHERE seller_id              IS NULL
   OR seller_zip_code_prefix IS NULL
   OR seller_city            IS NULL
   OR seller_state           IS NULL;

-- Result: 0 ✓


-- -----------------------------------------------------------------------------
-- 3. STATE VALIDITY CHECK
--    Context     : seller_state must be 2 characters and uppercase
--    Expectation : no result
-- -----------------------------------------------------------------------------

SELECT DISTINCT seller_state
FROM workspace.bronze.sellers
WHERE LENGTH(seller_state) != 2
   OR seller_state != UPPER(seller_state);

-- Result: no result ✓


-- -----------------------------------------------------------------------------
-- 4. UNWANTED SPACES CHECK
--    Columns checked : seller_city, seller_state
--    Expectation     : no result
-- -----------------------------------------------------------------------------

SELECT COUNT(*) AS space_count
FROM workspace.bronze.sellers
WHERE seller_city  != TRIM(seller_city)
   OR seller_state != TRIM(seller_state);

-- Result: no result ✓


-- -----------------------------------------------------------------------------
-- 5. CORRUPT ENCODING CHECK — seller_city
--    Context     : several city names found with corrupt UTF-8 encoding
--                  e.g. 'santa barbara d┬┤oeste'
--    Expectation : 0 (ideally)
-- -----------------------------------------------------------------------------

SELECT COUNT(*) AS corrupt_count
FROM workspace.bronze.sellers
WHERE seller_city RLIKE '[\\u251c\\u2514\\u252c]';

-- Result: 3 rows ⚠️
-- Fix: exclude rows with corrupt encoding in silver layer


-- -----------------------------------------------------------------------------
-- 6. CITY FORMAT INCONSISTENCY CHECK
--    Context     : many inconsistent city name formats found:
--                  - City contains state ('sao paulo sp', 'sbc/sp', 'sp / sp')
--                  - City contains extra info ('novo hamburgo, rio grande do sul')
--                  - City is just a state abbreviation ('sp', 'rj')
--                  - Typos ('cascavael', 'ribeirao pretp')
--                  - City contains slash ('ribeirao preto / sao paulo')
--    Expectation : recorded as known issue
-- -----------------------------------------------------------------------------

SELECT
    seller_zip_code_prefix,
    seller_city,
    seller_state
FROM workspace.bronze.sellers
WHERE seller_city LIKE '% sp'
   OR seller_city LIKE '%/sp'
   OR seller_city LIKE '% - sp'
   OR seller_city LIKE '%,%'
   OR seller_city LIKE '%/%'
   OR LOWER(TRIM(seller_city)) IN ('sp','rj','mg','pr','sc','rs','go','ba','df','ce')
ORDER BY seller_city;

-- Result: many rows with inconsistent format ⚠️ (known issue)
-- Architecture decision:
--   Following medallion architecture best practice, seller_city is retained
--   in silver layer as-is (after filtering corrupt encoding rows).
--   City enrichment will be done in gold layer via join to silver.geolocation
--   using seller_zip_code_prefix as the join key.


-- -----------------------------------------------------------------------------
-- 7. CITY INCONSISTENCY PER ZIP CODE CHECK
--    Context     : one ZIP code can have more than one city name
--                  due to inconsistent formats
-- -----------------------------------------------------------------------------

SELECT
    seller_zip_code_prefix,
    COUNT(DISTINCT LOWER(TRIM(seller_city))) AS distinct_city_count
FROM workspace.bronze.sellers
GROUP BY seller_zip_code_prefix
HAVING COUNT(DISTINCT LOWER(TRIM(seller_city))) > 1;

-- Result: several ZIP codes with inconsistent city names ⚠️ (known issue)
-- Example: zip 1207 → 'sao paulo' and 'sao paulo sp'
-- Fix: will be resolved in gold layer via join to silver.geolocation


-- =============================================================================
-- SUMMARY
-- =============================================================================
-- | No | Check                          | Column                   | Result        |
-- |----|--------------------------------|--------------------------|---------------|
-- |  1 | Duplicate/NULL primary key     | seller_id                | Clean ✓       |
-- |  2 | NULL check all columns         | all columns              | Clean ✓       |
-- |  3 | State validity (2 char, upper) | seller_state             | Clean ✓       |
-- |  4 | Unwanted spaces                | seller_city, seller_state| Clean ✓       |
-- |  5 | Corrupt encoding               | seller_city              | ⚠️ 3 rows     |
-- |  6 | City format inconsistency      | seller_city              | ⚠️ Known issue|
-- |  7 | City inconsistency per zip     | seller_city              | ⚠️ Known issue|
-- =============================================================================
-- CONCLUSION:
--   Table has issues in the seller_city column:
--   - 3 rows with corrupt encoding → excluded from silver layer
--   - Many inconsistent formats → retained as-is in silver layer
--
-- ARCHITECTURE DECISION:
--   Following medallion architecture best practice, seller_city is retained
--   in silver layer despite format inconsistencies. Silver is the cleaned
--   version of bronze, not a transformed version. City normalization will be
--   done in gold layer via join to silver.geolocation using
--   seller_zip_code_prefix as the join key.
-- =============================================================================

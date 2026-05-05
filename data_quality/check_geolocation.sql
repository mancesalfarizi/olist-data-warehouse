-- =============================================================================
-- DATA QUALITY CHECK: bronze.geolocation
-- Layer   : Bronze → Silver
-- Table   : bronze.geolocation
-- Author  : Salman
-- Date    : 2026-05-02
-- Purpose : Validate data before loading into silver layer
-- =============================================================================
-- Table context:
--   The geolocation table maps ZIP code prefixes to geographic coordinates.
--   One ZIP code prefix can have MANY rows (not an anomaly) because each
--   transaction records its own coordinates within the ZIP code area.
--   The silver layer will deduplicate to 1 row per ZIP code prefix.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. PRIMARY KEY CHECK
--    Context     : duplicates on zip_code_prefix are EXPECTED — one prefix
--                  covers a geographic area with many possible coordinates.
--                  Check only for NULLs.
--    Expectation : COUNT(*) > 1 = expected, zip_code_prefix IS NULL = no result
-- -----------------------------------------------------------------------------

SELECT
    geolocation_zip_code_prefix,
    COUNT(*) AS total
FROM workspace.bronze.geolocation
GROUP BY geolocation_zip_code_prefix
HAVING COUNT(*) > 1
    OR geolocation_zip_code_prefix IS NULL;

-- Result: many duplicates (expected), no NULLs ✓


-- -----------------------------------------------------------------------------
-- 2. NULL CHECK — all columns
--    Expectation : 0
-- -----------------------------------------------------------------------------

SELECT COUNT(*) AS null_count
FROM workspace.bronze.geolocation
WHERE geolocation_zip_code_prefix IS NULL
   OR geolocation_lat             IS NULL
   OR geolocation_lng             IS NULL
   OR geolocation_city            IS NULL
   OR geolocation_state           IS NULL;

-- Result: 0 ✓


-- -----------------------------------------------------------------------------
-- 3. CITY INCONSISTENCY CHECK
--    Context     : one ZIP code prefix can have different city names due to
--                  typos or corrupt encoding.
--                  e.g. 'santa cecilia', 'santa cecilia de umbuzeiro',
--                       'santa cec├¡lia' (corrupt encoding of 'santa cecília')
--    Expectation : results exist (known issue in Olist dataset)
-- -----------------------------------------------------------------------------

SELECT
    geolocation_zip_code_prefix,
    COUNT(DISTINCT LOWER(TRIM(geolocation_city))) AS distinct_city_count
FROM workspace.bronze.geolocation
GROUP BY geolocation_zip_code_prefix
HAVING COUNT(DISTINCT LOWER(TRIM(geolocation_city))) > 1;

-- Result: many ZIP codes with inconsistent city names ✓ (known issue)
-- Fix strategy: keep the most frequent city name per ZIP code prefix (mode)


-- -----------------------------------------------------------------------------
-- 4. CORRUPT ENCODING CHECK
--    Context     : Olist dataset contains corrupt UTF-8 characters,
--                  e.g. 's├úo paulo' (from 'São Paulo'),
--                       'santa cec├¡lia' (from 'santa cecília')
--    Expectation : results exist (known issue)
-- -----------------------------------------------------------------------------

SELECT DISTINCT geolocation_city
FROM workspace.bronze.geolocation
WHERE geolocation_city LIKE '%├%'
   OR geolocation_city LIKE '%└%'
   OR geolocation_city LIKE '%┬%';

-- Result: several cities with corrupt encoding ✓ (known issue)
-- Fix strategy: filter using character pattern detection


-- -----------------------------------------------------------------------------
-- 5. COORDINATE OUTLIER CHECK
--    Context     : some rows have coordinates outside Brazil's bounding box,
--                  or valid Brazilian coordinates assigned to wrong states.
--                  Brazil bounding box: lat -33.75 to 5.27, lng -73.99 to -34.79
--    Expectation : results exist (known issue)
-- -----------------------------------------------------------------------------

SELECT
    geolocation_zip_code_prefix,
    geolocation_lat,
    geolocation_lng,
    geolocation_city,
    geolocation_state
FROM workspace.bronze.geolocation
WHERE geolocation_lat NOT BETWEEN -33.75 AND 5.27
   OR geolocation_lng NOT BETWEEN -73.99 AND -34.79;

-- Result: several rows with coordinates outside Brazil ✓ (known issue)
-- Fix strategy: filter by Brazil bounding box
-- Note: coordinates assigned to wrong states (but still within bounding box)
--       are accepted risk in silver layer.


-- -----------------------------------------------------------------------------
-- 6. STATE VALIDITY CHECK
--    Context     : geolocation_state must be 2 characters and uppercase
--    Expectation : no result
-- -----------------------------------------------------------------------------

SELECT DISTINCT geolocation_state
FROM workspace.bronze.geolocation
WHERE LENGTH(geolocation_state) != 2
   OR geolocation_state != UPPER(geolocation_state);

-- Result: no result ✓


-- =============================================================================
-- SUMMARY
-- =============================================================================
-- | No | Check                          | Column                   | Result         |
-- |----|--------------------------------|--------------------------|----------------|
-- |  1 | Duplicate/NULL primary key     | zip_code_prefix          | Dup expected ✓ |
-- |  2 | NULL check all columns         | all columns              | Clean ✓        |
-- |  3 | City inconsistency             | geolocation_city         | Known issue ✓  |
-- |  4 | Corrupt encoding               | geolocation_city         | Known issue ✓  |
-- |  5 | Coordinate outliers            | lat, lng                 | Known issue ✓  |
-- |  6 | State validity (2 char, upper) | geolocation_state        | Clean ✓        |
-- =============================================================================
-- CONCLUSION:
--   Table contains several known issues (city inconsistency, corrupt encoding,
--   coordinate outliers) which are characteristics of the Olist dataset.
--   All issues are handled in the silver layer cleaning query.
--
-- KNOWN LIMITATION:
--   Some ZIP code prefixes have coordinate outliers that pass the bounding box
--   filter because they are still within Brazil but assigned to wrong states.
--   The median coordinate for those ZIP codes may not be 100% accurate.
--   Recommendation: add state-level boundary filter in gold layer if high-precision
--   spatial analysis is required (e.g. Haversine distance calculation).
-- =============================================================================

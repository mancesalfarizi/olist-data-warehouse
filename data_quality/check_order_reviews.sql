-- =============================================================================
-- DATA QUALITY CHECK: bronze.order_reviews
-- Layer   : Bronze → Silver
-- Table   : bronze.order_reviews
-- Author  : Salman
-- Date    : 2026-05-02
-- Purpose : Validate data before loading into silver layer
-- =============================================================================
-- Table context:
--   The order_reviews table contains customer reviews for received orders.
--   Ideally the primary key is review_id (one review per entry).
--   However, an anomaly was found where one review_id can be assigned to
--   more than one order_id — this is a bug in the source system.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. PRIMARY KEY CHECK
--    Context     : review_id should be unique, but an anomaly was found where
--                  one review_id is assigned to more than one order_id.
--    Expectation : no result (ideally)
-- -----------------------------------------------------------------------------

SELECT
    review_id,
    COUNT(*) AS cnt
FROM workspace.bronze.order_reviews
GROUP BY review_id
HAVING COUNT(*) > 1
    OR review_id IS NULL;

-- Result: many duplicates ⚠️
-- Distribution:
--   764 review_id appear in 2 different orders
--    25 review_id appear in 3 different orders
-- Total affected review_id: 789


-- -----------------------------------------------------------------------------
-- 2. NULL CHECK — all columns
--    Expectation : 0 for mandatory columns
--    Note        : review_comment_title and review_comment_message can be NULL
--                  since customers are not required to fill in comments
-- -----------------------------------------------------------------------------

SELECT COUNT(*) AS null_count
FROM workspace.bronze.order_reviews
WHERE review_id               IS NULL
   OR order_id                IS NULL
   OR review_score            IS NULL
   OR review_creation_date    IS NULL
   OR review_answer_timestamp IS NULL;

-- Result: 0 ✓


-- -----------------------------------------------------------------------------
-- 3. REVIEW SCORE VALIDITY CHECK
--    Context     : review_score must be between 1 and 5
--    Expectation : no result
-- -----------------------------------------------------------------------------

SELECT COUNT(*) AS invalid_score
FROM workspace.bronze.order_reviews
WHERE review_score NOT BETWEEN 1 AND 5;

-- Result: no result ✓


-- -----------------------------------------------------------------------------
-- 4. DUPLICATE DETAIL ANALYSIS
--    Context     : investigate whether columns other than order_id also differ
--                  for duplicate review_id entries
--    Expectation : all columns identical except order_id
-- -----------------------------------------------------------------------------

-- 4a. Check if all columns are identical except order_id
SELECT
    review_id,
    COUNT(DISTINCT review_score)            AS distinct_score,
    COUNT(DISTINCT review_comment_title)    AS distinct_title,
    COUNT(DISTINCT review_comment_message)  AS distinct_message,
    COUNT(DISTINCT review_creation_date)    AS distinct_creation,
    COUNT(DISTINCT review_answer_timestamp) AS distinct_answer
FROM workspace.bronze.order_reviews
GROUP BY review_id
HAVING COUNT(DISTINCT order_id) > 1
ORDER BY distinct_score DESC, distinct_message DESC;

-- Result:
--   distinct_score    = 1 for all → identical ✓
--   distinct_title    = 0 or 1    → identical (NULL counted as 0) ✓
--   distinct_message  = 0 or 1    → identical ✓
--   distinct_creation = 1 for all → identical ✓
--   distinct_answer   = 1 for all → identical ✓

-- 4b. Confirm: no reviews with different messages
SELECT
    r.review_id,
    r.order_id,
    r.review_score,
    r.review_comment_message,
    r.review_creation_date
FROM workspace.bronze.order_reviews r
WHERE r.review_id IN (
    SELECT review_id
    FROM workspace.bronze.order_reviews
    GROUP BY review_id
    HAVING COUNT(DISTINCT order_id) > 1
      AND COUNT(DISTINCT review_comment_message) > 1
)
ORDER BY r.review_id, r.order_id;

-- Result: no result ✓
-- Conclusion: all columns are identical except order_id — this is purely a bug
--             in the Olist system where one review was assigned to multiple orders


-- -----------------------------------------------------------------------------
-- 5. UNWANTED SPACES CHECK
--    Columns checked : review_comment_title, review_comment_message
--    Expectation     : no result
-- -----------------------------------------------------------------------------

SELECT COUNT(*) AS space_count
FROM workspace.bronze.order_reviews
WHERE (review_comment_title   IS NOT NULL AND review_comment_title   != TRIM(review_comment_title))
   OR (review_comment_message IS NOT NULL AND review_comment_message != TRIM(review_comment_message));

-- Result: no result ✓


-- -----------------------------------------------------------------------------
-- 6. DATE VALIDITY CHECK
--    Context     : review_creation_date and review_answer_timestamp must be
--                  within a reasonable date range
--    Expectation : no result
-- -----------------------------------------------------------------------------

SELECT COUNT(*) AS invalid_date
FROM workspace.bronze.order_reviews
WHERE review_creation_date    < '2000-01-01' OR review_creation_date    > '2030-01-01'
   OR review_answer_timestamp < '2000-01-01' OR review_answer_timestamp > '2030-01-01';

-- Result: no result ✓


-- =============================================================================
-- SUMMARY
-- =============================================================================
-- | No | Check                          | Column                   | Result        |
-- |----|--------------------------------|--------------------------|---------------|
-- |  1 | Duplicate/NULL primary key     | review_id                | ⚠️ 789 reviews|
-- |  2 | NULL check mandatory columns   | review_id, order_id,     | Clean ✓       |
-- |    |                                | review_score, dates      |               |
-- |  3 | Review score valid (1–5)       | review_score             | Clean ✓       |
-- |  4 | Duplicate detail analysis      | all columns              | Clean ✓       |
-- |    |                                | (identical except        |               |
-- |    |                                |  order_id)               |               |
-- |  5 | Unwanted spaces                | comment_title,           | Clean ✓       |
-- |    |                                | comment_message          |               |
-- |  6 | Date validity                  | review_creation_date,    | Clean ✓       |
-- |    |                                | review_answer_timestamp  |               |
-- =============================================================================
-- CONCLUSION:
--   A significant anomaly was found: 789 review_id entries are assigned to more
--   than one order_id. Investigation shows all other columns are identical —
--   this is a source system bug in Olist, not a user input error.
--   Fix: deduplicate using ROW_NUMBER() in silver layer, keep one row per
--   review_id. Primary key in silver layer is review_id (not composite).
--
-- KNOWN LIMITATION:
--   Since deduplication is done arbitrarily (ORDER BY order_id), the selected
--   order_id for duplicate reviews may not be the "correct" one.
--   Impact: analysis joining reviews with orders may be slightly inaccurate
--   for those 789 reviews.
-- =============================================================================

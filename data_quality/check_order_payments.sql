-- =============================================================================
-- DATA QUALITY CHECK: bronze.order_payments
-- Layer   : Bronze → Silver
-- Table   : bronze.order_payments
-- Author  : Salman
-- Date    : 2026-05-02
-- Purpose : Validate data before loading into silver layer
-- =============================================================================
-- Table context:
--   The order_payments table contains payment details for each order.
--   One order can be paid with more than one payment method (split payment),
--   indicated by the payment_sequential column.
--   Primary key is a composite key: (order_id, payment_sequential).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. PRIMARY KEY CHECK (COMPOSITE)
--    Context     : PK is the combination of order_id + payment_sequential.
--                  One order_id can appear more than once because one order
--                  can be paid with multiple methods — this is EXPECTED.
--    Expectation : no result
-- -----------------------------------------------------------------------------

SELECT
    order_id,
    payment_sequential,
    COUNT(*) AS cnt
FROM workspace.bronze.order_payments
GROUP BY order_id, payment_sequential
HAVING COUNT(*) > 1
    OR order_id IS NULL
    OR payment_sequential IS NULL;

-- Result: no result ✓


-- -----------------------------------------------------------------------------
-- 2. NULL CHECK — all columns
--    Expectation : 0
-- -----------------------------------------------------------------------------

SELECT COUNT(*) AS null_count
FROM workspace.bronze.order_payments
WHERE order_id               IS NULL
   OR payment_sequential     IS NULL
   OR payment_type           IS NULL
   OR payment_installments   IS NULL
   OR payment_value          IS NULL;

-- Result: 0 ✓


-- -----------------------------------------------------------------------------
-- 3. UNWANTED SPACES CHECK
--    Column checked : payment_type
--    Expectation    : no result
-- -----------------------------------------------------------------------------

SELECT COUNT(*) AS space_count
FROM workspace.bronze.order_payments
WHERE payment_type != TRIM(payment_type);

-- Result: no result ✓


-- -----------------------------------------------------------------------------
-- 4. PAYMENT TYPE VALID VALUES CHECK
--    Context     : payment_type must only contain known valid values
--    Expectation : only credit_card, debit_card, voucher, boleto, not_defined
-- -----------------------------------------------------------------------------

SELECT DISTINCT payment_type
FROM workspace.bronze.order_payments;

-- Result: credit_card, debit_card, voucher, boleto, not_defined ✓
-- Note: 'not_defined' is a known issue in the Olist dataset (3 rows)
--       recorded as accepted anomaly


-- -----------------------------------------------------------------------------
-- 5. PAYMENT VALUE CHECK
--    Context     : payment_value must not be negative.
--                  payment_value = 0 is allowed (100% voucher discount).
--    Expectation : no result for negative values
-- -----------------------------------------------------------------------------

-- 5a. Check for negative values
SELECT COUNT(*) AS invalid_count
FROM workspace.bronze.order_payments
WHERE payment_value < 0;

-- Result: 0 ✓

-- 5b. Log zero payment_value count
SELECT COUNT(*) AS zero_value_count
FROM workspace.bronze.order_payments
WHERE payment_value = 0;

-- Result: 9 rows
-- Note: acceptable — occurs on voucher or not_defined payment types


-- -----------------------------------------------------------------------------
-- 6. PAYMENT INSTALLMENTS CHECK
--    Context     : payment_installments must not be negative or zero
--    Expectation : no result
-- -----------------------------------------------------------------------------

SELECT COUNT(*) AS invalid_count
FROM workspace.bronze.order_payments
WHERE payment_installments <= 0;

-- Result: 2 rows ⚠️
-- Detail:
--   744bade1fcf9ff3f31d860ace076d422  2  credit_card  0  58.69
--   1a57108394169c0b47d8f876acc9ba2d  2  credit_card  0  129.94
--
-- Analysis: payment_type = credit_card with installments = 0 is a data entry
--           error — credit card must have at least 1 installment.
--           payment_value is not zero so the transaction is valid.
-- Fix: in silver layer, installments = 0 on credit_card is treated as 1.


-- -----------------------------------------------------------------------------
-- 7. NOT DEFINED PAYMENT TYPE CHECK
--    Context     : payment_type = 'not_defined' is an anomaly in the Olist dataset
--    Expectation : log count
-- -----------------------------------------------------------------------------

SELECT COUNT(*) AS not_defined_count
FROM workspace.bronze.order_payments
WHERE payment_type = 'not_defined';

-- Result: 3 rows
-- Note: known issue in Olist dataset, recorded as accepted anomaly


-- -----------------------------------------------------------------------------
-- 8. PAYMENT SEQUENTIAL CONTINUITY CHECK
--    Context     : payment_sequential should always start from 1 for each
--                  order_id. If min(payment_sequential) > 1, it means some
--                  payment rows are missing from the source data.
--    Expectation : no result (ideally)
-- -----------------------------------------------------------------------------

SELECT order_id, MIN(payment_sequential) AS min_seq
FROM workspace.bronze.order_payments
GROUP BY order_id
HAVING MIN(payment_sequential) != 1;

-- Result: 80 rows ⚠️
-- Analysis: 80 orders have payment_sequential not starting from 1,
--           meaning payment_sequential = 1 for those orders is missing.
-- Impact:
--   - Total payment per order will be understated for these 80 orders
--   - Join to orders table is still safe since order_id still exists
--   - Payment method analysis is slightly biased (80 methods not recorded)
-- Fix: cannot be fixed — source data is incomplete.
--      Recorded as known issue. Impact is very small (80 out of hundreds
--      of thousands of orders).


-- =============================================================================
-- SUMMARY
-- =============================================================================
-- | No | Check                            | Column                   | Result        |
-- |----|----------------------------------|--------------------------|---------------|
-- |  1 | Duplicate/NULL composite key     | order_id,                | Clean ✓       |
-- |    |                                  | payment_sequential       |               |
-- |  2 | NULL check all columns           | all columns              | Clean ✓       |
-- |  3 | Unwanted spaces                  | payment_type             | Clean ✓       |
-- |  4 | Payment type valid values        | payment_type             | Clean ✓       |
-- |  5 | Negative payment value           | payment_value            | Clean ✓       |
-- |  6 | Payment value = 0                | payment_value            | ⚠️ 9 rows     |
-- |  7 | Payment installments <= 0        | payment_installments     | ⚠️ 2 rows     |
-- |  8 | Not defined payment type         | payment_type             | ⚠️ 3 rows     |
-- |  9 | Sequential not starting from 1   | payment_sequential       | ⚠️ 80 rows    |
-- =============================================================================
-- CONCLUSION:
--   Table contains several minor issues that have been handled:
--   - payment_installments = 0 on credit_card → fixed to 1 in silver layer
--   - payment_value = 0 → acceptable (voucher/not_defined), not changed
--   - payment_type = not_defined → known Olist dataset issue, not changed
--
-- KNOWN LIMITATION:
--   80 orders have payment_sequential not starting from 1, meaning some payment
--   rows are missing from source data. Total payment value for those orders will
--   be understated. Cannot be fixed. Impact is very small on the overall dataset.
-- =============================================================================

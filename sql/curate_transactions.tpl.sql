-- Move & dedupe transactions from landing -> curated (anti-join + landing dedupe)

BEGIN TRANSACTION;

INSERT INTO `{{CURATED_PROJECT}}.{{CURATED_DATASET}}.transactions`
  (transaction_id, customer_id, transaction_date, amount, currency, product, load_tsp, file_name, rows_diff_hash)
WITH
  src AS (
    SELECT
      transaction_id,
      customer_id,
      transaction_date,
      amount,
      currency,
      product,
      load_tsp,
      source_file AS file_name
    FROM `{{LANDING_PROJECT}}.{{LANDING_DATASET}}.transactions`
  ),
  enriched AS (
    SELECT
      SAFE_CAST(transaction_id AS STRING)       AS transaction_id,
      SAFE_CAST(customer_id AS STRING)          AS customer_id,
      SAFE_CAST(transaction_date AS TIMESTAMP)  AS transaction_date,
      SAFE_CAST(amount AS NUMERIC)              AS amount,
      TRIM(currency)                            AS currency,
      TRIM(product)                             AS product,
      load_tsp,
      file_name,
      -- hash from business columns only
      TO_BASE64(SHA256(ARRAY_TO_STRING([
        COALESCE(SAFE_CAST(transaction_id AS STRING), ''),
        COALESCE(SAFE_CAST(customer_id AS STRING), ''),
        COALESCE(CAST(SAFE_CAST(transaction_date AS TIMESTAMP) AS STRING), ''),
        COALESCE(CAST(SAFE_CAST(amount AS NUMERIC) AS STRING), ''),
        COALESCE(TRIM(currency), ''),
        COALESCE(TRIM(product), '')
      ], '|'))) AS rows_diff_hash
    FROM src
  ),
  landing_dedup AS (
    SELECT *
    FROM enriched
    QUALIFY ROW_NUMBER() OVER (PARTITION BY rows_diff_hash ORDER BY load_tsp DESC) = 1
  ),
  anti_dupes AS (
    SELECT d.*
    FROM landing_dedup d
    LEFT JOIN `{{CURATED_PROJECT}}.{{CURATED_DATASET}}.transactions` c
      ON c.rows_diff_hash = d.rows_diff_hash
    WHERE c.rows_diff_hash IS NULL
  )
SELECT
  transaction_id, customer_id, transaction_date, amount, currency, product,
  load_tsp, file_name, rows_diff_hash
FROM anti_dupes;

-- Optional cleanup (disabled to avoid streaming buffer errors):
-- DELETE FROM `{{LANDING_PROJECT}}.{{LANDING_DATASET}}.transactions`
-- WHERE source_file IN (SELECT DISTINCT file_name FROM anti_dupes);

COMMIT TRANSACTION;

-- Move & dedupe customers from landing -> curated (anti-join + landing dedupe)

BEGIN TRANSACTION;

INSERT INTO `{{CURATED_PROJECT}}.{{CURATED_DATASET}}.customers`
  (customer_id, first_name, last_name, email, signup_date, country, load_tsp, file_name, rows_diff_hash)
WITH
  src AS (
    SELECT
      customer_id,
      first_name,
      last_name,
      email,
      signup_date,
      country,
      load_tsp,
      source_file AS file_name
    FROM `{{LANDING_PROJECT}}.{{LANDING_DATASET}}.customers`
  ),
  enriched AS (
    SELECT
      SAFE_CAST(customer_id AS STRING) AS customer_id,
      TRIM(first_name)                 AS first_name,
      TRIM(last_name)                  AS last_name,
      LOWER(email)                     AS email,
      SAFE_CAST(signup_date AS DATE)   AS signup_date,
      TRIM(country)                    AS country,
      load_tsp,
      file_name,
      -- hash from business columns only
      TO_BASE64(SHA256(ARRAY_TO_STRING([
        COALESCE(SAFE_CAST(customer_id AS STRING), ''),
        COALESCE(TRIM(first_name), ''),
        COALESCE(TRIM(last_name), ''),
        COALESCE(LOWER(email), ''),
        COALESCE(CAST(SAFE_CAST(signup_date AS DATE) AS STRING), ''),
        COALESCE(TRIM(country), '')
      ], '|'))) AS rows_diff_hash
    FROM src
  ),
  landing_dedup AS (
    -- keep only 1 row per hash within *this* landing scan (latest load_tsp wins)
    SELECT *
    FROM enriched
    QUALIFY ROW_NUMBER() OVER (PARTITION BY rows_diff_hash ORDER BY load_tsp DESC) = 1
  ),
  anti_dupes AS (
    SELECT d.*
    FROM landing_dedup d
    LEFT JOIN `{{CURATED_PROJECT}}.{{CURATED_DATASET}}.customers` c
      ON c.rows_diff_hash = d.rows_diff_hash
    WHERE c.rows_diff_hash IS NULL
  )
SELECT
  customer_id, first_name, last_name, email, signup_date, country,
  load_tsp, file_name, rows_diff_hash
FROM anti_dupes;

-- Optional cleanup (disabled to avoid streaming buffer errors):
-- DELETE FROM `{{LANDING_PROJECT}}.{{LANDING_DATASET}}.customers`
-- WHERE source_file IN (SELECT DISTINCT file_name FROM anti_dupes);

COMMIT TRANSACTION;

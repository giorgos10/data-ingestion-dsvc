CREATE OR REPLACE VIEW `{{CURATED_PROJECT}}.{{ANALYTICS_DATASET}}.customer_monthly_spend` AS
WITH txn AS (
  SELECT
    t.customer_id,
    FORMAT_DATE('%Y-%m', DATE(t.transaction_date)) AS month,
    t.amount
  FROM `{{CURATED_PROJECT}}.{{CURATED_DATASET}}.transactions` t
)
SELECT
  customer_id,
  month,
  SUM(amount)                 AS total_monthly_spend,
  AVG(NULLIF(amount, 0))      AS avg_txn_amount_in_month,
  COUNTIF(amount IS NOT NULL) AS txn_count_in_month
FROM txn
GROUP BY customer_id, month;

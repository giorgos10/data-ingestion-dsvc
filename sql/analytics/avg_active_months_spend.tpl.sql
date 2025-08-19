CREATE OR REPLACE VIEW `{{CURATED_PROJECT}}.{{ANALYTICS_DATASET}}.customer_active_avg_monthly_spend_alt` AS
WITH monthly AS (
  SELECT
    customer_id,
    DATE_TRUNC(TIMESTAMP_TRUNC(transaction_date, DAY), MONTH) AS month,
    SUM(amount) AS total_monthly_spend
  FROM `{{CURATED_PROJECT}}.{{CURATED_DATASET}}.transactions`
  GROUP BY customer_id, month
),
span AS (
  SELECT
    customer_id,
    SUM(total_monthly_spend)                             AS total_spend,
    COUNT(*)                                             AS active_months
  FROM monthly
  GROUP BY customer_id
)
SELECT
  customer_id,
  total_spend / NULLIF(active_months, 0) AS avg_monthly_spend_active_months
FROM span;

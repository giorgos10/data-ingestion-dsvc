-- View of each customer’s average monthly spend, averaged only across the months where they made a transaction
CREATE OR REPLACE VIEW `{{CURATED_PROJECT}}.{{ANALYTICS_DATASET}}.customer_avg_monthly_spend` AS
WITH monthly AS (
  SELECT
    customer_id,
    DATE_TRUNC(TIMESTAMP_TRUNC(transaction_date, DAY), MONTH) AS month,
    SUM(amount) AS total_monthly_spend
  FROM `{{CURATED_PROJECT}}.{{CURATED_DATASET}}.transactions`
  GROUP BY customer_id, month
)
SELECT
  customer_id,
  AVG(total_monthly_spend) AS avg_monthly_spend_active_months
FROM monthly
GROUP BY customer_id;

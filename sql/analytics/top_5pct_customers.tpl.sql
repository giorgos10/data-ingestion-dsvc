-- Ranked list of the top-spending customers (top 5% by total lifetime spend)
CREATE OR REPLACE VIEW `{{CURATED_PROJECT}}.{{ANALYTICS_DATASET}}.top_5pct_customers` AS
SELECT
  customer_id,
  lifetime_value
FROM `{{CURATED_PROJECT}}.{{ANALYTICS_DATASET}}.customer_ltv`
WHERE pct_rank >= 0.95
ORDER BY lifetime_value DESC;

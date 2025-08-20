-- Customers lifetime value (LTV) leaderboard - flags the top ~5%
CREATE OR REPLACE VIEW `{{CURATED_PROJECT}}.{{ANALYTICS_DATASET}}.customer_ltv` AS
WITH ltv AS (
  SELECT
    t.customer_id,
    SUM(t.amount) AS lifetime_value
  FROM `{{CURATED_PROJECT}}.{{CURATED_DATASET}}.transactions` t
  GROUP BY customer_id
),
ranked AS (
  SELECT
    customer_id,
    lifetime_value,
    PERCENT_RANK() OVER (ORDER BY lifetime_value) AS pct_rank
  FROM ltv
)
SELECT
  customer_id,
  lifetime_value,
  pct_rank,
  (pct_rank >= 0.95) AS is_top_5_pct
FROM ranked;

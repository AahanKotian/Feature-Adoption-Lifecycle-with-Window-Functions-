-- ============================================================
-- STEP 5: Assign Adoption Tier Per User Per Feature
-- ============================================================
-- Goal: Classify every (user, feature) pair into one of four
-- adoption tiers based on cumulative usage and engagement depth.
-- Also show their current usage trend using LAG.
--
-- Tiers:
--   first_use   → fewer than 3 total uses
--   occasional  → 3–9 uses, or < 3 active weeks
--   regular     → 10–24 uses across ≥ 3 active weeks
--   power_user  → 25+ uses across ≥ 5 active weeks
--
-- This is the portfolio centerpiece query.
-- ============================================================

WITH all_uses AS (
  SELECT
    user_id,
    feature,
    DATE(event_time)                                AS event_date,
    DATE(event_time, 'weekday 0', '-6 days')        AS week_start,
    event_time
  FROM
    feature_events
),

-- Per-user, per-feature lifetime stats
user_feature_stats AS (
  SELECT
    user_id,
    feature,
    COUNT(*)                                        AS total_uses,
    COUNT(DISTINCT event_date)                      AS active_days,
    COUNT(DISTINCT week_start)                      AS active_weeks,
    MIN(event_date)                                 AS first_use_date,
    MAX(event_date)                                 AS last_use_date,
    CAST(
      JULIANDAY(MAX(event_date)) -
      JULIANDAY(MIN(event_date))
      AS INTEGER
    )                                               AS engagement_span_days
  FROM
    all_uses
  GROUP BY
    user_id, feature
),

-- Tier assignment
tier_assignment AS (
  SELECT
    user_id,
    feature,
    total_uses,
    active_days,
    active_weeks,
    first_use_date,
    last_use_date,
    engagement_span_days,
    CASE
      WHEN total_uses < 3
        THEN 'first_use'
      WHEN total_uses BETWEEN 3 AND 9
        OR active_weeks < 3
        THEN 'occasional'
      WHEN total_uses BETWEEN 10 AND 24
        AND active_weeks >= 3
        THEN 'regular'
      WHEN total_uses >= 25
        AND active_weeks >= 5
        THEN 'power_user'
      -- Edge: high uses but low week spread (binge user)
      ELSE 'occasional'
    END                                             AS adoption_tier,
    -- Numeric tier for ranking/ordering
    CASE
      WHEN total_uses < 3                           THEN 1
      WHEN total_uses BETWEEN 3 AND 9               THEN 2
      WHEN total_uses BETWEEN 10 AND 24
           AND active_weeks >= 3                    THEN 3
      WHEN total_uses >= 25 AND active_weeks >= 5   THEN 4
      ELSE 2
    END                                             AS tier_rank
  FROM
    user_feature_stats
),

-- Most recent two weeks of activity for trend
recent_weekly AS (
  SELECT
    user_id,
    feature,
    week_start,
    COUNT(*)                                        AS uses_this_week,
    ROW_NUMBER() OVER (
      PARTITION BY user_id, feature
      ORDER BY week_start DESC
    )                                               AS recency_rank
  FROM
    all_uses
  GROUP BY
    user_id, feature, week_start
),

latest_week AS (
  SELECT user_id, feature, uses_this_week AS this_week_uses
  FROM recent_weekly WHERE recency_rank = 1
),

prev_week AS (
  SELECT user_id, feature, uses_this_week AS prev_week_uses
  FROM recent_weekly WHERE recency_rank = 2
)

SELECT
  ta.user_id,
  ta.feature,
  ta.total_uses,
  ta.active_days,
  ta.active_weeks,
  ta.first_use_date,
  ta.last_use_date,
  ta.engagement_span_days,
  ta.adoption_tier,

  -- LAG-based trend using the two most recent weeks
  COALESCE(lw.this_week_uses, 0)                   AS this_week_uses,
  COALESCE(pw.prev_week_uses, 0)                   AS prev_week_uses,
  COALESCE(lw.this_week_uses, 0)
    - COALESCE(pw.prev_week_uses, 0)               AS wow_delta,

  CASE
    WHEN pw.prev_week_uses IS NULL
      THEN 'new_this_week'
    WHEN COALESCE(lw.this_week_uses, 0)
       > COALESCE(pw.prev_week_uses, 0)
      THEN 'increasing'
    WHEN COALESCE(lw.this_week_uses, 0)
       < COALESCE(pw.prev_week_uses, 0)
      THEN 'decreasing'
    ELSE 'flat'
  END                                               AS usage_trend,

  -- Rank users within each feature by total uses
  DENSE_RANK() OVER (
    PARTITION BY ta.feature
    ORDER BY ta.total_uses DESC
  )                                                 AS usage_rank_in_feature,

  -- Percentile of this user's usage within the feature
  ROUND(
    100.0 * PERCENT_RANK() OVER (
      PARTITION BY ta.feature
      ORDER BY ta.total_uses
    ), 1
  )                                                 AS usage_percentile

FROM
  tier_assignment   ta
  LEFT JOIN latest_week lw
    ON ta.user_id = lw.user_id AND ta.feature = lw.feature
  LEFT JOIN prev_week pw
    ON ta.user_id = pw.user_id AND ta.feature = pw.feature
ORDER BY
  ta.feature,
  ta.tier_rank DESC,
  ta.total_uses DESC

-- ---------------------------------------------------------------
-- PERCENT_RANK() returns a value between 0 and 1.
-- Multiply by 100 to get a 0–100 percentile score.
-- A power_user who ranks in the 95th percentile is a top-tier
-- user even among power users.
-- ---------------------------------------------------------------

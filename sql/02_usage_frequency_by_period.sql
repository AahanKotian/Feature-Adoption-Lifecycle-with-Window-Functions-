-- ============================================================
-- STEP 2: Weekly Usage Counts Per User Per Feature
-- ============================================================
-- Goal: Bucket all events into calendar weeks and count how
-- many times each user used each feature per week.
--
-- This weekly grain is the input for LAG/LEAD comparisons
-- and moving averages in later steps. Daily grain is too
-- noisy; monthly grain is too coarse for lifecycle tracking.
--
-- Key technique: DATE truncation to week start, then GROUP BY
-- user + feature + week to get a clean time series.
-- ============================================================

WITH weekly_events AS (
  SELECT
    user_id,
    feature,
    -- Truncate to Monday of each week (SQLite uses strftime)
    -- For BigQuery: DATE_TRUNC(DATE(event_time), WEEK(MONDAY))
    -- For PostgreSQL: DATE_TRUNC('week', event_time::date)
    DATE(event_time, 'weekday 0', '-6 days')        AS week_start,
    COUNT(*)                                        AS uses_this_week
  FROM
    feature_events
  GROUP BY
    user_id,
    feature,
    week_start
),

-- Fill in zero-use weeks so LAG comparisons don't skip gaps.
-- We generate a spine of all (user, feature, week) combinations
-- that exist, then left join actual usage.
user_feature_weeks AS (
  SELECT DISTINCT
    user_id,
    feature,
    week_start
  FROM
    weekly_events
),

-- Join back to get 0 for weeks with no usage
-- (only covers weeks where user had SOME activity in the dataset)
filled_weeks AS (
  SELECT
    ufw.user_id,
    ufw.feature,
    ufw.week_start,
    COALESCE(we.uses_this_week, 0)                  AS uses_this_week
  FROM
    user_feature_weeks  ufw
    LEFT JOIN weekly_events we
      ON ufw.user_id    = we.user_id
      AND ufw.feature   = we.feature
      AND ufw.week_start = we.week_start
)

SELECT
  user_id,
  feature,
  week_start,
  uses_this_week,
  -- Cumulative uses as of this week (running total)
  SUM(uses_this_week) OVER (
    PARTITION BY user_id, feature
    ORDER BY week_start
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  )                                                 AS cumulative_uses_to_date,
  -- Week number in this user's engagement history (1 = first week)
  ROW_NUMBER() OVER (
    PARTITION BY user_id, feature
    ORDER BY week_start
  )                                                 AS week_number
FROM
  filled_weeks
ORDER BY
  user_id,
  feature,
  week_start

-- ---------------------------------------------------------------
-- Why fill zero-use weeks?
-- Without them, LAG() would compare week 4 to week 2 if the
-- user was inactive in week 3, making the delta misleading.
-- Filled zeros make the time series continuous.
-- ---------------------------------------------------------------

-- ============================================================
-- STEP 4: 7-Day Rolling Average Usage Per User Per Feature
-- ============================================================
-- Goal: Smooth out single-day usage spikes with a 7-day
-- moving average. This reveals true engagement trends that
-- raw daily counts obscure.
--
-- Example: A user who uses a feature 10 times on Monday and
-- 0 times the rest of the week looks like a "power user" on
-- Monday but "inactive" Tuesday–Sunday. The 7-day rolling
-- average shows their true daily engagement rate (~1.4/day).
--
-- Key technique: AVG() OVER() with a ROWS BETWEEN frame
-- that looks back 6 days (current day + 6 prior = 7-day window).
-- ============================================================

WITH daily_usage AS (
  SELECT
    user_id,
    feature,
    DATE(event_time)                                AS event_date,
    COUNT(*)                                        AS daily_uses
  FROM
    feature_events
  GROUP BY
    user_id, feature, event_date
)

SELECT
  user_id,
  feature,
  event_date,
  daily_uses,

  -- ── 7-day rolling average ────────────────────────────────
  ROUND(
    AVG(CAST(daily_uses AS FLOAT)) OVER (
      PARTITION BY user_id, feature
      ORDER BY event_date
      ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2
  )                                                 AS rolling_7day_avg,

  -- ── 3-day rolling average (more reactive) ────────────────
  ROUND(
    AVG(CAST(daily_uses AS FLOAT)) OVER (
      PARTITION BY user_id, feature
      ORDER BY event_date
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 2
  )                                                 AS rolling_3day_avg,

  -- ── 14-day rolling average (smoother trend) ──────────────
  ROUND(
    AVG(CAST(daily_uses AS FLOAT)) OVER (
      PARTITION BY user_id, feature
      ORDER BY event_date
      ROWS BETWEEN 13 PRECEDING AND CURRENT ROW
    ), 2
  )                                                 AS rolling_14day_avg,

  -- ── Cumulative uses to date ───────────────────────────────
  SUM(daily_uses) OVER (
    PARTITION BY user_id, feature
    ORDER BY event_date
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  )                                                 AS cumulative_uses,

  -- ── Flag: is today above the 7-day average? ──────────────
  CASE
    WHEN daily_uses >= AVG(CAST(daily_uses AS FLOAT)) OVER (
           PARTITION BY user_id, feature
           ORDER BY event_date
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
         )
    THEN 1 ELSE 0
  END                                               AS above_rolling_avg,

  -- ── Rank this day vs all days for this user+feature ──────
  RANK() OVER (
    PARTITION BY user_id, feature
    ORDER BY daily_uses DESC
  )                                                 AS daily_use_rank

FROM
  daily_usage
ORDER BY
  user_id, feature, event_date

-- ---------------------------------------------------------------
-- ROWS BETWEEN 6 PRECEDING AND CURRENT ROW:
--   This is a "rows-based" frame — it always looks back exactly
--   6 rows in the result set, regardless of date gaps.
--   For true calendar-based windows (filling date gaps first),
--   you'd need to generate a date spine and join before windowing.
--
-- For Mode/PostgreSQL, replace JULIANDAY math with:
--   event_date - INTERVAL '6 days'
-- ---------------------------------------------------------------

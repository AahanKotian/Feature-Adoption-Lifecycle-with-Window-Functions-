-- ============================================================
-- STEP 3: Running Totals + Week-over-Week Delta Using LAG
-- ============================================================
-- Goal: For each user × feature × week, show:
--   - How many times they've used the feature cumulatively
--   - How this week's usage compares to last week's (LAG)
--   - Whether they're trending up, down, or flat
--
-- Key techniques:
--   SUM() OVER() with UNBOUNDED PRECEDING → running total
--   LAG(col, 1) OVER() → look back one row (previous week)
--   LEAD(col, 1) OVER() → peek forward one row (next week)
-- ============================================================

WITH weekly_usage AS (
  -- Reproduces Step 2 inline for standalone execution
  SELECT
    user_id,
    feature,
    DATE(event_time, 'weekday 0', '-6 days')        AS week_start,
    COUNT(*)                                        AS uses_this_week
  FROM
    feature_events
  GROUP BY
    user_id, feature, week_start
)

SELECT
  user_id,
  feature,
  week_start,
  uses_this_week,

  -- ── Running total ────────────────────────────────────────
  SUM(uses_this_week) OVER (
    PARTITION BY user_id, feature
    ORDER BY week_start
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  )                                                 AS cumulative_uses,

  -- ── LAG: previous week's usage ───────────────────────────
  LAG(uses_this_week, 1, 0) OVER (
    PARTITION BY user_id, feature
    ORDER BY week_start
  )                                                 AS prev_week_uses,
  -- The third argument to LAG (0) is the default value returned
  -- for the first row, where there's no previous week.

  -- ── LEAD: next week's usage (forward-looking) ────────────
  LEAD(uses_this_week, 1, 0) OVER (
    PARTITION BY user_id, feature
    ORDER BY week_start
  )                                                 AS next_week_uses,

  -- ── Week-over-week delta ──────────────────────────────────
  uses_this_week - LAG(uses_this_week, 1, 0) OVER (
    PARTITION BY user_id, feature
    ORDER BY week_start
  )                                                 AS wow_delta,

  -- ── Trend classification ──────────────────────────────────
  CASE
    WHEN LAG(uses_this_week, 1) OVER (
           PARTITION BY user_id, feature ORDER BY week_start
         ) IS NULL
         THEN 'new'                                -- first week ever
    WHEN uses_this_week > LAG(uses_this_week, 1, 0) OVER (
           PARTITION BY user_id, feature ORDER BY week_start
         )
         THEN 'increasing'
    WHEN uses_this_week < LAG(uses_this_week, 1, 0) OVER (
           PARTITION BY user_id, feature ORDER BY week_start
         )
         THEN 'decreasing'
    ELSE 'flat'
  END                                               AS usage_trend,

  -- ── Look-back 2 weeks: is user consistently growing? ─────
  CASE
    WHEN uses_this_week
       > LAG(uses_this_week, 1, 0) OVER (
           PARTITION BY user_id, feature ORDER BY week_start)
    AND LAG(uses_this_week, 1, 0) OVER (
           PARTITION BY user_id, feature ORDER BY week_start)
       > LAG(uses_this_week, 2, 0) OVER (
           PARTITION BY user_id, feature ORDER BY week_start)
    THEN 1 ELSE 0
  END                                               AS two_week_growth_streak

FROM
  weekly_usage
ORDER BY
  user_id, feature, week_start

-- ---------------------------------------------------------------
-- LAG(col, 1, 0): the third argument (default 0) means the
-- first row won't return NULL — it returns 0 instead.
-- This makes wow_delta meaningful on the first row (delta = uses).
--
-- LEAD is shown here for reference — use it when you want to
-- flag users "at risk" of dropping off based on forward behavior.
-- ---------------------------------------------------------------

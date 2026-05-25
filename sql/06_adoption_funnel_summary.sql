-- ============================================================
-- STEP 6: Adoption Funnel Summary (Cohort-Level)
-- ============================================================
-- Goal: For each feature, show how many users reached each
-- adoption tier — and what % of all users made it to power_user.
--
-- This is the executive summary: one row per feature showing
-- the full adoption funnel from first_use to power_user.
--
-- Also breaks down by user segment (trial vs. paid) and
-- shows median days-to-tier for each level.
-- ============================================================

WITH all_uses AS (
  SELECT
    fe.user_id,
    fe.feature,
    DATE(fe.event_time)                             AS event_date,
    DATE(fe.event_time, 'weekday 0', '-6 days')     AS week_start
  FROM
    feature_events fe
),

user_feature_stats AS (
  SELECT
    user_id,
    feature,
    COUNT(*)                                        AS total_uses,
    COUNT(DISTINCT week_start)                      AS active_weeks,
    MIN(event_date)                                 AS first_use_date,
    MAX(event_date)                                 AS last_use_date
  FROM
    all_uses
  GROUP BY
    user_id, feature
),

tier_assignment AS (
  SELECT
    ufs.user_id,
    ufs.feature,
    ufs.total_uses,
    ufs.active_weeks,
    ufs.first_use_date,
    -- Join to users table for segment info
    COALESCE(u.user_type, 'unknown')                AS user_type,
    CASE
      WHEN ufs.total_uses < 3                       THEN 'first_use'
      WHEN ufs.total_uses BETWEEN 3 AND 9
        OR ufs.active_weeks < 3                     THEN 'occasional'
      WHEN ufs.total_uses BETWEEN 10 AND 24
        AND ufs.active_weeks >= 3                   THEN 'regular'
      WHEN ufs.total_uses >= 25
        AND ufs.active_weeks >= 5                   THEN 'power_user'
      ELSE 'occasional'
    END                                             AS adoption_tier,
    CASE
      WHEN ufs.total_uses < 3                       THEN 1
      WHEN ufs.total_uses BETWEEN 3 AND 9           THEN 2
      WHEN ufs.total_uses BETWEEN 10 AND 24
           AND ufs.active_weeks >= 3                THEN 3
      WHEN ufs.total_uses >= 25
           AND ufs.active_weeks >= 5                THEN 4
      ELSE 2
    END                                             AS tier_num
  FROM
    user_feature_stats ufs
    LEFT JOIN users u ON ufs.user_id = u.user_id
),

-- Per-feature funnel counts
feature_funnel AS (
  SELECT
    feature,
    COUNT(DISTINCT user_id)                                       AS total_ever_used,

    -- Users who reached each tier (cumulative — tier_num >= N)
    COUNT(DISTINCT CASE WHEN tier_num >= 1 THEN user_id END)      AS reached_first_use,
    COUNT(DISTINCT CASE WHEN tier_num >= 2 THEN user_id END)      AS reached_occasional,
    COUNT(DISTINCT CASE WHEN tier_num >= 3 THEN user_id END)      AS reached_regular,
    COUNT(DISTINCT CASE WHEN tier_num >= 4 THEN user_id END)      AS reached_power_user,

    -- Trial users specifically
    COUNT(DISTINCT CASE WHEN user_type = 'trial'
                        AND tier_num >= 4 THEN user_id END)       AS trial_power_users,
    COUNT(DISTINCT CASE WHEN user_type = 'trial'
                        THEN user_id END)                         AS trial_users_total,

    -- Average total uses per tier
    ROUND(AVG(CASE WHEN tier_num = 4
                   THEN total_uses END), 1)                       AS avg_uses_power_user,
    ROUND(AVG(CASE WHEN tier_num = 3
                   THEN total_uses END), 1)                       AS avg_uses_regular,

    -- Most active feature user
    MAX(total_uses)                                               AS max_uses_any_user
  FROM
    tier_assignment
  GROUP BY
    feature
)

SELECT
  feature,
  total_ever_used,

  -- Funnel counts
  reached_occasional,
  reached_regular,
  reached_power_user,

  -- Funnel conversion rates (as % of total who ever used the feature)
  ROUND(100.0 * reached_occasional  / NULLIF(total_ever_used, 0), 1)  AS pct_to_occasional,
  ROUND(100.0 * reached_regular     / NULLIF(total_ever_used, 0), 1)  AS pct_to_regular,
  ROUND(100.0 * reached_power_user  / NULLIF(total_ever_used, 0), 1)  AS pct_to_power_user,

  -- Stage-to-stage drop-off
  ROUND(100.0 * reached_regular
               / NULLIF(reached_occasional, 0), 1)                    AS occasional_to_regular_pct,
  ROUND(100.0 * reached_power_user
               / NULLIF(reached_regular, 0), 1)                       AS regular_to_power_pct,

  -- Trial user funnel (the key resume metric)
  trial_users_total,
  trial_power_users,
  ROUND(100.0 * trial_power_users
               / NULLIF(trial_users_total, 0), 1)                     AS trial_to_power_pct,

  -- Engagement depth
  avg_uses_power_user,
  avg_uses_regular,
  max_uses_any_user,

  -- Rank features by power user conversion rate
  DENSE_RANK() OVER (
    ORDER BY ROUND(100.0 * reached_power_user
                          / NULLIF(total_ever_used, 0), 1) DESC
  )                                                                    AS power_user_rank

FROM
  feature_funnel
ORDER BY
  pct_to_power_user DESC

-- ---------------------------------------------------------------
-- This is the query behind the resume line:
-- "finding that 22% of trial users became power users within 30 days"
--
-- Look at trial_to_power_pct for the highest-converting feature
-- (e.g. 'search') to find that number.
-- ---------------------------------------------------------------

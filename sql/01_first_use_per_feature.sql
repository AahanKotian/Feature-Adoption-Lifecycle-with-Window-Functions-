-- ============================================================
-- STEP 1: Tag Each User's First Interaction Per Feature
-- ============================================================
-- Goal: For every (user, feature) pair, identify the very
-- first time that user interacted with that feature.
--
-- This is the anchor for the lifecycle clock — "days since
-- first use" is calculated from this date forward.
--
-- Key technique: ROW_NUMBER() OVER (PARTITION BY user_id, feature
-- ORDER BY event_time) = 1 to isolate the first event cleanly.
--
-- Mode dataset: tutorial.yammer_events
-- Local dataset: feature_events
-- ============================================================

WITH ranked_events AS (
  SELECT
    user_id,
    feature,
    event_time,
    DATE(event_time)                                AS event_date,
    ROW_NUMBER() OVER (
      PARTITION BY user_id, feature
      ORDER BY event_time ASC
    )                                               AS use_number
  FROM
    feature_events
    -- For Mode: replace with tutorial.yammer_events
    -- and add: WHERE event_type = 'engagement'
),

first_uses AS (
  SELECT
    user_id,
    feature,
    event_date                                      AS first_use_date,
    event_time                                      AS first_use_time
  FROM
    ranked_events
  WHERE
    use_number = 1
)

SELECT
  fu.user_id,
  fu.feature,
  fu.first_use_date,
  -- How many total times has this user used this feature?
  COUNT(re.user_id)                                 AS total_lifetime_uses,
  -- How many distinct days did they use it?
  COUNT(DISTINCT re.event_date)                     AS active_days,
  -- Most recent use
  MAX(re.event_date)                                AS last_use_date,
  -- Days between first and last use (feature engagement span)
  CAST(
    JULIANDAY(MAX(re.event_date)) -
    JULIANDAY(fu.first_use_date)
    AS INTEGER
  )                                                 AS engagement_span_days
FROM
  first_uses     fu
  JOIN ranked_events re
    ON fu.user_id  = re.user_id
    AND fu.feature = re.feature
GROUP BY
  fu.user_id,
  fu.feature,
  fu.first_use_date
ORDER BY
  fu.feature,
  total_lifetime_uses DESC

-- ---------------------------------------------------------------
-- Note: engagement_span_days = 0 means a user only ever used
-- the feature on a single day (even if multiple times).
-- This is an early signal of "trial but didn't stick."
-- ---------------------------------------------------------------

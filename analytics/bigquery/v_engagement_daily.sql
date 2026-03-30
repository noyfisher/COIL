-- Daily engagement metrics
-- DAU, sessions per user, and feature adoption counts
-- Schedule: Daily at 02:00 UTC
-- Replace pt-helper-dev.analytics_506142273 with your actual BigQuery dataset

CREATE OR REPLACE VIEW `pt-helper-dev.analytics_506142273.v_engagement_daily` AS
SELECT
  event_date,

  -- Active users
  COUNT(DISTINCT user_pseudo_id) AS dau,

  -- Session counts
  COUNT(DISTINCT CONCAT(user_pseudo_id, '-',
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
  )) AS total_sessions,

  -- Feature adoption (unique users per feature)
  COUNT(DISTINCT CASE WHEN event_name = 'exercise_swapped' THEN user_pseudo_id END) AS users_swapped_exercise,
  COUNT(DISTINCT CASE WHEN event_name = 'recovery_insights_viewed' THEN user_pseudo_id END) AS users_viewed_insights,
  COUNT(DISTINCT CASE WHEN event_name = 'achievement_earned' THEN user_pseudo_id END) AS users_earned_achievement,
  COUNT(DISTINCT CASE WHEN event_name = 'reassessment_started' THEN user_pseudo_id END) AS users_reassessed,
  COUNT(DISTINCT CASE WHEN event_name = 'pdf_exported' THEN user_pseudo_id END) AS users_exported_pdf,

  -- Workout engagement
  COUNT(CASE WHEN event_name = 'workout_started' THEN 1 END) AS workouts_started,
  COUNT(CASE WHEN event_name = 'workout_completed' THEN 1 END) AS workouts_completed,
  COUNT(CASE WHEN event_name = 'exercise_skipped' THEN 1 END) AS exercises_skipped,
  COUNT(CASE WHEN event_name = 'exercise_swapped' THEN 1 END) AS exercises_swapped

FROM
  `pt-helper-dev.analytics_506142273.events_*`
WHERE
  _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
GROUP BY
  event_date
ORDER BY
  event_date DESC;

-- Daily funnel conversion counts
-- Shows how many unique users reached each funnel step per day
-- Schedule: Daily at 02:00 UTC
-- Replace pt-helper-dev.analytics_506142273 with your actual BigQuery dataset

CREATE OR REPLACE VIEW `pt-helper-dev.analytics_506142273.v_funnel_daily` AS
SELECT
  event_date,
  COUNT(DISTINCT CASE WHEN event_name = 'sign_in_completed' THEN user_pseudo_id END) AS sign_ins,
  COUNT(DISTINCT CASE WHEN event_name = 'onboarding_completed' THEN user_pseudo_id END) AS onboarding_completed,
  COUNT(DISTINCT CASE WHEN event_name = 'onboarding_skipped' THEN user_pseudo_id END) AS onboarding_skipped,
  COUNT(DISTINCT CASE WHEN event_name = 'body_map_opened' THEN user_pseudo_id END) AS body_map_opened,
  COUNT(DISTINCT CASE WHEN event_name = 'regions_selected' THEN user_pseudo_id END) AS regions_selected,
  COUNT(DISTINCT CASE WHEN event_name = 'assessment_completed' THEN user_pseudo_id END) AS assessment_completed,
  COUNT(DISTINCT CASE WHEN event_name = 'analysis_completed' THEN user_pseudo_id END) AS analysis_completed,
  COUNT(DISTINCT CASE WHEN event_name = 'analysis_failed' THEN user_pseudo_id END) AS analysis_failed,
  COUNT(DISTINCT CASE WHEN event_name = 'rehab_plan_generated' THEN user_pseudo_id END) AS rehab_plan_generated,
  COUNT(DISTINCT CASE WHEN event_name = 'workout_started' THEN user_pseudo_id END) AS workout_started,
  COUNT(DISTINCT CASE WHEN event_name = 'workout_completed' THEN user_pseudo_id END) AS workout_completed,
  COUNT(DISTINCT CASE WHEN event_name = 'workout_ended_early' THEN user_pseudo_id END) AS workout_ended_early
FROM
  `pt-helper-dev.analytics_506142273.events_*`
WHERE
  _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
GROUP BY
  event_date
ORDER BY
  event_date DESC;

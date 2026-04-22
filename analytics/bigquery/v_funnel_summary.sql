-- Funnel summary with drop-off percentages
-- Shows total unique users at each step and % drop-off from previous step
-- Used by Looker Studio funnel/bar chart
-- Replace pt-helper-dev.analytics_506142273 with your actual BigQuery dataset

CREATE OR REPLACE VIEW `pt-helper-dev.analytics_506142273.v_funnel_summary` AS
WITH step_counts AS (
  SELECT
    1 AS step_order, 'Sign In' AS step_name,
    COUNT(DISTINCT user_pseudo_id) AS unique_users
  FROM `pt-helper-dev.analytics_506142273.events_*`
  WHERE event_name = 'sign_in_completed'
    AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))

  UNION ALL
  SELECT 2, 'Onboarding',
    COUNT(DISTINCT user_pseudo_id)
  FROM `pt-helper-dev.analytics_506142273.events_*`
  WHERE event_name IN ('onboarding_completed', 'onboarding_skipped')
    AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))

  UNION ALL
  SELECT 3, 'Body Map',
    COUNT(DISTINCT user_pseudo_id)
  FROM `pt-helper-dev.analytics_506142273.events_*`
  WHERE event_name = 'body_map_opened'
    AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))

  UNION ALL
  SELECT 4, 'Regions Selected',
    COUNT(DISTINCT user_pseudo_id)
  FROM `pt-helper-dev.analytics_506142273.events_*`
  WHERE event_name = 'regions_selected'
    AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))

  UNION ALL
  SELECT 5, 'Assessment',
    COUNT(DISTINCT user_pseudo_id)
  FROM `pt-helper-dev.analytics_506142273.events_*`
  WHERE event_name = 'assessment_completed'
    AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))

  UNION ALL
  SELECT 6, 'Analysis',
    COUNT(DISTINCT user_pseudo_id)
  FROM `pt-helper-dev.analytics_506142273.events_*`
  WHERE event_name = 'analysis_completed'
    AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))

  UNION ALL
  SELECT 7, 'Rehab Plan',
    COUNT(DISTINCT user_pseudo_id)
  FROM `pt-helper-dev.analytics_506142273.events_*`
  WHERE event_name = 'rehab_plan_generated'
    AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))

  UNION ALL
  SELECT 8, 'Workout Started',
    COUNT(DISTINCT user_pseudo_id)
  FROM `pt-helper-dev.analytics_506142273.events_*`
  WHERE event_name = 'workout_started'
    AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))

  UNION ALL
  SELECT 9, 'Workout Completed',
    COUNT(DISTINCT user_pseudo_id)
  FROM `pt-helper-dev.analytics_506142273.events_*`
  WHERE event_name = 'workout_completed'
    AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))

  UNION ALL
  SELECT 10, 'Form Check Done',
    COUNT(DISTINCT user_pseudo_id)
  FROM `pt-helper-dev.analytics_506142273.events_*`
  WHERE event_name = 'form_analysis_completed'
    AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
)

SELECT
  step_order,
  step_name,
  unique_users,
  LAG(unique_users) OVER (ORDER BY step_order) AS previous_step_users,
  ROUND(
    SAFE_DIVIDE(
      unique_users,
      LAG(unique_users) OVER (ORDER BY step_order)
    ) * 100, 1
  ) AS conversion_pct,
  ROUND(
    100 - SAFE_DIVIDE(
      unique_users,
      LAG(unique_users) OVER (ORDER BY step_order)
    ) * 100, 1
  ) AS dropoff_pct
FROM step_counts
ORDER BY step_order;

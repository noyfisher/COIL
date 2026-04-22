-- User journey Sankey diagram data
-- Shows forward-only flow between funnel steps as source → target → user_count
-- Sankey charts require acyclic data (no loops), so backward transitions are excluded
-- Replace pt-helper-dev.analytics_506142273 with your actual BigQuery dataset

CREATE OR REPLACE VIEW `pt-helper-dev.analytics_506142273.v_user_journey_sankey` AS
WITH funnel_events AS (
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,
    -- Assign step order for forward-only filtering
    CASE event_name
      WHEN 'sign_in_completed' THEN 1
      WHEN 'onboarding_completed' THEN 2
      WHEN 'onboarding_skipped' THEN 2
      WHEN 'body_map_opened' THEN 3
      WHEN 'regions_selected' THEN 4
      WHEN 'assessment_completed' THEN 5
      WHEN 'analysis_completed' THEN 6
      WHEN 'analysis_failed' THEN 6
      WHEN 'rehab_plan_generated' THEN 7
      WHEN 'workout_started' THEN 8
      WHEN 'form_analysis_completed' THEN 8
      WHEN 'workout_completed' THEN 9
      WHEN 'workout_ended_early' THEN 9
    END AS step_order,
    CASE event_name
      WHEN 'sign_in_completed' THEN '1. Sign In'
      WHEN 'onboarding_completed' THEN '2. Onboarding Done'
      WHEN 'onboarding_skipped' THEN '2. Onboarding Skipped'
      WHEN 'body_map_opened' THEN '3. Body Map'
      WHEN 'regions_selected' THEN '4. Regions Selected'
      WHEN 'assessment_completed' THEN '5. Assessment Done'
      WHEN 'analysis_completed' THEN '6. Analysis Done'
      WHEN 'analysis_failed' THEN '6. Analysis Failed'
      WHEN 'rehab_plan_generated' THEN '7. Rehab Plan'
      WHEN 'workout_started' THEN '8. Workout Started'
      WHEN 'workout_completed' THEN '9. Workout Done'
      WHEN 'workout_ended_early' THEN '9. Workout Ended Early'
      WHEN 'form_analysis_completed' THEN '8. Form Check Done'
    END AS step_label,
    ROW_NUMBER() OVER (
      PARTITION BY user_pseudo_id, event_name, event_date
      ORDER BY event_timestamp
    ) AS event_occurrence
  FROM
    `pt-helper-dev.analytics_506142273.events_*`
  WHERE
    event_name IN (
      'sign_in_completed',
      'onboarding_completed', 'onboarding_skipped',
      'body_map_opened',
      'regions_selected',
      'assessment_completed',
      'analysis_completed', 'analysis_failed',
      'rehab_plan_generated',
      'workout_started', 'workout_completed', 'workout_ended_early',
      'form_analysis_completed'
    )
    AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
),

deduped AS (
  SELECT * FROM funnel_events WHERE event_occurrence = 1
),

with_next_step AS (
  SELECT
    user_pseudo_id,
    step_label AS source_step,
    step_order AS source_order,
    LEAD(step_label) OVER (
      PARTITION BY user_pseudo_id ORDER BY event_timestamp
    ) AS target_step,
    LEAD(step_order) OVER (
      PARTITION BY user_pseudo_id ORDER BY event_timestamp
    ) AS target_order
  FROM deduped
)

SELECT
  source_step,
  target_step,
  COUNT(DISTINCT user_pseudo_id) AS user_count
FROM with_next_step
WHERE
  -- Only forward transitions (no cycles)
  target_step IS NOT NULL
  AND target_order > source_order
  -- Prevent same-label edges (Sankey requires distinct source/target)
  AND source_step != target_step
GROUP BY source_step, target_step
HAVING user_count > 0
ORDER BY user_count DESC;

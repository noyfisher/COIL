-- Workout performance metrics
-- Completion rate, average duration, skip/swap rates
-- Schedule: Daily at 02:00 UTC
-- Replace pt-helper-dev.analytics_506142273 with your actual BigQuery dataset

CREATE OR REPLACE VIEW `pt-helper-dev.analytics_506142273.v_workout_metrics` AS
WITH workout_events AS (
  SELECT
    event_date,
    user_pseudo_id,
    event_name,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'duration_seconds') AS duration_seconds,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'exercises_completed') AS exercises_completed,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'exercises_skipped') AS exercises_skipped,
    -- workout_ended_early emits completed_count/skipped_count instead of exercises_completed/exercises_skipped
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'completed_count') AS completed_count,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'skipped_count') AS skipped_count,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'exercise_count') AS exercise_count,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'swap_reason') AS swap_reason
  FROM
    `pt-helper-dev.analytics_506142273.events_*`
  WHERE
    event_name IN ('workout_started', 'workout_completed', 'workout_ended_early', 'exercise_swapped')
    AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
)

SELECT
  event_date,

  -- Completion metrics
  COUNTIF(event_name = 'workout_started') AS workouts_started,
  COUNTIF(event_name = 'workout_completed') AS workouts_completed,
  COUNTIF(event_name = 'workout_ended_early') AS workouts_ended_early,
  SAFE_DIVIDE(
    COUNTIF(event_name = 'workout_completed'),
    COUNTIF(event_name = 'workout_started')
  ) * 100 AS completion_rate_pct,

  -- Duration
  AVG(CASE WHEN event_name = 'workout_completed' THEN duration_seconds END) AS avg_duration_seconds,

  -- Exercise metrics
  -- workout_ended_early has no exercises_completed/exercises_skipped params (it emits
  -- completed_count/skipped_count instead), so COALESCE across both param names
  AVG(CASE WHEN event_name = 'workout_completed' THEN COALESCE(exercises_completed, completed_count) END) AS avg_exercises_completed,
  AVG(CASE WHEN event_name IN ('workout_completed', 'workout_ended_early') THEN COALESCE(exercises_skipped, skipped_count) END) AS avg_exercises_skipped,

  -- Swap reasons
  COUNTIF(event_name = 'exercise_swapped') AS total_swaps,
  COUNTIF(event_name = 'exercise_swapped' AND swap_reason = 'too_painful') AS swaps_too_painful,
  COUNTIF(event_name = 'exercise_swapped' AND swap_reason = 'no_equipment') AS swaps_no_equipment,
  COUNTIF(event_name = 'exercise_swapped' AND swap_reason = 'too_difficult') AS swaps_too_difficult

FROM
  workout_events
GROUP BY
  event_date
ORDER BY
  event_date DESC;

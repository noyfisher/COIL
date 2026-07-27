-- Weekly cohort retention matrix
-- Signup week vs return week, showing % of users who came back
-- Schedule: Weekly Sunday 03:00 UTC
-- Replace pt-helper-dev.analytics_506142273 with your actual BigQuery dataset

CREATE OR REPLACE VIEW `pt-helper-dev.analytics_506142273.v_retention_cohorts` AS
WITH user_first_seen AS (
  SELECT
    user_pseudo_id,
    MIN(PARSE_DATE('%Y%m%d', event_date)) AS signup_date,
    DATE_TRUNC(MIN(PARSE_DATE('%Y%m%d', event_date)), WEEK) AS signup_week
  FROM
    `pt-helper-dev.analytics_506142273.events_*`
  WHERE
    event_name = 'sign_in_completed'
  GROUP BY
    user_pseudo_id
),

-- Cohort size must be computed OUTSIDE the activity join: within a
-- (signup_week, weeks_since_signup) group the joined rows only contain users
-- active that week, so counting f.user_pseudo_id there equals active_users and
-- retention_pct reads 100% in every cell.
cohort_sizes AS (
  SELECT
    signup_week,
    COUNT(DISTINCT user_pseudo_id) AS cohort_size
  FROM
    user_first_seen
  GROUP BY
    signup_week
),

user_activity AS (
  SELECT DISTINCT
    user_pseudo_id,
    DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), WEEK) AS activity_week
  FROM
    `pt-helper-dev.analytics_506142273.events_*`
  WHERE
    event_name IN ('app_opened', 'workout_started', 'analysis_completed', 'rehab_plan_generated')
)

SELECT
  f.signup_week,
  DATE_DIFF(a.activity_week, f.signup_week, WEEK) AS weeks_since_signup,
  COUNT(DISTINCT a.user_pseudo_id) AS active_users,
  c.cohort_size,
  ROUND(COUNT(DISTINCT a.user_pseudo_id) / c.cohort_size * 100, 1) AS retention_pct
FROM
  user_first_seen f
JOIN
  cohort_sizes c ON c.signup_week = f.signup_week
LEFT JOIN
  user_activity a ON f.user_pseudo_id = a.user_pseudo_id AND a.activity_week >= f.signup_week
GROUP BY
  f.signup_week, weeks_since_signup, c.cohort_size
HAVING
  weeks_since_signup >= 0
ORDER BY
  f.signup_week DESC, weeks_since_signup;

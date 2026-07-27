-- Screen-to-screen navigation flow, per day
-- Consecutive screen_view transitions within a session (source_screen -> target_screen)
-- Feeds the dashboard's screen-flow Sankey graph; self-loops (same screen twice in a row) are excluded
-- Replace pt-helper-dev.analytics_506142273 with your actual BigQuery dataset

CREATE OR REPLACE VIEW `pt-helper-dev.analytics_506142273.v_screen_flow_daily` AS
WITH screen_views AS (
  SELECT
    event_date,
    user_pseudo_id,
    event_timestamp,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'screen_name') AS screen_name,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id
  FROM
    `pt-helper-dev.analytics_506142273.events_*`
  WHERE
    event_name = 'screen_view'
    AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
),

with_next_screen AS (
  SELECT
    event_date,
    screen_name,
    LEAD(screen_name) OVER (
      PARTITION BY user_pseudo_id, ga_session_id ORDER BY event_timestamp
    ) AS next_screen
  FROM
    screen_views
)

SELECT
  event_date,
  screen_name AS source_screen,
  next_screen AS target_screen,
  COUNT(*) AS transition_count
FROM with_next_screen
WHERE
  -- Drop the last screen_view per session (no next screen) and same-screen re-appearances
  next_screen IS NOT NULL
  AND next_screen != screen_name
GROUP BY event_date, source_screen, target_screen
ORDER BY event_date DESC, transition_count DESC;

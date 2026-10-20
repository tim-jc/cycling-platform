-- Canonical bootstrap publishes the recovery view and its dependent debt/health
-- views before migrations run. Recreate the new authoritative contract here so
-- the immutable migration ledger also records this observability increment.
CREATE OR REPLACE VIEW cycling_platform_admin.v_google_health_daily_ingestion_failure_history AS
WITH RECURSIVE
failed_entities AS (
  SELECT entity.run_entity_id, entity.run_id, run.pipeline_run_id,
         entity.source_id, source.source_name, entity.entity_name,
         entity.started_at, entity.completed_at, entity.entity_status,
         entity.error_message
  FROM cycling_platform_admin.etl_run_entity entity
  INNER JOIN cycling_platform_admin.etl_run run
    ON run.run_id = entity.run_id
  LEFT JOIN cycling_platform_admin.data_source source
    ON source.source_id = entity.source_id
  WHERE entity.entity_status = 'FAILED'
    AND entity.entity_name IN (
      'google_health_daily_resting_heart_rate',
      'google_health_daily_heart_rate_variability',
      'google_health_daily_respiratory_rate'
    )
),
failed_windows AS (
  SELECT DISTINCT failed.run_entity_id,
         request.requested_start_date, request.requested_end_date
  FROM failed_entities failed
  INNER JOIN cycling_platform_admin.etl_request_log request
    ON request.run_entity_id = failed.run_entity_id
  WHERE request.requested_start_date IS NOT NULL
    AND request.requested_end_date > request.requested_start_date
),
failed_days AS (
  SELECT run_entity_id, requested_start_date, requested_end_date,
         requested_start_date AS coverage_date
  FROM failed_windows
  UNION ALL
  SELECT run_entity_id, requested_start_date, requested_end_date,
         DATE_ADD(coverage_date, INTERVAL 1 DAY)
  FROM failed_days
  WHERE DATE_ADD(coverage_date, INTERVAL 1 DAY) < requested_end_date
),
day_recovery AS (
  SELECT failed_day.run_entity_id,
         failed_day.requested_start_date,
         failed_day.requested_end_date,
         failed_day.coverage_date,
         MIN(CASE WHEN recovered_request.request_id IS NOT NULL
                  THEN recovered.completed_at END) AS recovery_completed_at,
         SUBSTRING_INDEX(
           GROUP_CONCAT(
             CASE WHEN recovered_request.request_id IS NOT NULL
                  THEN recovered.run_entity_id END
             ORDER BY recovered.completed_at, recovered.run_entity_id
           ),
           ',', 1
         ) AS recovery_run_entity_id
  FROM failed_days failed_day
  INNER JOIN failed_entities failed
    ON failed.run_entity_id = failed_day.run_entity_id
  LEFT JOIN cycling_platform_admin.etl_run_entity recovered
    ON recovered.entity_name = failed.entity_name
   AND recovered.source_id <=> failed.source_id
   AND recovered.entity_status = 'SUCCESS'
   AND recovered.started_at > COALESCE(failed.completed_at, failed.started_at)
   AND recovered.completed_at IS NOT NULL
  LEFT JOIN cycling_platform_admin.etl_request_log recovered_request
    ON recovered_request.run_entity_id = recovered.run_entity_id
   AND recovered_request.request_status = 'SUCCESS'
   AND recovered_request.requested_start_date <= failed_day.coverage_date
   AND recovered_request.requested_end_date > failed_day.coverage_date
  GROUP BY failed_day.run_entity_id,
           failed_day.requested_start_date,
           failed_day.requested_end_date,
           failed_day.coverage_date
),
window_recovery AS (
  SELECT run_entity_id, requested_start_date, requested_end_date,
         CASE WHEN COUNT(*) = COUNT(recovery_completed_at) THEN 1 ELSE 0 END AS is_covered,
         CASE WHEN COUNT(*) = COUNT(recovery_completed_at)
              THEN MAX(recovery_completed_at) END AS recovery_completed_at,
         CASE WHEN COUNT(*) = COUNT(recovery_completed_at)
              THEN GROUP_CONCAT(DISTINCT recovery_run_entity_id ORDER BY recovery_run_entity_id)
              END COLLATE utf8mb4_general_ci AS recovery_run_entity_ids
  FROM day_recovery
  GROUP BY run_entity_id, requested_start_date, requested_end_date
),
entity_recovery AS (
  SELECT run_entity_id,
         COUNT(*) AS failed_request_window_count,
         SUM(is_covered) AS covered_request_window_count,
         MIN(requested_start_date) AS earliest_failed_request_start_date,
         MAX(requested_end_date) AS latest_failed_request_end_date,
         CASE WHEN COUNT(*) = SUM(is_covered)
              THEN MAX(recovery_completed_at) END AS recovery_completed_at,
         CASE WHEN COUNT(*) = SUM(is_covered)
              THEN GROUP_CONCAT(DISTINCT recovery_run_entity_ids ORDER BY recovery_run_entity_ids)
              END COLLATE utf8mb4_general_ci AS recovery_run_entity_ids
  FROM window_recovery
  GROUP BY run_entity_id
)
SELECT failed.run_entity_id AS failed_run_entity_id,
       failed.run_id AS failed_run_id,
       failed.pipeline_run_id,
       failed.source_id, failed.source_name, failed.entity_name,
       failed.started_at AS failure_started_at_utc,
       failed.completed_at AS failure_completed_at_utc,
       failed.entity_status AS original_entity_status,
       failed.error_message AS error_summary,
       COALESCE(recovery.failed_request_window_count, 0) AS failed_request_window_count,
       recovery.earliest_failed_request_start_date,
       recovery.latest_failed_request_end_date,
       CASE
         WHEN recovery.failed_request_window_count IS NULL THEN 'UNKNOWN'
         WHEN recovery.failed_request_window_count = recovery.covered_request_window_count THEN 'RECOVERED'
         ELSE 'UNRESOLVED'
       END COLLATE utf8mb4_general_ci AS recovery_status,
       COALESCE(recovery.covered_request_window_count, 0) AS covered_request_window_count,
       recovery.recovery_completed_at AS recovery_completed_at_utc,
       recovery.recovery_run_entity_ids
FROM failed_entities failed
LEFT JOIN entity_recovery recovery
  ON recovery.run_entity_id = failed.run_entity_id;

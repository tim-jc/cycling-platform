-- Select the latest terminal validation assessment by completion time for each
-- scope. Active-only scopes remain visible as UNKNOWN, while no validation
-- history preserves the existing HEALTHY aggregate behaviour.

CREATE OR REPLACE VIEW cycling_platform_admin.v_operational_debt_condition_latest AS
  SELECT 'raw_activity_details' COLLATE utf8mb4_general_ci debt_key, 'RAW' COLLATE utf8mb4_general_ci debt_domain,
         CASE WHEN COALESCE(SUM(details_status = 'FAILED'), 0) > 0 THEN 'CRITICAL' WHEN COALESCE(SUM(details_status = 'PENDING'), 0) > 0 THEN 'WARNING' ELSE 'HEALTHY' END COLLATE utf8mb4_general_ci health_status,
         COALESCE(SUM(details_status IN ('PENDING', 'FAILED')), 0) item_count,
         'Activities awaiting or failing Raw detail retrieval' COLLATE utf8mb4_general_ci summary
  FROM cycling_platform_raw.activities
  UNION ALL
  SELECT 'raw_activity_streams' COLLATE utf8mb4_general_ci, 'RAW' COLLATE utf8mb4_general_ci,
         CASE WHEN COALESCE(SUM(stream_status = 'FAILED'), 0) > 0 THEN 'CRITICAL' WHEN COALESCE(SUM(stream_status = 'PENDING'), 0) > 0 THEN 'WARNING' ELSE 'HEALTHY' END COLLATE utf8mb4_general_ci,
         COALESCE(SUM(stream_status IN ('PENDING', 'FAILED')), 0), 'Activities awaiting or failing Raw stream retrieval' COLLATE utf8mb4_general_ci
  FROM cycling_platform_raw.activities
  UNION ALL
  SELECT 'raw_activity_laps' COLLATE utf8mb4_general_ci, 'RAW' COLLATE utf8mb4_general_ci,
         CASE WHEN COALESCE(SUM(laps_status = 'FAILED'), 0) > 0 THEN 'CRITICAL' WHEN COALESCE(SUM(laps_status = 'PENDING'), 0) > 0 THEN 'WARNING' ELSE 'HEALTHY' END COLLATE utf8mb4_general_ci,
         COALESCE(SUM(laps_status IN ('PENDING', 'FAILED')), 0), 'Activities awaiting or failing Raw lap retrieval' COLLATE utf8mb4_general_ci
  FROM cycling_platform_raw.activities
  UNION ALL
  SELECT 'achievement_evaluation' COLLATE utf8mb4_general_ci, 'GOLD' COLLATE utf8mb4_general_ci,
         CASE WHEN COUNT(*) > 0 THEN 'CRITICAL' ELSE 'HEALTHY' END COLLATE utf8mb4_general_ci,
         COUNT(*), 'Achievement evaluations currently INVALIDATED' COLLATE utf8mb4_general_ci
  FROM cycling_platform_admin.activity_achievement_evaluation_state WHERE evaluation_status = 'INVALIDATED'
  UNION ALL
  SELECT 'notification_pending' COLLATE utf8mb4_general_ci, 'NOTIFICATION' COLLATE utf8mb4_general_ci,
         CASE WHEN COUNT(*) > 0 THEN 'WARNING' ELSE 'HEALTHY' END COLLATE utf8mb4_general_ci,
         COUNT(*), 'Achievement notifications awaiting first delivery' COLLATE utf8mb4_general_ci
  FROM cycling_platform_admin.notification_outbox WHERE notification_status = 'PENDING'
  UNION ALL
  SELECT 'notification_retry_or_failed' COLLATE utf8mb4_general_ci, 'NOTIFICATION' COLLATE utf8mb4_general_ci,
         CASE WHEN COUNT(*) > 0 THEN 'CRITICAL' ELSE 'HEALTHY' END COLLATE utf8mb4_general_ci,
         COUNT(*), 'Achievement notifications awaiting retry or terminally failed' COLLATE utf8mb4_general_ci
  FROM cycling_platform_admin.notification_outbox WHERE notification_status IN ('RETRY', 'FAILED')
  UNION ALL
  SELECT 'notification_stale_sending' COLLATE utf8mb4_general_ci, 'NOTIFICATION' COLLATE utf8mb4_general_ci,
         CASE WHEN COUNT(*) > 0 THEN 'CRITICAL' ELSE 'HEALTHY' END COLLATE utf8mb4_general_ci,
         COUNT(*), 'Achievement notifications left SENDING for more than one hour' COLLATE utf8mb4_general_ci
  FROM cycling_platform_admin.notification_outbox
  WHERE notification_status = 'SENDING' AND updated_at < UTC_TIMESTAMP() - INTERVAL 1 HOUR
  UNION ALL
  SELECT 'google_health_daily_ingestion_coverage' COLLATE utf8mb4_general_ci,
         'RAW' COLLATE utf8mb4_general_ci,
         CASE
           WHEN COALESCE(SUM(recovery_status = 'UNRESOLVED'), 0) > 0 THEN 'WARNING'
           WHEN COALESCE(SUM(recovery_status = 'UNKNOWN'), 0) > 0 THEN 'UNKNOWN'
           ELSE 'HEALTHY'
         END COLLATE utf8mb4_general_ci,
         COALESCE(SUM(recovery_status IN ('UNRESOLVED', 'UNKNOWN')), 0),
         'Google Health daily ingestion failures with unresolved or unknown request coverage' COLLATE utf8mb4_general_ci
  FROM cycling_platform_admin.v_google_health_daily_ingestion_failure_history
  UNION ALL
  SELECT 'stale_pipeline_execution' COLLATE utf8mb4_general_ci, 'EXECUTION' COLLATE utf8mb4_general_ci,
         CASE WHEN COUNT(*) > 0 THEN 'CRITICAL' ELSE 'HEALTHY' END COLLATE utf8mb4_general_ci,
         COUNT(*), 'Pipeline executions RUNNING for more than six hours' COLLATE utf8mb4_general_ci
  FROM cycling_platform_admin.pipeline_run WHERE run_status = 'RUNNING' AND started_at < UTC_TIMESTAMP() - INTERVAL 6 HOUR
  UNION ALL
  SELECT 'latest_daily_pipeline' COLLATE utf8mb4_general_ci, 'EXECUTION' COLLATE utf8mb4_general_ci,
         CASE WHEN COUNT(*) > 0 THEN 'CRITICAL' ELSE 'HEALTHY' END COLLATE utf8mb4_general_ci,
         COUNT(*), 'Latest completed daily pipeline did not succeed' COLLATE utf8mb4_general_ci
  FROM cycling_platform_admin.pipeline_run run
  WHERE run.pipeline_run_id = (
    SELECT terminal.pipeline_run_id
    FROM cycling_platform_admin.pipeline_run terminal
    WHERE terminal.pipeline_name = 'daily-platform'
      AND terminal.run_status IN ('SUCCESS', 'FAILED')
    ORDER BY terminal.completed_at DESC, terminal.pipeline_run_id DESC
    LIMIT 1
  ) AND run.run_status = 'FAILED'
  UNION ALL
  SELECT 'stale_child_execution' COLLATE utf8mb4_general_ci, 'EXECUTION' COLLATE utf8mb4_general_ci,
         CASE WHEN ((SELECT COUNT(*) FROM cycling_platform_admin.etl_run WHERE run_status = 'RUNNING' AND started_at < UTC_TIMESTAMP() - INTERVAL 6 HOUR) +
                         (SELECT COUNT(*) FROM cycling_platform_admin.transform_run WHERE run_status = 'RUNNING' AND started_at < UTC_TIMESTAMP() - INTERVAL 6 HOUR) +
                         (SELECT COUNT(*) FROM cycling_platform_admin.validation_run WHERE run_status = 'RUNNING' AND started_at < UTC_TIMESTAMP() - INTERVAL 6 HOUR)) > 0 THEN 'CRITICAL' ELSE 'HEALTHY' END COLLATE utf8mb4_general_ci,
         ((SELECT COUNT(*) FROM cycling_platform_admin.etl_run WHERE run_status = 'RUNNING' AND started_at < UTC_TIMESTAMP() - INTERVAL 6 HOUR) +
          (SELECT COUNT(*) FROM cycling_platform_admin.transform_run WHERE run_status = 'RUNNING' AND started_at < UTC_TIMESTAMP() - INTERVAL 6 HOUR) +
          (SELECT COUNT(*) FROM cycling_platform_admin.validation_run WHERE run_status = 'RUNNING' AND started_at < UTC_TIMESTAMP() - INTERVAL 6 HOUR)),
         'ETL, transform or validation executions RUNNING for more than six hours' COLLATE utf8mb4_general_ci
  UNION ALL
  SELECT 'latest_validation' COLLATE utf8mb4_general_ci, 'VALIDATION' COLLATE utf8mb4_general_ci,
         CASE MAX(CASE history.health_status WHEN 'CRITICAL' THEN 4 WHEN 'WARNING' THEN 3 WHEN 'UNKNOWN' THEN 1 ELSE 0 END)
           WHEN 4 THEN 'CRITICAL' WHEN 3 THEN 'WARNING' WHEN 1 THEN 'UNKNOWN' ELSE 'HEALTHY'
         END COLLATE utf8mb4_general_ci,
         COALESCE(SUM(history.health_status <> 'HEALTHY'), 0),
         'Latest governed validation outcome for each validation scope' COLLATE utf8mb4_general_ci
  FROM (
    SELECT scopes.validation_scope,
           CASE
             WHEN terminal.validation_run_id IS NULL THEN 'UNKNOWN'
             ELSE terminal.health_status
           END COLLATE utf8mb4_general_ci AS health_status
    FROM (
      SELECT DISTINCT validation_scope
      FROM cycling_platform_admin.v_validation_history
    ) scopes
    LEFT JOIN (
      SELECT ranked.validation_run_id, ranked.validation_scope,
             ranked.health_status
      FROM (
        SELECT terminal.validation_run_id, terminal.validation_scope,
               terminal.health_status,
               ROW_NUMBER() OVER (
                 PARTITION BY terminal.validation_scope
                 ORDER BY terminal.completed_at_utc DESC,
                          terminal.validation_run_id DESC
               ) AS terminal_rank
        FROM cycling_platform_admin.v_validation_history terminal
        WHERE terminal.run_status IN ('SUCCESS', 'FAILED', 'TIMED_OUT')
      ) ranked
      WHERE ranked.terminal_rank = 1
    ) terminal
      ON terminal.validation_scope = scopes.validation_scope
  ) history
  UNION ALL
  SELECT 'backup' COLLATE utf8mb4_general_ci, 'BACKUP' COLLATE utf8mb4_general_ci, health_status,
         CASE WHEN health_status = 'HEALTHY' THEN 0 ELSE 1 END,
         'Latest complete recovery point, physical attempt and retention reconciliation' COLLATE utf8mb4_general_ci
  FROM cycling_platform_admin.v_backup_health_latest;

-- Reconcile older Admin databases with the validation summary columns already
-- present in the canonical bootstrap DDL, then publish outcome-aware read views.
ALTER TABLE cycling_platform_admin.validation_run
  ADD COLUMN IF NOT EXISTS validation_outcome VARCHAR(30) NULL AFTER run_status;

ALTER TABLE cycling_platform_admin.validation_run
  ADD COLUMN IF NOT EXISTS total_check_count INT NOT NULL DEFAULT 0 AFTER checks_failed,
  ADD COLUMN IF NOT EXISTS warning_check_count INT NOT NULL DEFAULT 0 AFTER total_check_count,
  ADD COLUMN IF NOT EXISTS warning_issue_count INT NOT NULL DEFAULT 0 AFTER warning_check_count,
  ADD COLUMN IF NOT EXISTS error_check_count INT NOT NULL DEFAULT 0 AFTER warning_issue_count,
  ADD COLUMN IF NOT EXISTS error_issue_count INT NOT NULL DEFAULT 0 AFTER error_check_count,
  ADD COLUMN IF NOT EXISTS skipped_check_count INT NOT NULL DEFAULT 0 AFTER error_issue_count;

ALTER TABLE cycling_platform_admin.validation_run
  ADD INDEX IF NOT EXISTS idx_validation_run_outcome (validation_outcome);

CREATE OR REPLACE VIEW cycling_platform_admin.v_validation_history AS
WITH
check_summary AS (
  SELECT checks.validation_run_id,
         COUNT(*) AS check_count,
         SUM(checks.check_status = 'PASS') AS passed_check_count,
         SUM(checks.check_status = 'FAIL') AS failed_check_count,
         COALESCE(SUM(checks.issue_count), 0) AS issue_count,
         SUM(checks.check_status = 'FAIL' AND checks.severity = 'WARNING') AS warning_failure_count,
         SUM(checks.check_status = 'FAIL' AND checks.severity IN ('CRITICAL', 'ERROR')) AS critical_failure_count,
         SUM(checks.check_status NOT IN ('PASS', 'FAIL') OR checks.check_status IS NULL OR checks.severity IS NULL) AS malformed_check_count
  FROM cycling_platform_admin.validation_run_check checks
  GROUP BY checks.validation_run_id
),
governed_outcome AS (
  SELECT run.validation_run_id, run.pipeline_run_id, run.validation_scope,
         run.run_mode, run.run_status,
         run.started_at AS started_at_utc, run.completed_at AS completed_at_utc,
         run.duration_seconds,
         COALESCE(checks.check_count, 0) AS check_count,
         COALESCE(checks.passed_check_count, 0) AS passed_check_count,
         COALESCE(checks.failed_check_count, 0) AS failed_check_count,
         run.skipped_check_count,
         COALESCE(checks.issue_count, 0) AS issue_count,
         CASE
           WHEN run.run_status = 'TIMED_OUT' THEN 'TIMED_OUT'
           WHEN run.run_status = 'FAILED' THEN 'FAILED'
           WHEN run.run_status = 'RUNNING' THEN NULL
           WHEN run.run_status <> 'SUCCESS' THEN NULL
           WHEN run.validation_outcome IN ('PASSED', 'PASSED_WITH_WARNINGS', 'FAILED', 'TIMED_OUT') THEN run.validation_outcome
           WHEN run.validation_outcome IS NOT NULL THEN NULL
           WHEN COALESCE(checks.malformed_check_count, 0) > 0 THEN NULL
           WHEN run.checks_planned > 0 AND COALESCE(checks.check_count, 0) < run.checks_planned THEN NULL
           WHEN COALESCE(checks.critical_failure_count, 0) > 0 THEN 'FAILED'
           WHEN COALESCE(checks.warning_failure_count, 0) > 0 THEN 'PASSED_WITH_WARNINGS'
           ELSE 'PASSED'
         END COLLATE utf8mb4_general_ci AS validation_outcome,
         run.error_message
  FROM cycling_platform_admin.validation_run run
  LEFT JOIN check_summary checks
    ON checks.validation_run_id = run.validation_run_id
)
SELECT validation_run_id, pipeline_run_id, validation_scope, run_mode,
       run_status, started_at_utc, completed_at_utc,
       duration_seconds, check_count, passed_check_count, failed_check_count,
       skipped_check_count, issue_count,
       CASE validation_outcome
         WHEN 'PASSED' THEN 'HEALTHY'
         WHEN 'PASSED_WITH_WARNINGS' THEN 'WARNING'
         WHEN 'FAILED' THEN 'CRITICAL'
         WHEN 'TIMED_OUT' THEN 'CRITICAL'
         ELSE 'UNKNOWN'
       END COLLATE utf8mb4_general_ci AS health_status,
       error_message,
       validation_outcome
FROM governed_outcome;

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
    SELECT MAX(latest.pipeline_run_id) FROM cycling_platform_admin.pipeline_run latest
    WHERE latest.pipeline_name = 'daily-platform'
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
  FROM cycling_platform_admin.v_validation_history history
  WHERE history.validation_run_id IN (
    SELECT MAX(latest.validation_run_id)
    FROM cycling_platform_admin.v_validation_history latest
    GROUP BY latest.validation_scope
  )
  UNION ALL
  SELECT 'backup' COLLATE utf8mb4_general_ci, 'BACKUP' COLLATE utf8mb4_general_ci, health_status,
         CASE WHEN health_status = 'HEALTHY' THEN 0 ELSE 1 END,
         'Latest complete recovery point, physical attempt and retention reconciliation' COLLATE utf8mb4_general_ci
  FROM cycling_platform_admin.v_backup_health_latest;

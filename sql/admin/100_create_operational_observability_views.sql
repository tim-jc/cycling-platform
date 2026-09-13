-- MariaDB derives the collation of literal-only CASE and UNION expressions
-- from the creating session. Every generated text output is therefore given
-- the governed platform collation explicitly; base-column text retains its
-- canonical table-column collation.
CREATE OR REPLACE VIEW cycling_platform_admin.v_pipeline_run_history AS
SELECT pipeline_run_id, pipeline_name, execution_mode, trigger_type,
       execution_host, requested_window_start, requested_window_end,
       run_status,
       CASE
         WHEN run_status = 'FAILED' THEN 'CRITICAL'
         WHEN run_status = 'RUNNING' AND started_at < UTC_TIMESTAMP() - INTERVAL 6 HOUR THEN 'CRITICAL'
         WHEN run_status = 'RUNNING' THEN 'INFO'
         ELSE 'HEALTHY'
       END COLLATE utf8mb4_general_ci AS health_status,
       started_at AS started_at_utc, completed_at AS completed_at_utc,
       duration_seconds, failure_class, failure_summary
FROM cycling_platform_admin.pipeline_run;

CREATE OR REPLACE VIEW cycling_platform_admin.v_pipeline_phase_history AS
SELECT phase.pipeline_phase_run_id, phase.pipeline_run_id,
       pipeline.pipeline_name, pipeline.execution_mode,
       phase.phase_ordinal, phase.phase_name, phase.phase_status,
       CASE
         WHEN phase.phase_status = 'FAILED' THEN 'CRITICAL'
         WHEN phase.phase_status = 'RUNNING' AND phase.started_at < UTC_TIMESTAMP() - INTERVAL 6 HOUR THEN 'CRITICAL'
         WHEN phase.phase_status IN ('RUNNING', 'SKIPPED', 'NOT_RUN') THEN 'INFO'
         ELSE 'HEALTHY'
       END COLLATE utf8mb4_general_ci AS health_status,
       phase.started_at AS started_at_utc,
       phase.completed_at AS completed_at_utc,
       phase.duration_seconds,
       phase.notifications_queued, phase.notifications_attempted,
       phase.notifications_sent, phase.notifications_failed,
       phase.notifications_deferred,
       phase.failure_class, phase.failure_summary
FROM cycling_platform_admin.pipeline_phase_run phase
INNER JOIN cycling_platform_admin.pipeline_run pipeline
  ON pipeline.pipeline_run_id = phase.pipeline_run_id;

CREATE OR REPLACE VIEW cycling_platform_admin.v_transform_performance_history AS
SELECT run.transform_run_id, run.pipeline_run_id, run.layer_name,
       run.entity_name, run.run_mode, run.run_status,
       run.started_at AS started_at_utc, run.completed_at AS completed_at_utc,
       run.duration_seconds AS total_duration_seconds,
       run.setup_seconds, run.discovery_seconds,
       run.source_preparation_seconds, run.processing_seconds,
       run.finalisation_seconds,
       run.discovery_mode, run.candidate_mode, run.invalidation_action,
       run.invalidation_reason, run.dependency_start_date,
       run.total_batches, run.completed_batches,
       run.activities_planned, run.activities_completed,
       run.expected_rows_planned, run.rows_inserted, run.rows_updated,
       run.rows_deleted,
       MAX(CASE WHEN metric.metric_name = 'upstream_affected_count' THEN metric.metric_value END) AS upstream_affected_count,
       MAX(CASE WHEN metric.metric_name = 'output_changed_activity_count' THEN metric.metric_value END) AS output_changed_activity_count,
       MAX(CASE WHEN metric.metric_name = 'repair_candidate_count' THEN metric.metric_value END) AS repair_candidate_count,
       MAX(CASE WHEN metric.metric_name = 'direct_affected_count' THEN metric.metric_value END) AS direct_affected_count,
       MAX(CASE WHEN metric.metric_name = 'evaluation_debt_count' THEN metric.metric_value END) AS evaluation_debt_count,
       MAX(CASE WHEN metric.metric_name = 'closure_activity_count' THEN metric.metric_value END) AS closure_activity_count,
       MAX(CASE WHEN metric.metric_name = 'zero_achievement_evaluations' THEN metric.metric_value END) AS zero_achievement_evaluations,
       MAX(CASE WHEN metric.metric_name = 'evaluation_state_rows_invalidated' THEN metric.metric_value END) AS evaluation_state_rows_invalidated,
       MAX(CASE WHEN metric.metric_name = 'evaluation_state_rows_current' THEN metric.metric_value END) AS evaluation_state_rows_current,
       MAX(CASE WHEN metric.metric_name = 'remaining_invalidated_count' THEN metric.metric_value END) AS remaining_invalidated_count,
       CASE WHEN COUNT(metric.metric_name) = 0 THEN 0 ELSE 1 END AS has_phase_1b_metrics
FROM cycling_platform_admin.transform_run run
LEFT JOIN cycling_platform_admin.transform_run_metric metric
  ON metric.transform_run_id = run.transform_run_id
GROUP BY run.transform_run_id, run.pipeline_run_id, run.layer_name,
         run.entity_name, run.run_mode, run.run_status, run.started_at,
         run.completed_at, run.duration_seconds, run.setup_seconds,
         run.discovery_seconds, run.source_preparation_seconds,
         run.processing_seconds, run.finalisation_seconds,
         run.discovery_mode, run.candidate_mode, run.invalidation_action,
         run.invalidation_reason, run.dependency_start_date,
         run.total_batches, run.completed_batches, run.activities_planned,
         run.activities_completed, run.expected_rows_planned,
         run.rows_inserted, run.rows_updated, run.rows_deleted;

CREATE OR REPLACE VIEW cycling_platform_admin.v_source_freshness_observation_history AS
SELECT observation.source_freshness_observation_id,
       observation.source_id, observation.entity_name, observation.run_id,
       observation.run_entity_id, entity.entity_status,
       entity.started_at, entity.completed_at,
       observation.newest_source_data_at, observation.observed_at,
       LAG(observation.newest_source_data_at) OVER (
         PARTITION BY observation.source_id, observation.entity_name
         ORDER BY observation.observed_at, observation.source_freshness_observation_id
       ) AS previous_source_data_at,
       ROW_NUMBER() OVER (
         PARTITION BY observation.source_id, observation.entity_name
         ORDER BY observation.observed_at DESC, observation.source_freshness_observation_id DESC
       ) AS latest_rank
FROM cycling_platform_admin.source_freshness_observation observation
INNER JOIN cycling_platform_admin.etl_run_entity entity
  ON entity.run_entity_id = observation.run_entity_id;

CREATE OR REPLACE VIEW cycling_platform_admin.v_source_execution_success_latest AS
SELECT source_id, entity_name, MAX(completed_at) AS latest_success_at_utc
FROM cycling_platform_admin.etl_run_entity
WHERE entity_status = 'SUCCESS'
GROUP BY source_id, entity_name;

CREATE OR REPLACE VIEW cycling_platform_admin.v_source_freshness_latest AS
SELECT policy.source_id, source.source_name, policy.entity_name,
       policy.entity_requirement, policy.execution_freshness_enabled,
       policy.source_data_timestamp_semantics,
       latest.run_id AS latest_run_id,
       latest.run_entity_id AS latest_run_entity_id,
       latest.entity_status AS latest_execution_status,
       latest.started_at AS latest_attempt_started_at_utc,
       latest.completed_at AS latest_attempt_completed_at_utc,
       success.latest_success_at_utc,
       latest.newest_source_data_at AS newest_source_data_at_utc,
       latest.previous_source_data_at AS previous_source_data_at_utc,
       CASE
         WHEN latest.run_entity_id IS NULL THEN 'NEVER_OBSERVED'
         WHEN latest.newest_source_data_at IS NULL THEN 'NO_SOURCE_DATA'
         WHEN latest.previous_source_data_at IS NULL THEN 'FIRST_OBSERVATION'
         WHEN latest.newest_source_data_at > latest.previous_source_data_at THEN 'ADVANCED'
         WHEN latest.newest_source_data_at = latest.previous_source_data_at THEN 'UNCHANGED'
         ELSE 'REGRESSED'
       END COLLATE utf8mb4_general_ci AS source_data_change_status,
       TIMESTAMPDIFF(MINUTE, success.latest_success_at_utc, UTC_TIMESTAMP()) / 60.0 AS execution_age_hours,
       TIMESTAMPDIFF(MINUTE, latest.newest_source_data_at, UTC_TIMESTAMP()) / 60.0 AS source_data_age_hours,
       CASE
         WHEN policy.execution_freshness_enabled = 0 AND latest.run_entity_id IS NULL THEN 'INFO'
         WHEN latest.run_entity_id IS NULL THEN
           CASE WHEN policy.entity_requirement = 'REQUIRED' THEN 'UNKNOWN' ELSE 'INFO' END
         WHEN latest.entity_status <> 'SUCCESS' THEN
           CASE WHEN policy.entity_requirement = 'REQUIRED' THEN 'CRITICAL' ELSE 'WARNING' END
         WHEN policy.execution_freshness_enabled = 0 THEN 'HEALTHY'
         WHEN success.latest_success_at_utc IS NULL THEN 'UNKNOWN'
         WHEN TIMESTAMPDIFF(MINUTE, success.latest_success_at_utc, UTC_TIMESTAMP()) / 60.0 > policy.critical_after_hours THEN
           CASE WHEN policy.entity_requirement = 'REQUIRED' THEN 'CRITICAL' ELSE 'INFO' END
         WHEN TIMESTAMPDIFF(MINUTE, success.latest_success_at_utc, UTC_TIMESTAMP()) / 60.0 > policy.warning_after_hours THEN
           CASE WHEN policy.entity_requirement = 'REQUIRED' THEN 'WARNING' ELSE 'INFO' END
         WHEN latest.newest_source_data_at IS NULL THEN 'INFO'
         ELSE 'HEALTHY'
       END COLLATE utf8mb4_general_ci AS health_status
FROM cycling_platform_admin.source_entity_observability_policy policy
INNER JOIN cycling_platform_admin.data_source source ON source.source_id = policy.source_id
LEFT JOIN cycling_platform_admin.v_source_freshness_observation_history latest
  ON latest.source_id = policy.source_id
 AND latest.entity_name = policy.entity_name
 AND latest.latest_rank = 1
LEFT JOIN cycling_platform_admin.v_source_execution_success_latest success
  ON success.source_id = policy.source_id AND success.entity_name = policy.entity_name;

CREATE OR REPLACE VIEW cycling_platform_admin.v_publication_success_latest AS
SELECT 'RAW' COLLATE utf8mb4_general_ci publication_name,
       MAX(CASE WHEN phase.phase_status = 'SUCCESS' THEN phase.completed_at END) latest_success_at_utc,
       MAX(phase.started_at) latest_attempt_at_utc,
       SUBSTRING_INDEX(GROUP_CONCAT(phase.phase_status ORDER BY phase.started_at DESC), ',', 1) latest_attempt_status,
       30 warning_after_hours, 48 critical_after_hours,
       'Latest successful daily raw_ingestion phase completion' COLLATE utf8mb4_general_ci timestamp_semantics
FROM cycling_platform_admin.pipeline_phase_run phase
INNER JOIN cycling_platform_admin.pipeline_run pipeline ON pipeline.pipeline_run_id = phase.pipeline_run_id
WHERE phase.phase_name = 'raw_ingestion' AND pipeline.pipeline_name = 'daily-platform'
UNION ALL
SELECT 'SILVER' COLLATE utf8mb4_general_ci, MAX(CASE WHEN phase.phase_status = 'SUCCESS' THEN phase.completed_at END),
       MAX(phase.started_at), SUBSTRING_INDEX(GROUP_CONCAT(phase.phase_status ORDER BY phase.started_at DESC), ',', 1), 30, 48,
       'Latest successful Silver publication gate completion' COLLATE utf8mb4_general_ci
FROM cycling_platform_admin.pipeline_phase_run phase
INNER JOIN cycling_platform_admin.pipeline_run pipeline ON pipeline.pipeline_run_id = phase.pipeline_run_id
WHERE phase.phase_name = 'silver_publication_checks' AND pipeline.pipeline_name = 'daily-platform'
UNION ALL
SELECT 'GOLD' COLLATE utf8mb4_general_ci, MAX(CASE WHEN phase.phase_status = 'SUCCESS' THEN phase.completed_at END),
       MAX(phase.started_at), SUBSTRING_INDEX(GROUP_CONCAT(phase.phase_status ORDER BY phase.started_at DESC), ',', 1), 30, 48,
       'Latest successful Gold publication gate completion' COLLATE utf8mb4_general_ci
FROM cycling_platform_admin.pipeline_phase_run phase
INNER JOIN cycling_platform_admin.pipeline_run pipeline ON pipeline.pipeline_run_id = phase.pipeline_run_id
WHERE phase.phase_name = 'gold_publication_checks' AND pipeline.pipeline_name = 'daily-platform'
UNION ALL
SELECT 'DEEP_VALIDATION' COLLATE utf8mb4_general_ci, MAX(CASE WHEN run_status = 'SUCCESS' THEN completed_at END),
       MAX(started_at), SUBSTRING_INDEX(GROUP_CONCAT(run_status ORDER BY started_at DESC), ',', 1), 48, 72,
       'Latest successful DEEP validation execution completion' COLLATE utf8mb4_general_ci
FROM cycling_platform_admin.validation_run WHERE validation_scope = 'DEEP';

CREATE OR REPLACE VIEW cycling_platform_admin.v_publication_dependency_latest AS
SELECT publication.publication_name, publication.latest_success_at_utc,
       publication.latest_attempt_at_utc, publication.latest_attempt_status,
       publication.warning_after_hours, publication.critical_after_hours,
       publication.timestamp_semantics,
       upstream.latest_success_at_utc AS upstream_success_at_utc
FROM cycling_platform_admin.v_publication_success_latest publication
LEFT JOIN cycling_platform_admin.v_publication_success_latest upstream
  ON upstream.publication_name = CASE publication.publication_name
       WHEN 'SILVER' THEN 'RAW'
       WHEN 'GOLD' THEN 'SILVER'
       ELSE NULL
     END;

CREATE OR REPLACE VIEW cycling_platform_admin.v_publication_freshness_latest AS
SELECT publication_name, latest_success_at_utc,
       latest_attempt_at_utc, latest_attempt_status, upstream_success_at_utc,
       CASE
         WHEN upstream_success_at_utc IS NULL THEN NULL
         WHEN latest_success_at_utc IS NULL OR latest_success_at_utc < upstream_success_at_utc THEN 1
         ELSE 0
       END AS is_behind_upstream,
       TIMESTAMPDIFF(MINUTE, latest_success_at_utc, UTC_TIMESTAMP()) / 60.0 AS age_hours,
       CASE
         WHEN latest_attempt_status IN ('FAILED', 'TIMED_OUT') THEN 'CRITICAL'
         WHEN latest_success_at_utc IS NULL THEN 'UNKNOWN'
         WHEN upstream_success_at_utc IS NOT NULL AND latest_success_at_utc < upstream_success_at_utc THEN 'WARNING'
         WHEN latest_success_at_utc < UTC_TIMESTAMP() - INTERVAL critical_after_hours HOUR THEN 'CRITICAL'
         WHEN latest_success_at_utc < UTC_TIMESTAMP() - INTERVAL warning_after_hours HOUR THEN 'WARNING'
         ELSE 'HEALTHY'
       END COLLATE utf8mb4_general_ci AS health_status,
       timestamp_semantics
FROM cycling_platform_admin.v_publication_dependency_latest;

CREATE OR REPLACE VIEW cycling_platform_admin.v_source_health_latest AS
SELECT source_id, source_name,
       CASE MAX(CASE health_status WHEN 'CRITICAL' THEN 4 WHEN 'WARNING' THEN 3 WHEN 'INFO' THEN 2 WHEN 'UNKNOWN' THEN 1 ELSE 0 END)
         WHEN 4 THEN 'CRITICAL' WHEN 3 THEN 'WARNING' WHEN 2 THEN 'INFO'
         WHEN 1 THEN 'UNKNOWN' ELSE 'HEALTHY'
       END COLLATE utf8mb4_general_ci AS health_status,
       SUM(health_status = 'CRITICAL') AS critical_entity_count,
       SUM(health_status = 'WARNING') AS warning_entity_count,
       SUM(health_status = 'UNKNOWN') AS unknown_entity_count
FROM cycling_platform_admin.v_source_freshness_latest
WHERE entity_requirement = 'REQUIRED'
GROUP BY source_id, source_name;

CREATE OR REPLACE VIEW cycling_platform_admin.v_validation_history AS
SELECT run.validation_run_id, run.pipeline_run_id, run.validation_scope,
       run.run_mode, run.run_status,
       run.started_at AS started_at_utc, run.completed_at AS completed_at_utc,
       run.duration_seconds,
       COUNT(checks.validation_run_check_id) AS check_count,
       SUM(CASE WHEN checks.check_status = 'PASS' THEN 1 ELSE 0 END) AS passed_check_count,
       SUM(CASE WHEN checks.check_status = 'FAIL' THEN 1 ELSE 0 END) AS failed_check_count,
       0 AS skipped_check_count,
       COALESCE(SUM(checks.issue_count), 0) AS issue_count,
       CASE
         WHEN run.run_status IN ('FAILED', 'TIMED_OUT') THEN 'CRITICAL'
         WHEN SUM(CASE WHEN checks.check_status = 'FAIL' THEN 1 ELSE 0 END) > 0 THEN 'CRITICAL'
         WHEN SUM(CASE WHEN checks.severity = 'WARNING' AND checks.issue_count > 0 THEN 1 ELSE 0 END) > 0 THEN 'WARNING'
         WHEN run.run_status = 'SUCCESS' THEN 'HEALTHY'
         ELSE 'INFO'
       END COLLATE utf8mb4_general_ci AS health_status,
       run.error_message
FROM cycling_platform_admin.validation_run run
LEFT JOIN cycling_platform_admin.validation_run_check checks
  ON checks.validation_run_id = run.validation_run_id
GROUP BY run.validation_run_id, run.pipeline_run_id, run.validation_scope,
         run.run_mode, run.run_status, run.started_at, run.completed_at,
         run.duration_seconds, run.error_message;

CREATE OR REPLACE VIEW cycling_platform_admin.v_backup_history AS
SELECT attempt.backup_attempt_id, attempt.backup_host, attempt.source_host,
       attempt.run_prefix, attempt.attempt_status,
       attempt.started_at AS started_at_utc,
       attempt.completed_at AS completed_at_utc, attempt.duration_seconds,
       attempt.complete_set_created, attempt.failure_class,
       attempt.failing_database, attempt.failing_operation,
       attempt.final_attempt_number, attempt.max_attempts,
       attempt.partial_verified_file_count, attempt.failure_summary,
       complete.backup_run_id, complete.completed_at AS recovery_point_at_utc,
       complete.expected_database_count, complete.successful_database_count,
       complete.total_compressed_bytes,
       CASE WHEN complete.backup_run_id IS NULL THEN 0 ELSE 1 END AS is_complete_verified_recovery_point
FROM cycling_platform_admin.backup_attempt attempt
LEFT JOIN cycling_platform_admin.backup_run complete
  ON complete.backup_run_id = attempt.backup_run_id;

CREATE OR REPLACE VIEW cycling_platform_admin.v_backup_health_latest AS
SELECT latest_attempt.backup_attempt_id AS latest_attempt_id,
       latest_attempt.attempt_status AS latest_attempt_status,
       latest_attempt.completed_at AS latest_attempt_completed_at_utc,
       latest_attempt.failure_class AS latest_attempt_failure_class,
       latest_attempt.failing_database AS latest_attempt_failing_database,
       latest_good.backup_run_id AS latest_recovery_point_id,
       latest_good.completed_at AS latest_recovery_point_at_utc,
       TIMESTAMPDIFF(MINUTE, latest_good.completed_at, UTC_TIMESTAMP()) / 60.0 AS recovery_point_age_hours,
       latest_reconciliation.backup_reconciliation_run_id AS latest_reconciliation_id,
       latest_reconciliation.status AS latest_reconciliation_status,
       latest_reconciliation.completed_at AS latest_reconciliation_at_utc,
       COALESCE(latest_reconciliation.missing_file_count, 0) AS missing_file_count,
       COALESCE(latest_reconciliation.incomplete_run_count, 0) AS incomplete_run_count,
       COALESCE(latest_reconciliation.orphan_file_count, 0) AS orphan_file_count,
       COALESCE(latest_reconciliation.unexpected_file_count, 0) AS unexpected_file_count,
       CASE
         WHEN latest_good.backup_run_id IS NULL THEN 'UNKNOWN'
         WHEN latest_good.completed_at < UTC_TIMESTAMP() - INTERVAL 48 HOUR THEN 'CRITICAL'
         WHEN latest_attempt.attempt_status = 'FAILED' AND latest_attempt.started_at > latest_good.completed_at THEN 'WARNING'
         WHEN latest_reconciliation.backup_reconciliation_run_id IS NULL THEN 'UNKNOWN'
         WHEN COALESCE(latest_reconciliation.missing_file_count, 0) > 0 OR COALESCE(latest_reconciliation.incomplete_run_count, 0) > 0 THEN 'CRITICAL'
         WHEN COALESCE(latest_reconciliation.orphan_file_count, 0) > 0 OR COALESCE(latest_reconciliation.unexpected_file_count, 0) > 0 THEN 'WARNING'
         WHEN latest_reconciliation.status <> 'HEALTHY' THEN 'WARNING'
         WHEN latest_good.completed_at < UTC_TIMESTAMP() - INTERVAL 30 HOUR THEN 'WARNING'
         ELSE 'HEALTHY'
       END COLLATE utf8mb4_general_ci AS health_status
FROM cycling_platform_admin.data_source anchor
LEFT JOIN cycling_platform_admin.backup_attempt latest_attempt
  ON latest_attempt.backup_attempt_id = (SELECT MAX(backup_attempt_id) FROM cycling_platform_admin.backup_attempt)
LEFT JOIN cycling_platform_admin.backup_run latest_good
  ON latest_good.backup_run_id = (SELECT MAX(backup_run_id) FROM cycling_platform_admin.backup_run WHERE status = 'SUCCESS')
LEFT JOIN cycling_platform_admin.backup_reconciliation_run latest_reconciliation
  ON latest_reconciliation.backup_reconciliation_run_id = (SELECT MAX(backup_reconciliation_run_id) FROM cycling_platform_admin.backup_reconciliation_run)
WHERE anchor.source_id = (SELECT MIN(source_id) FROM cycling_platform_admin.data_source);

CREATE OR REPLACE VIEW cycling_platform_admin.v_api_request_failure_history AS
SELECT attempt.api_request_attempt_id, endpoint.endpoint_run_id,
       run.pipeline_run_id, endpoint.run_id, source.source_name,
       endpoint.entity_name, attempt.request_sequence, attempt.request_name,
       attempt.source_reference, attempt.attempt_number,
       attempt.retry_decision, attempt.http_status, attempt.failure_class,
       attempt.error_summary, attempt.started_at AS started_at_utc,
       attempt.completed_at AS completed_at_utc, attempt.duration_seconds
FROM cycling_platform_admin.api_request_attempt attempt
INNER JOIN cycling_platform_admin.api_endpoint_run endpoint
  ON endpoint.endpoint_run_id = attempt.endpoint_run_id
INNER JOIN cycling_platform_admin.etl_run run ON run.run_id = endpoint.run_id
INNER JOIN cycling_platform_admin.data_source source ON source.source_id = endpoint.source_id
WHERE attempt.attempt_status = 'FAILED';

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
         CASE WHEN COUNT(*) > 0 THEN 'CRITICAL' ELSE 'HEALTHY' END COLLATE utf8mb4_general_ci,
         COUNT(*), 'Validation scopes whose latest execution did not succeed' COLLATE utf8mb4_general_ci
  FROM cycling_platform_admin.validation_run run
  WHERE run.validation_run_id IN (
    SELECT MAX(latest.validation_run_id) FROM cycling_platform_admin.validation_run latest GROUP BY latest.validation_scope
  ) AND run.run_status <> 'SUCCESS'
  UNION ALL
  SELECT 'backup' COLLATE utf8mb4_general_ci, 'BACKUP' COLLATE utf8mb4_general_ci, health_status,
         CASE WHEN health_status = 'HEALTHY' THEN 0 ELSE 1 END,
         'Latest complete recovery point, physical attempt and retention reconciliation' COLLATE utf8mb4_general_ci
  FROM cycling_platform_admin.v_backup_health_latest;

CREATE OR REPLACE VIEW cycling_platform_admin.v_operational_debt_latest AS
SELECT debt_key, debt_domain, health_status, item_count, summary,
       UTC_TIMESTAMP() AS observed_at_utc
FROM cycling_platform_admin.v_operational_debt_condition_latest;

CREATE OR REPLACE VIEW cycling_platform_admin.v_platform_health_condition_latest AS
SELECT health_status,
       CASE health_status WHEN 'CRITICAL' THEN 4 WHEN 'WARNING' THEN 3 WHEN 'INFO' THEN 2 WHEN 'UNKNOWN' THEN 1 ELSE 0 END severity_rank
FROM cycling_platform_admin.v_operational_debt_latest
UNION ALL
SELECT health_status,
       CASE health_status WHEN 'CRITICAL' THEN 4 WHEN 'WARNING' THEN 3 WHEN 'INFO' THEN 2 WHEN 'UNKNOWN' THEN 1 ELSE 0 END
FROM cycling_platform_admin.v_source_health_latest
UNION ALL
SELECT health_status,
       CASE health_status WHEN 'CRITICAL' THEN 4 WHEN 'WARNING' THEN 3 WHEN 'INFO' THEN 2 WHEN 'UNKNOWN' THEN 1 ELSE 0 END
FROM cycling_platform_admin.v_publication_freshness_latest;

CREATE OR REPLACE VIEW cycling_platform_admin.v_platform_health_latest AS
SELECT UTC_TIMESTAMP() AS observed_at_utc,
       CASE MAX(severity_rank)
         WHEN 4 THEN 'CRITICAL' WHEN 3 THEN 'WARNING' WHEN 2 THEN 'INFO'
         WHEN 1 THEN 'UNKNOWN' ELSE 'HEALTHY'
       END COLLATE utf8mb4_general_ci AS health_status,
       SUM(health_status = 'CRITICAL') AS critical_condition_count,
       SUM(health_status = 'WARNING') AS warning_condition_count,
       SUM(health_status = 'INFO') AS info_condition_count,
       SUM(health_status = 'UNKNOWN') AS unknown_condition_count,
       latest.pipeline_run_id AS latest_pipeline_run_id,
       latest.run_status AS latest_pipeline_status,
       latest.completed_at AS latest_pipeline_completed_at_utc
FROM cycling_platform_admin.v_platform_health_condition_latest conditions
LEFT JOIN cycling_platform_admin.pipeline_run latest
  ON latest.pipeline_run_id = (
    SELECT MAX(pipeline_run_id)
    FROM cycling_platform_admin.pipeline_run
    WHERE pipeline_name = 'daily-platform'
  )
GROUP BY latest.pipeline_run_id, latest.run_status, latest.completed_at;

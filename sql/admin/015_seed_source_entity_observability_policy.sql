INSERT INTO cycling_platform_admin.source_entity_observability_policy (
    source_id, entity_name, entity_requirement, execution_freshness_enabled,
    warning_after_hours, critical_after_hours, source_data_timestamp_semantics
)
SELECT source_id, policy.entity_name, policy.entity_requirement,
       policy.execution_freshness_enabled, policy.warning_after_hours,
       policy.critical_after_hours, policy.source_data_timestamp_semantics
FROM cycling_platform_admin.data_source source
INNER JOIN (
    SELECT 'strava' source_name, 'activities' entity_name, 'REQUIRED' entity_requirement, 1 execution_freshness_enabled, 30 warning_after_hours, 48 critical_after_hours, 'Maximum source activity start_datetime_utc' source_data_timestamp_semantics
    UNION ALL SELECT 'strava', 'gear', 'OPTIONAL', 1, 30, 48, 'Maximum source_observed_at from gear observations'
    UNION ALL SELECT 'strava', 'activity_details', 'OPTIONAL', 0, 30, 48, 'Maximum retrieved_at for source activity details'
    UNION ALL SELECT 'strava', 'activity_streams', 'OPTIONAL', 0, 30, 48, 'Maximum retrieved_at for source activity streams'
    UNION ALL SELECT 'strava', 'activity_laps', 'OPTIONAL', 0, 30, 48, 'Maximum retrieved_at for source activity laps'
    UNION ALL SELECT 'google_health', 'google_health_heart_rate', 'REQUIRED', 1, 30, 48, 'Maximum source activity_date represented at UTC midnight'
    UNION ALL SELECT 'google_health', 'google_health_sleep_logs', 'REQUIRED', 1, 30, 48, 'Maximum source sleep end_physical_time, falling back to start_physical_time'
    UNION ALL SELECT 'google_health', 'google_health_exercise', 'OPTIONAL', 1, 30, 48, 'Maximum source interval_end_time, falling back to interval_start_time'
    UNION ALL SELECT 'google_health', 'google_health_daily_resting_heart_rate', 'REQUIRED', 1, 30, 48, 'Maximum source activity_date represented at UTC midnight'
    UNION ALL SELECT 'google_health', 'google_health_daily_heart_rate_variability', 'REQUIRED', 1, 30, 48, 'Maximum source activity_date represented at UTC midnight'
    UNION ALL SELECT 'google_health', 'google_health_daily_respiratory_rate', 'REQUIRED', 1, 30, 48, 'Maximum source activity_date represented at UTC midnight'
) policy ON policy.source_name = source.source_name
ON DUPLICATE KEY UPDATE
    entity_requirement = VALUES(entity_requirement),
    execution_freshness_enabled = VALUES(execution_freshness_enabled),
    warning_after_hours = VALUES(warning_after_hours),
    critical_after_hours = VALUES(critical_after_hours),
    source_data_timestamp_semantics = VALUES(source_data_timestamp_semantics);

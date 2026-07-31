-- Canonical platform encoding for deterministic upgrades and restores.
-- MariaDB DDL auto-commits. The migration runner records this file only after
-- every statement succeeds.

ALTER DATABASE cycling_platform_admin
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_general_ci;

ALTER DATABASE cycling_platform_raw
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_general_ci;

ALTER DATABASE cycling_platform_stage
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_general_ci;

ALTER DATABASE cycling_platform_silver
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_general_ci;

ALTER DATABASE cycling_platform_gold
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_admin.schema_migration
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_admin.data_source
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_admin.etl_run
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_admin.etl_run_entity
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_admin.etl_request_log
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_admin.api_endpoint_run
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_admin.transform_run
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_admin.transform_run_batch
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_admin.validation_run
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_admin.validation_run_check
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_admin.notification_outbox
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_admin.power_source_classification
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_admin.activity_power_overrides
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_admin.backup_run
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_admin.backup_run_file
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_admin.backup_reconciliation_run
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_raw.activities
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_raw.activity_streams
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_raw.activity_details
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_raw.activity_laps
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_raw.gear_observations
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_raw.gear_resolution_attempts
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_raw.google_health_heart_rate_responses
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_raw.google_health_sleep_logs
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_raw.google_health_daily_resting_heart_rate
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_raw.google_health_daily_heart_rate_variability
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_raw.google_health_daily_respiratory_rate
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_stage.activity_streams_build
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_silver.activities
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_silver.activity_streams
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_silver.gear
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_gold.activity_best_efforts
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_gold.activity_achievements
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

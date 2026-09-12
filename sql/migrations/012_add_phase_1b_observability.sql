ALTER TABLE cycling_platform_admin.transform_run
    ADD COLUMN IF NOT EXISTS setup_seconds DOUBLE NULL AFTER max_batch_expected_rows,
    ADD COLUMN IF NOT EXISTS discovery_seconds DOUBLE NULL AFTER setup_seconds,
    ADD COLUMN IF NOT EXISTS source_preparation_seconds DOUBLE NULL AFTER discovery_seconds,
    ADD COLUMN IF NOT EXISTS processing_seconds DOUBLE NULL AFTER source_preparation_seconds,
    ADD COLUMN IF NOT EXISTS finalisation_seconds DOUBLE NULL AFTER processing_seconds,
    ADD COLUMN IF NOT EXISTS discovery_mode VARCHAR(30) NULL AFTER finalisation_seconds,
    ADD COLUMN IF NOT EXISTS candidate_mode VARCHAR(30) NULL AFTER discovery_mode,
    ADD COLUMN IF NOT EXISTS invalidation_action VARCHAR(40) NULL AFTER candidate_mode,
    ADD COLUMN IF NOT EXISTS invalidation_reason VARCHAR(100) NULL AFTER invalidation_action,
    ADD COLUMN IF NOT EXISTS dependency_start_date DATE NULL AFTER invalidation_reason;

ALTER TABLE cycling_platform_admin.pipeline_phase_run
    ADD COLUMN IF NOT EXISTS notifications_queued INT NULL AFTER failure_summary,
    ADD COLUMN IF NOT EXISTS notifications_attempted INT NULL AFTER notifications_queued,
    ADD COLUMN IF NOT EXISTS notifications_sent INT NULL AFTER notifications_attempted,
    ADD COLUMN IF NOT EXISTS notifications_failed INT NULL AFTER notifications_sent,
    ADD COLUMN IF NOT EXISTS notifications_deferred INT NULL AFTER notifications_failed;

ALTER TABLE cycling_platform_admin.etl_run_entity
    ADD COLUMN IF NOT EXISTS source_id INT NULL AFTER run_id,
    ADD CONSTRAINT fk_etl_run_entity_source
        FOREIGN KEY IF NOT EXISTS (source_id)
        REFERENCES cycling_platform_admin.data_source (source_id);

ALTER TABLE cycling_platform_admin.transform_run_metric
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_admin.api_request_attempt
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

-- New Admin execution-ledger tables are created before migrations during
-- bootstrap. Explicit conversion keeps restored/manual copies deterministic.
ALTER TABLE cycling_platform_admin.pipeline_run
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_admin.pipeline_phase_run
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_admin.backup_attempt
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_admin.etl_run
    ADD COLUMN IF NOT EXISTS pipeline_run_id BIGINT NULL AFTER run_id,
    ADD CONSTRAINT fk_etl_run_pipeline
        FOREIGN KEY IF NOT EXISTS (pipeline_run_id)
        REFERENCES cycling_platform_admin.pipeline_run (pipeline_run_id);

ALTER TABLE cycling_platform_admin.transform_run
    ADD COLUMN IF NOT EXISTS pipeline_run_id BIGINT NULL AFTER transform_run_id,
    ADD CONSTRAINT fk_transform_run_pipeline
        FOREIGN KEY IF NOT EXISTS (pipeline_run_id)
        REFERENCES cycling_platform_admin.pipeline_run (pipeline_run_id);

ALTER TABLE cycling_platform_admin.validation_run
    ADD COLUMN IF NOT EXISTS pipeline_run_id BIGINT NULL AFTER validation_run_id,
    ADD CONSTRAINT fk_validation_run_pipeline
        FOREIGN KEY IF NOT EXISTS (pipeline_run_id)
        REFERENCES cycling_platform_admin.pipeline_run (pipeline_run_id);

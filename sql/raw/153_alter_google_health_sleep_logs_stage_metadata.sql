-- Backward-compatible promoted metadata for source-reported Google Health sleep stages.
-- The complete sleep_log_payload remains the Raw source of truth.

ALTER TABLE cycling_platform_raw.google_health_sleep_logs
    ADD COLUMN IF NOT EXISTS sleep_type VARCHAR(100) NULL
        AFTER end_civil_date,
    ADD COLUMN IF NOT EXISTS stages_status VARCHAR(100) NULL
        AFTER sleep_type,
    ADD COLUMN IF NOT EXISTS is_processed TINYINT(1) NULL
        AFTER stages_status,
    ADD COLUMN IF NOT EXISTS is_nap TINYINT(1) NULL
        AFTER is_processed,
    ADD COLUMN IF NOT EXISTS is_manually_edited TINYINT(1) NULL
        AFTER is_nap,
    ADD COLUMN IF NOT EXISTS has_sleep_stages TINYINT(1) NULL
        AFTER is_manually_edited,
    ADD COLUMN IF NOT EXISTS sleep_stage_count INT NULL
        AFTER has_sleep_stages,
    ADD COLUMN IF NOT EXISTS has_sleep_summary TINYINT(1) NULL
        AFTER sleep_stage_count;

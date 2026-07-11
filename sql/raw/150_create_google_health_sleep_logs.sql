-- Grain: one row per Google Health sleep log/session
-- Business key: sleep_log_key
-- Load strategy: UPSERT
-- Refresh strategy: date-window ingestion
-- Source of truth: sleep_log_payload

CREATE TABLE IF NOT EXISTS cycling_platform_raw.google_health_sleep_logs (

    sleep_log_key CHAR(64) NOT NULL,

    source_log_id VARCHAR(500) NULL,

    google_user_id VARCHAR(100) NOT NULL,

    run_id BIGINT NOT NULL,

    source_id INT NOT NULL,

    retrieved_at DATETIME NOT NULL,

    source_name TEXT NULL,

    start_physical_time DATETIME NULL,

    end_physical_time DATETIME NULL,

    start_utc_offset VARCHAR(32) NULL,

    end_utc_offset VARCHAR(32) NULL,

    start_civil_date DATE NULL,

    end_civil_date DATE NULL,

    sleep_type VARCHAR(100) NULL,

    stages_status VARCHAR(100) NULL,

    is_processed TINYINT(1) NULL,

    is_nap TINYINT(1) NULL,

    is_manually_edited TINYINT(1) NULL,

    has_sleep_stages TINYINT(1) NULL,

    sleep_stage_count INT NULL,

    has_sleep_summary TINYINT(1) NULL,

    sleep_log_payload JSON NOT NULL,

    created_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (sleep_log_key),

    KEY idx_google_health_sleep_start_time (start_physical_time),

    KEY idx_google_health_sleep_run_id (run_id),

    KEY idx_google_health_sleep_source_id (source_id),

    KEY idx_google_health_sleep_retrieved_at (retrieved_at),

    CONSTRAINT fk_google_health_sleep_logs_run_id
        FOREIGN KEY (run_id)
        REFERENCES cycling_platform_admin.etl_run (run_id),

    CONSTRAINT fk_google_health_sleep_logs_source_id
        FOREIGN KEY (source_id)
        REFERENCES cycling_platform_admin.data_source (source_id)

);

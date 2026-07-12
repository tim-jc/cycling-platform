-- Grain: one row per Google Health daily resting heart-rate source data point
-- Business key: daily_resting_heart_rate_key
-- Load strategy: UPSERT
-- Refresh strategy: date-window ingestion
-- Source of truth: daily_resting_heart_rate_payload

CREATE TABLE IF NOT EXISTS cycling_platform_raw.google_health_daily_resting_heart_rate (

    daily_resting_heart_rate_key CHAR(64) NOT NULL,

    source_id INT NOT NULL,

    google_health_user_id VARCHAR(100) NOT NULL,

    source_data_point_id VARCHAR(500) NULL,

    activity_date DATE NOT NULL,

    resting_heart_rate_bpm DECIMAL(6, 2) NULL,

    calculation_method VARCHAR(100) NULL,

    source_name TEXT NULL,

    run_id BIGINT NOT NULL,

    retrieved_at DATETIME NOT NULL,

    daily_resting_heart_rate_payload JSON NOT NULL,

    created_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (daily_resting_heart_rate_key),

    KEY idx_google_health_rhr_activity_date (activity_date),

    KEY idx_google_health_rhr_run_id (run_id),

    KEY idx_google_health_rhr_retrieved_at (retrieved_at),

    KEY idx_google_health_rhr_source_id (source_id),

    CONSTRAINT fk_google_health_rhr_run_id
        FOREIGN KEY (run_id)
        REFERENCES cycling_platform_admin.etl_run (run_id),

    CONSTRAINT fk_google_health_rhr_source_id
        FOREIGN KEY (source_id)
        REFERENCES cycling_platform_admin.data_source (source_id)

);

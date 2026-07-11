-- Grain: one row per Google Health daily heart-rate variability source data point
-- Business key: daily_heart_rate_variability_key
-- Load strategy: UPSERT
-- Refresh strategy: date-window ingestion
-- Source of truth: daily_heart_rate_variability_payload

CREATE TABLE IF NOT EXISTS cycling_platform_raw.google_health_daily_heart_rate_variability (

    daily_heart_rate_variability_key CHAR(64) NOT NULL,

    source_id INT NOT NULL,

    google_health_user_id VARCHAR(100) NOT NULL,

    source_data_point_id VARCHAR(500) NULL,

    activity_date DATE NOT NULL,

    average_hrv_milliseconds DECIMAL(10, 3) NULL,

    deep_sleep_rmssd_milliseconds DECIMAL(10, 3) NULL,

    non_rem_heart_rate_bpm DECIMAL(6, 2) NULL,

    entropy DECIMAL(10, 3) NULL,

    source_name TEXT NULL,

    run_id BIGINT NOT NULL,

    retrieved_at DATETIME NOT NULL,

    daily_heart_rate_variability_payload JSON NOT NULL,

    created_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (daily_heart_rate_variability_key),

    KEY idx_google_health_daily_hrv_activity_date (activity_date),

    KEY idx_google_health_daily_hrv_run_id (run_id),

    KEY idx_google_health_daily_hrv_retrieved_at (retrieved_at),

    KEY idx_google_health_daily_hrv_source_id (source_id),

    CONSTRAINT fk_google_health_daily_hrv_run_id
        FOREIGN KEY (run_id)
        REFERENCES cycling_platform_admin.etl_run (run_id),

    CONSTRAINT fk_google_health_daily_hrv_source_id
        FOREIGN KEY (source_id)
        REFERENCES cycling_platform_admin.data_source (source_id)

);

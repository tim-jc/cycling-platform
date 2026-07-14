-- Grain: one row per Google Health daily respiratory-rate source data point
-- Business key: daily_respiratory_rate_key
-- Load strategy: UPSERT
-- Refresh strategy: date-window ingestion
-- Source of truth: daily_respiratory_rate_payload

CREATE TABLE IF NOT EXISTS cycling_platform_raw.google_health_daily_respiratory_rate (

    daily_respiratory_rate_key CHAR(64) NOT NULL,

    source_id INT NOT NULL,

    google_health_user_id VARCHAR(100) NOT NULL,

    source_data_point_id VARCHAR(500) NULL,

    activity_date DATE NOT NULL,

    respiratory_rate_brpm DECIMAL(6, 2) NULL,

    source_name TEXT NULL,

    source_ecosystem VARCHAR(100) NULL,

    source_platform VARCHAR(100) NULL,

    source_recording_method VARCHAR(100) NULL,

    source_device_manufacturer VARCHAR(255) NULL,

    source_device_model VARCHAR(255) NULL,

    run_id BIGINT NOT NULL,

    retrieved_at DATETIME NOT NULL,

    daily_respiratory_rate_payload JSON NOT NULL,

    created_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (daily_respiratory_rate_key),

    KEY idx_google_health_daily_rr_activity_date (activity_date),

    KEY idx_google_health_daily_rr_run_id (run_id),

    KEY idx_google_health_daily_rr_retrieved_at (retrieved_at),

    KEY idx_google_health_daily_rr_source_id (source_id),

    KEY idx_google_health_daily_rr_source_ecosystem (
        source_ecosystem,
        activity_date
    ),

    KEY idx_google_health_daily_rr_source_platform (
        source_platform,
        activity_date
    ),

    CONSTRAINT fk_google_health_daily_rr_run_id
        FOREIGN KEY (run_id)
        REFERENCES cycling_platform_admin.etl_run (run_id),

    CONSTRAINT fk_google_health_daily_rr_source_id
        FOREIGN KEY (source_id)
        REFERENCES cycling_platform_admin.data_source (source_id)

);

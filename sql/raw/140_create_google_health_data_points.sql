-- Grain: one row per Google Health data point
-- Business key: data_point_key
-- Load strategy: UPSERT
-- Refresh strategy: date-window ingestion
-- Source of truth: data_point_payload

CREATE TABLE IF NOT EXISTS cycling_platform_raw.google_health_data_points (

    data_point_key CHAR(64) NOT NULL,

    data_type VARCHAR(100) NOT NULL,

    google_user_id VARCHAR(100) NOT NULL,

    run_id BIGINT NOT NULL,

    source_id INT NOT NULL,

    retrieved_at DATETIME NOT NULL,

    source_name TEXT NULL,

    sample_physical_time DATETIME NULL,

    sample_utc_offset VARCHAR(32) NULL,

    sample_civil_date DATE NULL,

    value_numeric DECIMAL(18,6) NULL,

    value_name VARCHAR(100) NULL,

    data_point_name TEXT NULL,

    data_point_payload JSON NOT NULL,

    created_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (data_point_key),

    KEY idx_google_health_type_time (
        data_type,
        sample_physical_time
    ),

    KEY idx_google_health_run_id (run_id),

    KEY idx_google_health_source_id (source_id),

    KEY idx_google_health_retrieved_at (retrieved_at),

    CONSTRAINT fk_google_health_data_points_run_id
        FOREIGN KEY (run_id)
        REFERENCES cycling_platform_admin.etl_run (run_id),

    CONSTRAINT fk_google_health_data_points_source_id
        FOREIGN KEY (source_id)
        REFERENCES cycling_platform_admin.data_source (source_id)

);

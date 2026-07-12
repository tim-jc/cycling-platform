-- Grain: one row per Google/Fitbit heart-rate API response per user/date/detail level
-- Business key: source_id + fitbit_user_id + activity_date + detail_level
-- Load strategy: UPSERT
-- Refresh strategy: date-window ingestion
-- Source of truth: heart_rate_payload

CREATE TABLE IF NOT EXISTS cycling_platform_raw.google_health_heart_rate_responses (

    source_id INT NOT NULL,

    fitbit_user_id VARCHAR(100) NOT NULL,

    activity_date DATE NOT NULL,

    detail_level VARCHAR(100) NOT NULL,

    run_id BIGINT NOT NULL,

    retrieved_at DATETIME NOT NULL,

    dataset_interval INT NULL,

    heart_rate_payload JSON NOT NULL,

    created_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (
        source_id,
        fitbit_user_id,
        activity_date,
        detail_level
    ),

    KEY idx_google_health_heart_rate_run_id (run_id),

    KEY idx_google_health_heart_rate_retrieved_at (retrieved_at),

    CONSTRAINT fk_google_health_heart_rate_responses_run_id
        FOREIGN KEY (run_id)
        REFERENCES cycling_platform_admin.etl_run (run_id),

    CONSTRAINT fk_google_health_heart_rate_responses_source_id
        FOREIGN KEY (source_id)
        REFERENCES cycling_platform_admin.data_source (source_id)

);

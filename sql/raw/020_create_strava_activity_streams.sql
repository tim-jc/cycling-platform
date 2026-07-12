-- Grain: one row per Strava activity and stream type
-- Business key: activity_id + stream_type
-- Load strategy: UPSERT
-- Refresh strategy: rolling window + hygiene runs
-- Source of truth: stream_payload

CREATE TABLE IF NOT EXISTS cycling_platform_raw.activity_streams (

    activity_id BIGINT NOT NULL,

    stream_type VARCHAR(50) NOT NULL,

    run_id BIGINT NOT NULL,

    source_id INT NOT NULL,

    retrieved_at DATETIME NOT NULL,

    series_type VARCHAR(50) NULL,

    original_size INT NULL,

    resolution VARCHAR(50) NULL,

    stream_payload JSON NOT NULL,

    created_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (activity_id, stream_type),

    KEY idx_activity_streams_run_id (run_id),

    KEY idx_activity_streams_source_id (source_id),

    KEY idx_activity_streams_retrieved_at (retrieved_at),

    CONSTRAINT fk_activity_streams_activity_id
        FOREIGN KEY (activity_id)
        REFERENCES cycling_platform_raw.activities (activity_id),

    CONSTRAINT fk_activity_streams_run_id
        FOREIGN KEY (run_id)
        REFERENCES cycling_platform_admin.etl_run (run_id),

    CONSTRAINT fk_activity_streams_source_id
        FOREIGN KEY (source_id)
        REFERENCES cycling_platform_admin.data_source (source_id)

);

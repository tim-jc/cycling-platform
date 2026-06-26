-- Grain: one row per Strava activity lap
-- Business key: activity_id + lap_index
-- Load strategy: UPSERT
-- Refresh strategy: state-driven child-entity ingestion
-- Source of truth: lap_payload

CREATE TABLE IF NOT EXISTS cycling_platform_raw.activity_laps (

    activity_id BIGINT NOT NULL,

    lap_index INT NOT NULL,

    run_id BIGINT NOT NULL,

    source_id INT NOT NULL,

    retrieved_at DATETIME NOT NULL,

    lap_payload JSON NOT NULL,

    created_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (activity_id, lap_index),

    KEY idx_activity_laps_run_id (run_id),

    KEY idx_activity_laps_source_id (source_id),

    KEY idx_activity_laps_retrieved_at (retrieved_at),

    CONSTRAINT fk_activity_laps_activity_id
        FOREIGN KEY (activity_id)
        REFERENCES cycling_platform_raw.activities (activity_id),

    CONSTRAINT fk_activity_laps_run_id
        FOREIGN KEY (run_id)
        REFERENCES cycling_platform_admin.etl_run (run_id),

    CONSTRAINT fk_activity_laps_source_id
        FOREIGN KEY (source_id)
        REFERENCES cycling_platform_admin.data_source (source_id)

);

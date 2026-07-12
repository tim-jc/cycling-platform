-- Grain: one row per Strava activity
-- Business key: activity_id
-- Load strategy: UPSERT
-- Refresh strategy: rolling window + hygiene runs
-- Source of truth: details_payload

CREATE TABLE IF NOT EXISTS cycling_platform_raw.activity_details (

    activity_id BIGINT NOT NULL,

    run_id BIGINT NOT NULL,

    source_id INT NOT NULL,

    retrieved_at DATETIME NOT NULL,

    details_payload JSON NOT NULL,

    created_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (activity_id),

    KEY idx_activity_details_run_id (run_id),

    KEY idx_activity_details_source_id (source_id),

    KEY idx_activity_details_retrieved_at (retrieved_at),

    CONSTRAINT fk_activity_details_activity_id
        FOREIGN KEY (activity_id)
        REFERENCES cycling_platform_raw.activities (activity_id),

    CONSTRAINT fk_activity_details_run_id
        FOREIGN KEY (run_id)
        REFERENCES cycling_platform_admin.etl_run (run_id),

    CONSTRAINT fk_activity_details_source_id
        FOREIGN KEY (source_id)
        REFERENCES cycling_platform_admin.data_source (source_id)

);

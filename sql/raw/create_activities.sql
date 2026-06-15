-- Grain: one row per Strava activity
-- Business key: activity_id
-- Load strategy: UPSERT
-- Refresh strategy: rolling window + hygiene runs
-- Source of truth: raw_payload

CREATE TABLE IF NOT EXISTS raw.activities (

    activity_id BIGINT PRIMARY KEY,

    run_id BIGINT NOT NULL,

    source_id INT NOT NULL,

    retrieved_at DATETIME NOT NULL,

    raw_payload JSON NOT NULL,

    activity_name VARCHAR(255),

    sport_type VARCHAR(50),

    start_datetime_utc DATETIME,

    timezone_name VARCHAR(100),

    distance_metres DOUBLE,

    moving_time_seconds INT,

    elapsed_time_seconds INT,

    elevation_gain_metres DOUBLE,

    average_speed_metres_per_second DOUBLE,

    max_speed_metres_per_second DOUBLE,

    average_heartrate_bpm DOUBLE NULL,

    max_heartrate_bpm DOUBLE NULL,

    average_power_watts DOUBLE NULL,

    weighted_average_power_watts DOUBLE NULL,

    energy_kilojoules DOUBLE NULL,

    gear_id VARCHAR(50) NULL,

    is_trainer_activity BOOLEAN,

    is_commute_activity BOOLEAN,

    is_manual_activity BOOLEAN,

    is_private_activity BOOLEAN,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    updated_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT fk_activities_run
        FOREIGN KEY (run_id)
        REFERENCES admin.etl_run (run_id),

    CONSTRAINT fk_activities_source
        FOREIGN KEY (source_id)
        REFERENCES admin.data_source (source_id)

);
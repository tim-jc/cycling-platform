-- Grain: one row per Strava activity
-- Business key: activity_id
-- Load strategy: UPSERT
-- Refresh strategy: rolling window + hygiene runs
-- Source of truth: raw_payload

CREATE TABLE IF NOT EXISTS cycling_platform_raw.activities (

    activity_id BIGINT PRIMARY KEY,

    run_id BIGINT NOT NULL,

    source_id INT NOT NULL,

    retrieved_at DATETIME NOT NULL,

    raw_payload JSON NOT NULL,
    
    athlete_id BIGINT NULL,

    activity_name VARCHAR(255),

    sport_type VARCHAR(50),

    start_datetime_utc DATETIME,

    start_datetime_local DATETIME,

    timezone_name VARCHAR(100),

    distance_metres DOUBLE,

    moving_time_seconds INT,

    elapsed_time_seconds INT,

    elevation_gain_metres DOUBLE,

    average_speed_metres_per_second DOUBLE,

    average_cadence_rpm DOUBLE NULL,

    average_heartrate_bpm DOUBLE NULL,

    average_power_watts DOUBLE NULL,

    weighted_average_power_watts DOUBLE NULL,

    energy_kilojoules DOUBLE NULL,

    gear_id VARCHAR(50) NULL,

    is_device_watts BOOLEAN,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    stream_status VARCHAR(20) NOT NULL DEFAULT 'PENDING',

    stream_attempted_at DATETIME NULL,

    details_status VARCHAR(20) NOT NULL DEFAULT 'PENDING',

    details_attempted_at DATETIME NULL,

    updated_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT fk_activities_run
        FOREIGN KEY (run_id)
        REFERENCES cycling_platform_admin.etl_run (run_id),

    CONSTRAINT fk_activities_source
        FOREIGN KEY (source_id)
        REFERENCES cycling_platform_admin.data_source (source_id),

    KEY idx_activities_start_datetime_utc (start_datetime_utc),

    KEY idx_activities_sport_type (sport_type),

    KEY idx_activities_gear_id (gear_id)

);
-- Grain: one current source-reported Strava lap per lap_id
-- Business key: lap_id; additional uniqueness: activity_id + lap_index
-- Load strategy: atomic full or activity-scoped replacement from Raw
-- Source of truth: cycling_platform_raw.activity_laps.lap_payload

CREATE TABLE IF NOT EXISTS cycling_platform_silver.activity_laps (

    lap_id BIGINT NOT NULL,

    activity_id BIGINT NOT NULL,

    lap_index INT NOT NULL,

    source_id INT NOT NULL,

    lap_name VARCHAR(255) NULL,

    start_datetime_utc DATETIME NULL,

    start_datetime_local DATETIME NULL,

    elapsed_time_seconds INT NULL,

    moving_time_seconds INT NULL,

    distance_metres DOUBLE NULL,

    start_sample_index INT NULL,

    end_sample_index INT NULL,

    average_speed_metres_per_second DOUBLE NULL,

    average_cadence_rpm DOUBLE NULL,

    average_power_watts DOUBLE NULL,

    average_heartrate_bpm DOUBLE NULL,

    maximum_heartrate_bpm DOUBLE NULL,

    elevation_gain_metres DOUBLE NULL,

    is_device_watts BOOLEAN NULL,

    raw_run_id BIGINT NOT NULL,

    raw_retrieved_at DATETIME NOT NULL,

    raw_payload_hash CHAR(64) NOT NULL,

    transform_version VARCHAR(50) NOT NULL,

    transformed_at DATETIME NOT NULL,

    PRIMARY KEY (lap_id),

    UNIQUE KEY uq_silver_activity_laps_activity_index (activity_id, lap_index),

    CONSTRAINT chk_silver_activity_laps_lap_index
        CHECK (lap_index >= 0),

    CONSTRAINT chk_silver_activity_laps_elapsed_time
        CHECK (elapsed_time_seconds IS NULL OR elapsed_time_seconds >= 0),

    CONSTRAINT chk_silver_activity_laps_moving_time
        CHECK (moving_time_seconds IS NULL OR moving_time_seconds >= 0),

    CONSTRAINT chk_silver_activity_laps_distance
        CHECK (distance_metres IS NULL OR distance_metres >= 0),

    CONSTRAINT chk_silver_activity_laps_sample_indices
        CHECK (
            (start_sample_index IS NULL OR start_sample_index >= 0)
            AND (end_sample_index IS NULL OR end_sample_index >= 0)
            AND (
                start_sample_index IS NULL
                OR end_sample_index IS NULL
                OR start_sample_index <= end_sample_index
            )
        )

) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_general_ci;

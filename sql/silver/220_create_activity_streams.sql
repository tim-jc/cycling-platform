-- Grain: one row per Strava activity stream sample
-- Business key: activity_id + sample_index
-- Load strategy: rebuild from raw
-- Source of truth: cycling_platform_raw.activity_streams.stream_payload

CREATE TABLE IF NOT EXISTS cycling_platform_silver.activity_streams (

    activity_id BIGINT NOT NULL,

    sample_index INT NOT NULL,

    time_seconds INT NULL,

    distance_metres DOUBLE NULL,

    latitude DOUBLE NULL,

    longitude DOUBLE NULL,

    altitude_metres DOUBLE NULL,

    velocity_smooth_metres_per_second DOUBLE NULL,

    heartrate_bpm INT NULL,

    cadence_rpm INT NULL,

    watts INT NULL,

    temperature_celsius INT NULL,

    is_moving BOOLEAN NULL,

    grade_smooth_percent DOUBLE NULL,

    raw_stream_count INT NOT NULL,

    raw_max_original_size INT NOT NULL,

    raw_stream_retrieved_at DATETIME NOT NULL,

    transformed_at DATETIME NOT NULL,

    PRIMARY KEY (activity_id, sample_index),

    KEY idx_silver_activity_streams_time_seconds (time_seconds),

    KEY idx_silver_activity_streams_distance_metres (distance_metres)

);

-- Operational staging table for large silver activity stream rebuilds.
-- Not a data product. Rows are owned by run_id and are safe to delete.

CREATE TABLE IF NOT EXISTS cycling_platform_stage.activity_streams_build (

    run_id BIGINT NOT NULL,

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

    staged_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (run_id, activity_id, sample_index),

    CONSTRAINT fk_stage_activity_streams_build_run
        FOREIGN KEY (run_id)
        REFERENCES cycling_platform_admin.etl_run (run_id)

);

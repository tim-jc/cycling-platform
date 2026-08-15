-- Grain: one row per distinct Google Health Exercise source payload observation
-- Business key: exercise_observation_key (user + source data-point id + payload)
-- Load strategy: append new observations; identical observations are unchanged
-- Refresh strategy: bounded interval-window ingestion
-- Source of truth: exercise_payload

CREATE TABLE IF NOT EXISTS cycling_platform_raw.google_health_exercise (

    exercise_observation_key CHAR(64) NOT NULL,

    source_id INT NOT NULL,

    google_health_user_id VARCHAR(100) NOT NULL,

    source_data_point_id VARCHAR(500) NOT NULL,

    exercise_type VARCHAR(150) NULL,

    display_name VARCHAR(500) NULL,

    interval_start_time DATETIME NULL,

    interval_end_time DATETIME NULL,

    start_utc_offset VARCHAR(32) NULL,

    end_utc_offset VARCHAR(32) NULL,

    source_update_time DATETIME NULL,

    source_name TEXT NULL,

    source_ecosystem VARCHAR(100) NULL,

    source_platform VARCHAR(100) NULL,

    source_recording_method VARCHAR(100) NULL,

    source_device_manufacturer VARCHAR(255) NULL,

    source_device_model VARCHAR(255) NULL,

    run_id BIGINT NOT NULL,

    retrieved_at DATETIME NOT NULL,

    exercise_payload JSON NOT NULL,

    created_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (exercise_observation_key),

    KEY idx_google_health_exercise_source_record (
        google_health_user_id,
        source_data_point_id
    ),

    KEY idx_google_health_exercise_interval_start (interval_start_time),

    KEY idx_google_health_exercise_source_update (source_update_time),

    KEY idx_google_health_exercise_run_id (run_id),

    KEY idx_google_health_exercise_source_id (source_id),

    KEY idx_google_health_exercise_ecosystem (
        source_ecosystem,
        interval_start_time
    ),

    CONSTRAINT fk_google_health_exercise_run_id
        FOREIGN KEY (run_id)
        REFERENCES cycling_platform_admin.etl_run (run_id),

    CONSTRAINT fk_google_health_exercise_source_id
        FOREIGN KEY (source_id)
        REFERENCES cycling_platform_admin.data_source (source_id)

) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_general_ci;

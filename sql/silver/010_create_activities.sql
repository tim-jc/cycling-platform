-- Grain: one row per Strava activity
-- Business key: activity_id
-- Load strategy: rebuild from raw
-- Source of truth: cycling_platform_raw.activities + activity_details

CREATE TABLE IF NOT EXISTS cycling_platform_silver.activities (

    activity_id BIGINT PRIMARY KEY,

    athlete_id BIGINT NULL,

    source_id INT NOT NULL,

    gear_id VARCHAR(50) NULL,

    activity_name VARCHAR(255),

    sport_type VARCHAR(50),

    activity_type VARCHAR(50),

    timezone_name VARCHAR(100),

    start_datetime_utc DATETIME,

    start_datetime_local DATETIME,

    start_date_local DATE,

    start_time_local TIME,

    distance_metres DOUBLE,

    distance_kilometres DOUBLE,

    distance_miles DOUBLE,

    moving_time_seconds INT,

    elapsed_time_seconds INT,

    elevation_gain_metres DOUBLE,

    average_speed_metres_per_second DOUBLE,

    average_speed_kilometres_per_hour DOUBLE,

    average_speed_miles_per_hour DOUBLE,

    average_cadence_rpm DOUBLE NULL,

    average_heartrate_bpm DOUBLE NULL,

    average_power_watts DOUBLE NULL,

    weighted_average_power_watts DOUBLE NULL,

    energy_kilojoules DOUBLE NULL,

    is_device_watts BOOLEAN,

    power_source_type VARCHAR(50) NULL,

    power_source_status VARCHAR(50) NULL,

    is_measured_power TINYINT(1) NOT NULL DEFAULT 0,

    is_power_record_eligible TINYINT(1) NOT NULL DEFAULT 0,

    power_record_exclusion_reason VARCHAR(150) NULL,

    power_classification_rule VARCHAR(150) NULL,

    power_classification_method VARCHAR(150) NULL,

    power_classification_version VARCHAR(50) NULL,

    power_meter_cutover_at DATETIME NULL,

    is_manual BOOLEAN NULL,

    is_trainer BOOLEAN NULL,

    has_streams BOOLEAN NOT NULL,

    has_details BOOLEAN NOT NULL,

    has_laps BOOLEAN NOT NULL,

    raw_activity_retrieved_at DATETIME NOT NULL,

    raw_detail_retrieved_at DATETIME NULL,

    transformed_at DATETIME NOT NULL,

    KEY idx_silver_activities_start_datetime_utc (start_datetime_utc),

    KEY idx_silver_activities_start_date_local (start_date_local),

    KEY idx_silver_activities_sport_type (sport_type),

    KEY idx_silver_activities_gear_id (gear_id)

);

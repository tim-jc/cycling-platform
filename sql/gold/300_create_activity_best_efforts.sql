-- Grain: one row per activity, metric, and duration
-- Business key: activity_id + metric_name + duration_seconds
-- Load strategy: rebuild by activity batch from silver.activity_streams
-- Source of truth: cycling_platform_silver.activity_streams

CREATE TABLE IF NOT EXISTS cycling_platform_gold.activity_best_efforts (

    activity_id BIGINT NOT NULL,

    metric_name VARCHAR(50) NOT NULL,

    duration_seconds INT NOT NULL,

    peak_value DOUBLE NOT NULL,

    start_sample_index INT NOT NULL,

    end_sample_index INT NOT NULL,

    start_time_seconds INT NULL,

    end_time_seconds INT NULL,

    start_distance_metres DOUBLE NULL,

    end_distance_metres DOUBLE NULL,

    start_latitude DOUBLE NULL,

    start_longitude DOUBLE NULL,

    end_latitude DOUBLE NULL,

    end_longitude DOUBLE NULL,

    sample_count INT NOT NULL,

    computed_at DATETIME NOT NULL,

    PRIMARY KEY (activity_id, metric_name, duration_seconds),

    KEY idx_gold_activity_best_efforts_metric_duration_peak (
        metric_name,
        duration_seconds,
        peak_value
    ),

    KEY idx_gold_activity_best_efforts_activity_id (activity_id)

);

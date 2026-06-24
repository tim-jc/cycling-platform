-- Rebuild silver activity streams from raw stream arrays.
-- Stream arrays are aligned by array position within each activity.

TRUNCATE TABLE cycling_platform_silver.activity_streams;

INSERT INTO cycling_platform_silver.activity_streams (
    activity_id,
    sample_index,
    time_seconds,
    distance_metres,
    latitude,
    longitude,
    altitude_metres,
    velocity_smooth_metres_per_second,
    heartrate_bpm,
    cadence_rpm,
    watts,
    temperature_celsius,
    is_moving,
    grade_smooth_percent,
    raw_stream_count,
    raw_max_original_size,
    raw_stream_retrieved_at,
    transformed_at
)
WITH digits AS (
    SELECT 0 AS n UNION ALL
    SELECT 1 UNION ALL
    SELECT 2 UNION ALL
    SELECT 3 UNION ALL
    SELECT 4 UNION ALL
    SELECT 5 UNION ALL
    SELECT 6 UNION ALL
    SELECT 7 UNION ALL
    SELECT 8 UNION ALL
    SELECT 9
),
sequence_numbers AS (
    SELECT
        ones.n
        + tens.n * 10
        + hundreds.n * 100
        + thousands.n * 1000
        + ten_thousands.n * 10000
        + 1 AS sample_index
    FROM digits ones
    CROSS JOIN digits tens
    CROSS JOIN digits hundreds
    CROSS JOIN digits thousands
    CROSS JOIN digits ten_thousands
),
activity_stream_summary AS (
    SELECT
        activity_id,
        COUNT(*) AS raw_stream_count,
        MAX(original_size) AS raw_max_original_size,
        MAX(retrieved_at) AS raw_stream_retrieved_at
    FROM cycling_platform_raw.activity_streams
    GROUP BY activity_id
),
activity_samples AS (
    SELECT
        summary.activity_id,
        sequence_numbers.sample_index,
        summary.raw_stream_count,
        summary.raw_max_original_size,
        summary.raw_stream_retrieved_at
    FROM activity_stream_summary summary
    JOIN sequence_numbers
        ON sequence_numbers.sample_index <= summary.raw_max_original_size
)
SELECT
    samples.activity_id,
    samples.sample_index,
    CAST(JSON_UNQUOTE(JSON_EXTRACT(
        time_stream.stream_payload,
        CONCAT('$[', samples.sample_index - 1, ']')
    )) AS SIGNED) AS time_seconds,
    CAST(JSON_UNQUOTE(JSON_EXTRACT(
        distance_stream.stream_payload,
        CONCAT('$[', samples.sample_index - 1, ']')
    )) AS DECIMAL(18,6)) AS distance_metres,
    CAST(JSON_UNQUOTE(JSON_EXTRACT(
        latlng_stream.stream_payload,
        CONCAT('$[', samples.sample_index - 1, '][0]')
    )) AS DECIMAL(11,8)) AS latitude,
    CAST(JSON_UNQUOTE(JSON_EXTRACT(
        latlng_stream.stream_payload,
        CONCAT('$[', samples.sample_index - 1, '][1]')
    )) AS DECIMAL(11,8)) AS longitude,
    CAST(JSON_UNQUOTE(JSON_EXTRACT(
        altitude_stream.stream_payload,
        CONCAT('$[', samples.sample_index - 1, ']')
    )) AS DECIMAL(18,6)) AS altitude_metres,
    CAST(JSON_UNQUOTE(JSON_EXTRACT(
        velocity_stream.stream_payload,
        CONCAT('$[', samples.sample_index - 1, ']')
    )) AS DECIMAL(18,6)) AS velocity_smooth_metres_per_second,
    CAST(JSON_UNQUOTE(JSON_EXTRACT(
        heartrate_stream.stream_payload,
        CONCAT('$[', samples.sample_index - 1, ']')
    )) AS SIGNED) AS heartrate_bpm,
    CAST(JSON_UNQUOTE(JSON_EXTRACT(
        cadence_stream.stream_payload,
        CONCAT('$[', samples.sample_index - 1, ']')
    )) AS SIGNED) AS cadence_rpm,
    CAST(JSON_UNQUOTE(JSON_EXTRACT(
        watts_stream.stream_payload,
        CONCAT('$[', samples.sample_index - 1, ']')
    )) AS SIGNED) AS watts,
    CAST(JSON_UNQUOTE(JSON_EXTRACT(
        temp_stream.stream_payload,
        CONCAT('$[', samples.sample_index - 1, ']')
    )) AS SIGNED) AS temperature_celsius,
    CASE JSON_UNQUOTE(JSON_EXTRACT(
        moving_stream.stream_payload,
        CONCAT('$[', samples.sample_index - 1, ']')
    ))
        WHEN 'true' THEN TRUE
        WHEN 'false' THEN FALSE
        ELSE NULL
    END AS is_moving,
    CAST(JSON_UNQUOTE(JSON_EXTRACT(
        grade_stream.stream_payload,
        CONCAT('$[', samples.sample_index - 1, ']')
    )) AS DECIMAL(18,6)) AS grade_smooth_percent,
    samples.raw_stream_count,
    samples.raw_max_original_size,
    samples.raw_stream_retrieved_at,
    UTC_TIMESTAMP() AS transformed_at
FROM activity_samples samples
LEFT JOIN cycling_platform_raw.activity_streams time_stream
    ON time_stream.activity_id = samples.activity_id
    AND time_stream.stream_type = 'time'
LEFT JOIN cycling_platform_raw.activity_streams distance_stream
    ON distance_stream.activity_id = samples.activity_id
    AND distance_stream.stream_type = 'distance'
LEFT JOIN cycling_platform_raw.activity_streams latlng_stream
    ON latlng_stream.activity_id = samples.activity_id
    AND latlng_stream.stream_type = 'latlng'
LEFT JOIN cycling_platform_raw.activity_streams altitude_stream
    ON altitude_stream.activity_id = samples.activity_id
    AND altitude_stream.stream_type = 'altitude'
LEFT JOIN cycling_platform_raw.activity_streams velocity_stream
    ON velocity_stream.activity_id = samples.activity_id
    AND velocity_stream.stream_type = 'velocity_smooth'
LEFT JOIN cycling_platform_raw.activity_streams heartrate_stream
    ON heartrate_stream.activity_id = samples.activity_id
    AND heartrate_stream.stream_type = 'heartrate'
LEFT JOIN cycling_platform_raw.activity_streams cadence_stream
    ON cadence_stream.activity_id = samples.activity_id
    AND cadence_stream.stream_type = 'cadence'
LEFT JOIN cycling_platform_raw.activity_streams watts_stream
    ON watts_stream.activity_id = samples.activity_id
    AND watts_stream.stream_type = 'watts'
LEFT JOIN cycling_platform_raw.activity_streams temp_stream
    ON temp_stream.activity_id = samples.activity_id
    AND temp_stream.stream_type = 'temp'
LEFT JOIN cycling_platform_raw.activity_streams moving_stream
    ON moving_stream.activity_id = samples.activity_id
    AND moving_stream.stream_type = 'moving'
LEFT JOIN cycling_platform_raw.activity_streams grade_stream
    ON grade_stream.activity_id = samples.activity_id
    AND grade_stream.stream_type = 'grade_smooth';

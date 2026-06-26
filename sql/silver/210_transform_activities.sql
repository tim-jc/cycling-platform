-- Rebuild silver activities from raw activity and detail data.

TRUNCATE TABLE cycling_platform_silver.activities;

INSERT INTO cycling_platform_silver.activities (
    activity_id,
    athlete_id,
    source_id,
    gear_id,
    activity_name,
    sport_type,
    activity_type,
    timezone_name,
    start_datetime_utc,
    start_datetime_local,
    start_date_local,
    start_time_local,
    distance_metres,
    distance_kilometres,
    distance_miles,
    moving_time_seconds,
    elapsed_time_seconds,
    elevation_gain_metres,
    average_speed_metres_per_second,
    average_speed_kilometres_per_hour,
    average_speed_miles_per_hour,
    average_cadence_rpm,
    average_heartrate_bpm,
    average_power_watts,
    weighted_average_power_watts,
    energy_kilojoules,
    is_device_watts,
    is_manual,
    is_trainer,
    has_streams,
    has_details,
    has_laps,
    raw_activity_retrieved_at,
    raw_detail_retrieved_at,
    transformed_at
)
SELECT
    a.activity_id,
    a.athlete_id,
    a.source_id,
    a.gear_id,
    a.activity_name,
    a.sport_type,
    a.sport_type AS activity_type,
    a.timezone_name,
    a.start_datetime_utc,
    a.start_datetime_local,
    DATE(a.start_datetime_local) AS start_date_local,
    TIME(a.start_datetime_local) AS start_time_local,
    a.distance_metres,
    a.distance_metres / 1000 AS distance_kilometres,
    a.distance_metres / 1609.344 AS distance_miles,
    a.moving_time_seconds,
    a.elapsed_time_seconds,
    a.elevation_gain_metres,
    a.average_speed_metres_per_second,
    a.average_speed_metres_per_second * 3.6 AS average_speed_kilometres_per_hour,
    a.average_speed_metres_per_second * 2.2369362920544 AS average_speed_miles_per_hour,
    a.average_cadence_rpm,
    a.average_heartrate_bpm,
    a.average_power_watts,
    a.weighted_average_power_watts,
    a.energy_kilojoules,
    a.is_device_watts,
    CASE JSON_UNQUOTE(JSON_EXTRACT(a.raw_payload, '$.manual'))
        WHEN 'true' THEN TRUE
        WHEN 'false' THEN FALSE
        ELSE NULL
    END AS is_manual,
    CASE JSON_UNQUOTE(JSON_EXTRACT(a.raw_payload, '$.trainer'))
        WHEN 'true' THEN TRUE
        WHEN 'false' THEN FALSE
        ELSE NULL
    END AS is_trainer,
    EXISTS (
        SELECT 1
        FROM cycling_platform_raw.activity_streams s
        WHERE s.activity_id = a.activity_id
    ) AS has_streams,
    d.activity_id IS NOT NULL AS has_details,
    EXISTS (
        SELECT 1
        FROM cycling_platform_raw.activity_laps l
        WHERE l.activity_id = a.activity_id
    ) AS has_laps,
    a.retrieved_at AS raw_activity_retrieved_at,
    d.retrieved_at AS raw_detail_retrieved_at,
    UTC_TIMESTAMP() AS transformed_at
FROM cycling_platform_raw.activities a
LEFT JOIN cycling_platform_raw.activity_details d
    ON d.activity_id = a.activity_id;

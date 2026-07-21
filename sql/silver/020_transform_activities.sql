-- Rebuild silver activities from raw activity and detail data.
-- Power-source classification is the platform interpretation of source power
-- provenance. Raw Strava fields and payloads remain unchanged.

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
    power_source_type,
    power_source_status,
    is_measured_power,
    is_power_record_eligible,
    power_record_exclusion_reason,
    power_classification_rule,
    power_classification_method,
    power_classification_version,
    power_meter_cutover_at,
    is_manual,
    is_trainer,
    has_streams,
    has_details,
    has_laps,
    raw_activity_retrieved_at,
    raw_detail_retrieved_at,
    transformed_at
)
WITH power_config AS (
    SELECT
        effective_cutover_at,
        rule_version
    FROM cycling_platform_admin.power_source_classification
    WHERE classification_name = 'strava_power_meter_cutover'
      AND is_active = 1
    ORDER BY updated_at DESC
    LIMIT 1
),
activity_evidence AS (
    SELECT
        a.*,
        CASE JSON_UNQUOTE(JSON_EXTRACT(a.raw_payload, '$.manual'))
            WHEN 'true' THEN TRUE
            WHEN 'false' THEN FALSE
            ELSE NULL
        END AS is_manual_raw,
        CASE JSON_UNQUOTE(JSON_EXTRACT(a.raw_payload, '$.trainer'))
            WHEN 'true' THEN TRUE
            WHEN 'false' THEN FALSE
            ELSE NULL
        END AS is_trainer_raw,
        LOWER(CONCAT_WS(
            ' ',
            COALESCE(a.activity_name, ''),
            COALESCE(JSON_UNQUOTE(JSON_EXTRACT(a.raw_payload, '$.external_id')), ''),
            COALESCE(JSON_UNQUOTE(JSON_EXTRACT(a.raw_payload, '$.device_name')), '')
        )) AS source_identity_text,
        EXISTS (
            SELECT 1
            FROM cycling_platform_raw.activity_streams s
            WHERE s.activity_id = a.activity_id
              AND s.stream_type = 'watts'
        ) AS has_watts_stream,
        EXISTS (
            SELECT 1
            FROM cycling_platform_raw.activity_streams s
            WHERE s.activity_id = a.activity_id
              AND s.stream_type = 'latlng'
        ) AS has_latlng_stream
    FROM cycling_platform_raw.activities a
),
classified AS (
    SELECT
        evidence.*,
        d.activity_id IS NOT NULL AS has_details,
        d.retrieved_at AS raw_detail_retrieved_at,
        EXISTS (
            SELECT 1
            FROM cycling_platform_raw.activity_laps l
            WHERE l.activity_id = evidence.activity_id
        ) AS has_laps,
        EXISTS (
            SELECT 1
            FROM cycling_platform_raw.activity_streams s
            WHERE s.activity_id = evidence.activity_id
        ) AS has_streams,
        power_config.effective_cutover_at,
        power_config.rule_version,
        overrides.power_source_type AS override_power_source_type,
        overrides.power_source_status AS override_power_source_status,
        overrides.is_measured_power AS override_is_measured_power,
        overrides.is_power_record_eligible AS override_is_power_record_eligible,
        overrides.power_record_exclusion_reason AS override_exclusion_reason,
        overrides.power_classification_rule AS override_classification_rule,
        overrides.power_classification_method AS override_classification_method,
        (
            COALESCE(evidence.is_device_watts, 0) = 1
            OR evidence.average_power_watts IS NOT NULL
            OR evidence.weighted_average_power_watts IS NOT NULL
            OR COALESCE(evidence.has_watts_stream, 0) = 1
        ) AS has_usable_power,
        (
            evidence.source_identity_text LIKE '%trainerroad%'
        ) AS is_trainerroad,
        (
            evidence.sport_type IN (
                'Ride',
                'GravelRide',
                'MountainBikeRide',
                'EBikeRide',
                'Handcycle'
            )
            AND evidence.sport_type <> 'VirtualRide'
            AND COALESCE(evidence.is_trainer_raw, 0) = 0
            AND COALESCE(evidence.has_latlng_stream, 0) = 1
            AND evidence.source_identity_text NOT LIKE '%trainerroad%'
        ) AS is_outdoor_power_candidate
    FROM activity_evidence evidence
    LEFT JOIN cycling_platform_raw.activity_details d
        ON d.activity_id = evidence.activity_id
    LEFT JOIN power_config
        ON 1 = 1
    LEFT JOIN cycling_platform_admin.activity_power_overrides overrides
        ON overrides.activity_id = evidence.activity_id
       AND overrides.is_active = 1
)
SELECT
    activity_id,
    athlete_id,
    source_id,
    gear_id,
    activity_name,
    sport_type,
    sport_type AS activity_type,
    timezone_name,
    start_datetime_utc,
    start_datetime_local,
    DATE(start_datetime_local) AS start_date_local,
    TIME(start_datetime_local) AS start_time_local,
    distance_metres,
    distance_metres / 1000 AS distance_kilometres,
    distance_metres / 1609.344 AS distance_miles,
    moving_time_seconds,
    elapsed_time_seconds,
    elevation_gain_metres,
    average_speed_metres_per_second,
    average_speed_metres_per_second * 3.6 AS average_speed_kilometres_per_hour,
    average_speed_metres_per_second * 2.2369362920544 AS average_speed_miles_per_hour,
    average_cadence_rpm,
    average_heartrate_bpm,
    average_power_watts,
    weighted_average_power_watts,
    energy_kilojoules,
    is_device_watts,
    CASE
        WHEN override_power_source_type IS NOT NULL
            THEN override_power_source_type
        WHEN has_usable_power = 0
            THEN 'none'
        WHEN is_trainerroad = 1
            AND effective_cutover_at IS NULL
            THEN 'unknown'
        WHEN is_trainerroad = 1
            AND start_datetime_utc < effective_cutover_at
            THEN 'virtual'
        WHEN is_outdoor_power_candidate = 1
            AND is_device_watts = 1
            THEN 'measured'
        WHEN effective_cutover_at IS NULL
            THEN 'unknown'
        WHEN is_device_watts = 1
            AND start_datetime_utc >= effective_cutover_at
            THEN 'measured'
        WHEN is_device_watts = 1
            AND start_datetime_utc < effective_cutover_at
            THEN 'unknown'
        WHEN COALESCE(is_device_watts, 0) = 0
            AND has_usable_power = 1
            THEN 'estimated'
        ELSE 'unknown'
    END AS power_source_type,
    CASE
        WHEN override_power_source_status IS NOT NULL
            THEN override_power_source_status
        WHEN has_usable_power = 0
            THEN 'unavailable'
        WHEN is_trainerroad = 1
            AND effective_cutover_at IS NULL
            THEN 'ambiguous'
        WHEN is_trainerroad = 1
            AND start_datetime_utc < effective_cutover_at
            THEN 'inferred_virtual'
        WHEN is_outdoor_power_candidate = 1
            AND is_device_watts = 1
            THEN 'inferred_measured'
        WHEN effective_cutover_at IS NULL
            THEN 'ambiguous'
        WHEN is_device_watts = 1
            AND start_datetime_utc >= effective_cutover_at
            THEN 'inferred_measured'
        WHEN is_device_watts = 1
            AND start_datetime_utc < effective_cutover_at
            THEN 'ambiguous'
        WHEN COALESCE(is_device_watts, 0) = 0
            AND has_usable_power = 1
            THEN 'ambiguous'
        ELSE 'ambiguous'
    END AS power_source_status,
    CASE
        WHEN override_is_measured_power IS NOT NULL
            THEN override_is_measured_power
        WHEN has_usable_power = 1
            AND is_outdoor_power_candidate = 1
            AND is_device_watts = 1
            THEN TRUE
        WHEN has_usable_power = 1
            AND effective_cutover_at IS NOT NULL
            AND is_device_watts = 1
            AND start_datetime_utc >= effective_cutover_at
            THEN TRUE
        ELSE FALSE
    END AS is_measured_power,
    CASE
        WHEN override_is_power_record_eligible IS NOT NULL
            THEN override_is_power_record_eligible
        WHEN has_usable_power = 1
            AND is_outdoor_power_candidate = 1
            AND is_device_watts = 1
            THEN TRUE
        WHEN has_usable_power = 1
            AND effective_cutover_at IS NOT NULL
            AND is_device_watts = 1
            AND start_datetime_utc >= effective_cutover_at
            THEN TRUE
        ELSE FALSE
    END AS is_power_record_eligible,
    CASE
        WHEN override_is_power_record_eligible IS NOT NULL
            THEN override_exclusion_reason
        WHEN has_usable_power = 0
            THEN 'no_usable_power'
        WHEN is_trainerroad = 1
            AND effective_cutover_at IS NULL
            THEN 'power_meter_cutover_unavailable'
        WHEN is_trainerroad = 1
            AND start_datetime_utc < effective_cutover_at
            THEN 'trainerroad_virtual_power_before_power_meter_cutover'
        WHEN is_outdoor_power_candidate = 1
            AND is_device_watts = 1
            THEN NULL
        WHEN effective_cutover_at IS NULL
            THEN 'power_meter_cutover_unavailable'
        WHEN is_device_watts = 1
            AND start_datetime_utc >= effective_cutover_at
            THEN NULL
        WHEN is_device_watts = 1
            AND start_datetime_utc < effective_cutover_at
            THEN 'pre_cutover_device_watts_ambiguous'
        WHEN COALESCE(is_device_watts, 0) = 0
            AND has_usable_power = 1
            THEN 'strava_non_device_watts'
        ELSE 'unknown_power_source'
    END AS power_record_exclusion_reason,
    CASE
        WHEN override_classification_rule IS NOT NULL
            THEN override_classification_rule
        WHEN has_usable_power = 0
            THEN 'no_usable_power'
        WHEN is_trainerroad = 1
            AND effective_cutover_at IS NULL
            THEN 'power_meter_cutover_unavailable'
        WHEN is_trainerroad = 1
            AND start_datetime_utc < effective_cutover_at
            THEN 'trainerroad_virtual_power_before_power_meter_cutover'
        WHEN is_outdoor_power_candidate = 1
            AND is_device_watts = 1
            AND start_datetime_utc < effective_cutover_at
            THEN 'outdoor_device_watts_before_cutover'
        WHEN is_outdoor_power_candidate = 1
            AND is_device_watts = 1
            THEN 'outdoor_device_watts_gps_evidence'
        WHEN effective_cutover_at IS NULL
            THEN 'power_meter_cutover_unavailable'
        WHEN is_device_watts = 1
            AND start_datetime_utc >= effective_cutover_at
            THEN 'device_watts_at_or_after_power_meter_cutover'
        WHEN is_device_watts = 1
            AND start_datetime_utc < effective_cutover_at
            THEN 'pre_cutover_device_watts_ambiguous'
        WHEN COALESCE(is_device_watts, 0) = 0
            AND has_usable_power = 1
            THEN 'strava_non_device_watts'
        ELSE 'unknown_power_source'
    END AS power_classification_rule,
    CASE
        WHEN override_classification_method IS NOT NULL
            THEN override_classification_method
        WHEN is_trainerroad = 1
            THEN 'activity_name_or_payload_pattern'
        WHEN is_outdoor_power_candidate = 1
            AND is_device_watts = 1
            THEN 'outdoor_gps_device_watts_evidence'
        WHEN has_usable_power = 1
            AND effective_cutover_at IS NOT NULL
            THEN 'cutover_rule'
        ELSE 'source_field_fallback'
    END AS power_classification_method,
    COALESCE(rule_version, 'power_source_classification_v1')
        AS power_classification_version,
    effective_cutover_at AS power_meter_cutover_at,
    is_manual_raw AS is_manual,
    is_trainer_raw AS is_trainer,
    has_streams,
    has_details,
    has_laps,
    retrieved_at AS raw_activity_retrieved_at,
    raw_detail_retrieved_at,
    UTC_TIMESTAMP() AS transformed_at
FROM classified;

report_power_source_classification <- function(
  connection,
  output_path = NULL
) {
  report <- DBI::dbGetQuery(
    conn = connection,
    statement = "
      SELECT
        activities.activity_id,
        activities.start_datetime_utc,
        activities.start_datetime_local,
        activities.start_date_local,
        activities.activity_name,
        activities.sport_type,
        activities.is_trainer,
        activities.is_device_watts,
        activities.gear_id,
        JSON_UNQUOTE(JSON_EXTRACT(raw.raw_payload, '$.external_id'))
          AS external_id,
        JSON_UNQUOTE(JSON_EXTRACT(raw.raw_payload, '$.device_name'))
          AS device_name,
        activities.average_power_watts,
        activities.weighted_average_power_watts,
        EXISTS (
          SELECT 1
          FROM cycling_platform_silver.activity_streams streams
          WHERE streams.activity_id = activities.activity_id
            AND streams.watts IS NOT NULL
        ) AS has_watts_stream,
        EXISTS (
          SELECT 1
          FROM cycling_platform_raw.activity_streams streams
          WHERE streams.activity_id = activities.activity_id
            AND streams.stream_type = 'latlng'
        ) AS has_latlng_stream,
        classification.effective_cutover_at,
        classification.derived_supporting_activity_id
          AS cutover_supporting_activity_id,
        classification.derived_supporting_gear_id
          AS cutover_supporting_gear_id,
        activities.power_source_type,
        activities.power_source_status,
        activities.is_measured_power,
        activities.is_power_record_eligible,
        activities.power_record_exclusion_reason,
        activities.power_classification_rule,
        activities.power_classification_method,
        activities.power_classification_version,
        CASE
          WHEN activities.activity_id =
            classification.derived_supporting_activity_id
          THEN 1
          ELSE 0
        END AS is_cutover_supporting_activity,
        CASE
          WHEN activities.is_device_watts = 1
            AND activities.sport_type IN (
              'Ride',
              'GravelRide',
              'MountainBikeRide',
              'EBikeRide',
              'Handcycle'
            )
            AND activities.sport_type <> 'VirtualRide'
            AND COALESCE(activities.is_trainer, 0) = 0
            AND EXISTS (
              SELECT 1
              FROM cycling_platform_raw.activity_streams streams
              WHERE streams.activity_id = activities.activity_id
                AND streams.stream_type = 'latlng'
            )
            AND LOWER(CONCAT_WS(
              ' ',
              COALESCE(activities.activity_name, ''),
              COALESCE(JSON_UNQUOTE(JSON_EXTRACT(raw.raw_payload, '$.external_id')), ''),
              COALESCE(JSON_UNQUOTE(JSON_EXTRACT(raw.raw_payload, '$.device_name')), '')
            )) NOT LIKE '%trainerroad%'
          THEN 1
          ELSE 0
        END AS is_outdoor_device_watts_activity,
        CASE
          WHEN activities.gear_id IN ('b2708460', 'b3311095')
          THEN 1
          ELSE 0
        END AS is_approved_cutover_gear,
        CASE
          WHEN activities.is_device_watts = 1
            AND activities.gear_id NOT IN ('b2708460', 'b3311095')
            AND activities.sport_type IN (
              'Ride',
              'GravelRide',
              'MountainBikeRide',
              'EBikeRide',
              'Handcycle'
            )
            AND activities.sport_type <> 'VirtualRide'
            AND COALESCE(activities.is_trainer, 0) = 0
            AND EXISTS (
              SELECT 1
              FROM cycling_platform_raw.activity_streams streams
              WHERE streams.activity_id = activities.activity_id
                AND streams.stream_type = 'latlng'
            )
            AND LOWER(CONCAT_WS(
              ' ',
              COALESCE(activities.activity_name, ''),
              COALESCE(JSON_UNQUOTE(JSON_EXTRACT(raw.raw_payload, '$.external_id')), ''),
              COALESCE(JSON_UNQUOTE(JSON_EXTRACT(raw.raw_payload, '$.device_name')), '')
            )) NOT LIKE '%trainerroad%'
          THEN 1
          ELSE 0
        END AS is_rejected_cutoff_candidate_unapproved_gear,
        CASE
          WHEN activities.is_device_watts = 1
            AND activities.gear_id IS NULL
            AND activities.sport_type IN (
              'Ride',
              'GravelRide',
              'MountainBikeRide',
              'EBikeRide',
              'Handcycle'
            )
            AND activities.sport_type <> 'VirtualRide'
            AND COALESCE(activities.is_trainer, 0) = 0
            AND EXISTS (
              SELECT 1
              FROM cycling_platform_raw.activity_streams streams
              WHERE streams.activity_id = activities.activity_id
                AND streams.stream_type = 'latlng'
            )
            AND LOWER(CONCAT_WS(
              ' ',
              COALESCE(activities.activity_name, ''),
              COALESCE(JSON_UNQUOTE(JSON_EXTRACT(raw.raw_payload, '$.external_id')), ''),
              COALESCE(JSON_UNQUOTE(JSON_EXTRACT(raw.raw_payload, '$.device_name')), '')
            )) NOT LIKE '%trainerroad%'
          THEN 1
          ELSE 0
        END AS is_missing_gear_cutoff_review,
        CASE
          WHEN LOWER(CONCAT_WS(
              ' ',
              COALESCE(activities.activity_name, ''),
              COALESCE(JSON_UNQUOTE(JSON_EXTRACT(raw.raw_payload, '$.external_id')), ''),
              COALESCE(JSON_UNQUOTE(JSON_EXTRACT(raw.raw_payload, '$.device_name')), '')
            )) LIKE '%trainerroad%'
            AND activities.power_meter_cutover_at IS NOT NULL
            AND activities.start_datetime_utc >= activities.power_meter_cutover_at
            AND (
              activities.is_device_watts = 1
              OR activities.average_power_watts IS NOT NULL
              OR activities.weighted_average_power_watts IS NOT NULL
            )
          THEN 1
          ELSE 0
        END AS is_post_cutover_trainerroad_power,
        CASE
          WHEN activities.power_record_exclusion_reason =
            'trainerroad_virtual_power_before_power_meter_cutover'
          THEN 1
          ELSE 0
        END AS is_pre_cutover_trainerroad_power,
        CASE
          WHEN activities.power_source_status = 'ambiguous'
          THEN 1
          ELSE 0
        END AS is_ambiguous
      FROM cycling_platform_silver.activities activities
      INNER JOIN cycling_platform_raw.activities raw
        ON raw.activity_id = activities.activity_id
      LEFT JOIN cycling_platform_admin.power_source_classification classification
        ON classification.classification_name = 'strava_power_meter_cutover'
       AND classification.is_active = 1
      WHERE activities.is_device_watts = 1
         OR activities.average_power_watts IS NOT NULL
         OR activities.weighted_average_power_watts IS NOT NULL
         OR EXISTS (
          SELECT 1
          FROM cycling_platform_silver.activity_streams streams
          WHERE streams.activity_id = activities.activity_id
            AND streams.watts IS NOT NULL
        )
      ORDER BY
        activities.start_datetime_utc,
        activities.activity_id
    "
  )

  if (!is.null(output_path)) {
    utils::write.csv(
      report,
      file = output_path,
      row.names = FALSE
    )
  }

  report
}

report_power_record_reconciliation <- function(
  connection,
  metric_name = "watts"
) {
  DBI::dbGetQuery(
    conn = connection,
    statement = "
      WITH excluded AS (
        SELECT
          duration_seconds,
          activity_id AS excluded_activity_id,
          peak_value AS excluded_peak_value,
          record_exclusion_reason,
          ROW_NUMBER() OVER (
            PARTITION BY duration_seconds
            ORDER BY peak_value DESC, activity_id
          ) AS excluded_rank
        FROM cycling_platform_gold.activity_best_efforts
        WHERE metric_name = ?
          AND is_record_eligible = 0
      ),
      eligible AS (
        SELECT
          duration_seconds,
          activity_id AS replacement_activity_id,
          peak_value AS replacement_peak_value,
          ROW_NUMBER() OVER (
            PARTITION BY duration_seconds
            ORDER BY peak_value DESC, activity_id
          ) AS eligible_rank
        FROM cycling_platform_gold.activity_best_efforts
        WHERE metric_name = ?
          AND is_record_eligible = 1
      )
      SELECT
        excluded.duration_seconds,
        excluded.excluded_activity_id,
        excluded.excluded_peak_value,
        excluded.record_exclusion_reason,
        eligible.replacement_activity_id,
        eligible.replacement_peak_value,
        excluded.excluded_peak_value - eligible.replacement_peak_value
          AS watt_difference
      FROM excluded
      LEFT JOIN eligible
        ON eligible.duration_seconds = excluded.duration_seconds
       AND eligible.eligible_rank = 1
      WHERE excluded.excluded_rank = 1
      ORDER BY excluded.duration_seconds
    ",
    params = list(
      metric_name,
      metric_name
    )
  )
}

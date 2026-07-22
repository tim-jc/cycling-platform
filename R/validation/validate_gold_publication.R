gold_validation_sql_values <- function(values) {
  paste(
    values,
    collapse = ", "
  )
}

gold_validation_sql_strings <- function(connection, values) {
  paste(
    DBI::dbQuoteString(
      conn = connection,
      x = as.character(values)
    ),
    collapse = ", "
  )
}

gold_activity_best_efforts_publication_checks <- function(
  connection,
  config = list(),
  check_scope = "gold_publication",
  per_check_timeout_seconds = NULL,
  deadline = NULL
) {
  metrics <- config$transforms$gold_best_effort_metrics

  if (is.null(metrics)) {
    metrics <- c(
      "watts",
      "cadence_rpm",
      "heartrate_bpm"
    )
  }

  durations <- config$transforms$gold_best_effort_durations

  if (is.null(durations)) {
    durations <- default_best_effort_durations()
  }

  calculation_version <- gold_activity_best_efforts_calculation_version(
    config = config
  )

  metrics_sql <- gold_validation_sql_strings(
    connection = connection,
    values = metrics
  )

  durations_sql <- gold_validation_sql_values(
    as.integer(durations)
  )

  calculation_version_sql <- gold_validation_sql_strings(
    connection = connection,
    values = calculation_version
  )

  trainerroad_cutover_gear_id <- trainerroad_power_cutover_gear_id(
    config = config
  )

  trainerroad_cutover_gear_id_sql <- gold_validation_sql_strings(
    connection = connection,
    values = trainerroad_cutover_gear_id
  )

  checks <- list()

  table_exists <- get_gold_activity_best_efforts_table_exists(
    connection = connection
  )

  checks <- append_validation_result(
    checks,
    validation_table_exists_result(
      table_exists = table_exists,
      check_scope = check_scope
    )
  )

  if (!isTRUE(table_exists)) {
    return(dplyr::bind_rows(checks))
  }

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_best_efforts_latest_transform_success",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = "
        WITH latest AS (
          SELECT
            transform_run_id,
            run_status,
            completed_at
          FROM cycling_platform_admin.transform_run
          WHERE layer_name = 'gold'
            AND entity_name = 'activity_best_efforts'
          ORDER BY transform_run_id DESC
          LIMIT 1
        )
        SELECT
          'missing_or_failed_latest_gold_transform' AS issue_type
        FROM DUAL
        WHERE NOT EXISTS (
            SELECT 1
            FROM latest
            WHERE run_status = 'SUCCESS'
              AND completed_at IS NOT NULL
          )
      ",
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_best_efforts_latest_transform_fresh",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = "
        WITH latest AS (
          SELECT
            transform_run_id,
            run_status,
            completed_at
          FROM cycling_platform_admin.transform_run
          WHERE layer_name = 'gold'
            AND entity_name = 'activity_best_efforts'
            AND run_status = 'SUCCESS'
          ORDER BY transform_run_id DESC
          LIMIT 1
        ),
        latest_silver_stream_transform AS (
          SELECT MAX(completed_at) AS latest_silver_stream_completed_at
          FROM cycling_platform_admin.transform_run
          WHERE layer_name = 'silver'
            AND entity_name = 'activity_streams'
            AND run_status = 'SUCCESS'
        )
        SELECT
          latest.transform_run_id,
          latest.completed_at,
          latest_silver_stream_transform.latest_silver_stream_completed_at
        FROM latest_silver_stream_transform
        LEFT JOIN latest
          ON 1 = 1
        WHERE latest_silver_stream_transform.latest_silver_stream_completed_at IS NOT NULL
          AND (
            latest.transform_run_id IS NULL
            OR latest.completed_at
              < latest_silver_stream_transform.latest_silver_stream_completed_at
          )
      ",
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_best_efforts_latest_batches_success",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = "
        WITH latest AS (
          SELECT transform_run_id
          FROM cycling_platform_admin.transform_run
          WHERE layer_name = 'gold'
            AND entity_name = 'activity_best_efforts'
          ORDER BY transform_run_id DESC
          LIMIT 1
        )
        SELECT
          batches.transform_run_batch_id,
          batches.batch_number,
          batches.batch_status
        FROM latest
        INNER JOIN cycling_platform_admin.transform_run_batch batches
          ON batches.transform_run_id = latest.transform_run_id
        WHERE batches.batch_status <> 'SUCCESS'
        LIMIT 1000
      ",
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_best_efforts_duplicate_primary_key",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = "
        SELECT
          activity_id,
          metric_name,
          duration_seconds,
          COUNT(*) AS issue_count
        FROM cycling_platform_gold.activity_best_efforts
        GROUP BY
          activity_id,
          metric_name,
          duration_seconds
        HAVING COUNT(*) > 1
        LIMIT 1000
      ",
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_best_efforts_orphaned_activity_ids",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = "
        SELECT
          best_efforts.activity_id
        FROM cycling_platform_gold.activity_best_efforts best_efforts
        LEFT JOIN cycling_platform_silver.activities activities
          ON activities.activity_id = best_efforts.activity_id
        WHERE activities.activity_id IS NULL
        GROUP BY best_efforts.activity_id
        LIMIT 1000
      ",
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_best_efforts_metric_names_valid",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = glue::glue("
        SELECT DISTINCT metric_name
        FROM cycling_platform_gold.activity_best_efforts
        WHERE metric_name NOT IN ({metrics_sql})
        LIMIT 1000
      "),
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_best_efforts_durations_valid",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = glue::glue("
        SELECT DISTINCT duration_seconds
        FROM cycling_platform_gold.activity_best_efforts
        WHERE duration_seconds NOT IN ({durations_sql})
        LIMIT 1000
      "),
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_best_efforts_calculation_version_current",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = glue::glue("
        SELECT
          activity_id,
          metric_name,
          duration_seconds,
          calculation_version
        FROM cycling_platform_gold.activity_best_efforts
        WHERE calculation_version IS NULL
           OR calculation_version = ''
           OR calculation_version <> {calculation_version_sql}
        LIMIT 1000
      "),
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_best_efforts_watts_eligibility_matches_silver",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = "
        SELECT
          best_efforts.activity_id,
          best_efforts.duration_seconds,
          best_efforts.is_record_eligible,
          activities.is_power_record_eligible
        FROM cycling_platform_gold.activity_best_efforts best_efforts
        INNER JOIN cycling_platform_silver.activities activities
          ON activities.activity_id = best_efforts.activity_id
        WHERE best_efforts.metric_name = 'watts'
          AND best_efforts.is_record_eligible
            <> activities.is_power_record_eligible
        LIMIT 1000
      ",
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_best_efforts_non_watts_not_excluded",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = "
        SELECT
          activity_id,
          metric_name,
          duration_seconds,
          is_record_eligible,
          record_exclusion_reason
        FROM cycling_platform_gold.activity_best_efforts
        WHERE metric_name <> 'watts'
          AND (
            is_record_eligible <> 1
            OR record_exclusion_reason IS NOT NULL
          )
        LIMIT 1000
      ",
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_best_efforts_exclusions_have_reason",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = "
        SELECT
          activity_id,
          metric_name,
          duration_seconds
        FROM cycling_platform_gold.activity_best_efforts
        WHERE is_record_eligible = 0
          AND (
            record_exclusion_reason IS NULL
            OR record_exclusion_reason = ''
          )
        LIMIT 1000
      ",
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "trainerroad_power_cutover_supporting_gear_valid",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = glue::glue("
        SELECT
          classification_name,
          derived_supporting_activity_id,
          derived_supporting_gear_id
        FROM cycling_platform_admin.power_source_classification
        WHERE classification_name = 'strava_power_meter_cutover'
          AND is_active = 1
          AND derived_supporting_activity_id IS NOT NULL
          AND (
            derived_supporting_gear_id IS NULL
            OR derived_supporting_gear_id <> {trainerroad_cutover_gear_id_sql}
          )
        LIMIT 1000
      "),
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "trainerroad_power_cutover_selected_earliest_roller_bike_candidate",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = glue::glue("
        WITH candidate AS (
          SELECT
            activities.activity_id,
            activities.start_datetime_utc,
            activities.gear_id
          FROM cycling_platform_raw.activities activities
          WHERE activities.is_device_watts = 1
            AND activities.gear_id = {trainerroad_cutover_gear_id_sql}
            AND (
              activities.average_power_watts IS NOT NULL
              OR activities.weighted_average_power_watts IS NOT NULL
              OR EXISTS (
                SELECT 1
                FROM cycling_platform_raw.activity_streams power_streams
                WHERE power_streams.activity_id = activities.activity_id
                  AND power_streams.stream_type = 'watts'
              )
            )
            AND activities.start_datetime_utc IS NOT NULL
            AND activities.sport_type IN (
              'Ride',
              'GravelRide',
              'MountainBikeRide',
              'EBikeRide',
              'Handcycle'
            )
            AND activities.sport_type <> 'VirtualRide'
            AND COALESCE(
              JSON_UNQUOTE(JSON_EXTRACT(activities.raw_payload, '$.trainer')),
              'false'
            ) <> 'true'
            AND EXISTS (
              SELECT 1
              FROM cycling_platform_raw.activity_streams streams
              WHERE streams.activity_id = activities.activity_id
                AND streams.stream_type = 'latlng'
            )
            AND LOWER(CONCAT_WS(
              ' ',
              COALESCE(activities.activity_name, ''),
              COALESCE(JSON_UNQUOTE(JSON_EXTRACT(activities.raw_payload, '$.external_id')), ''),
              COALESCE(JSON_UNQUOTE(JSON_EXTRACT(activities.raw_payload, '$.device_name')), '')
            )) NOT LIKE '%trainerroad%'
          ORDER BY activities.start_datetime_utc, activities.activity_id
          LIMIT 1
        ),
        active_classification AS (
          SELECT
            derived_cutover_at,
            derived_supporting_activity_id,
            derived_supporting_gear_id
          FROM cycling_platform_admin.power_source_classification
          WHERE classification_name = 'strava_power_meter_cutover'
            AND is_active = 1
          ORDER BY updated_at DESC
          LIMIT 1
        )
        SELECT
          candidate.activity_id AS expected_activity_id,
          candidate.start_datetime_utc AS expected_cutover_at,
          candidate.gear_id AS expected_gear_id,
          active_classification.derived_supporting_activity_id
            AS actual_activity_id,
          active_classification.derived_cutover_at AS actual_cutover_at,
          active_classification.derived_supporting_gear_id AS actual_gear_id
        FROM candidate
        LEFT JOIN active_classification
          ON 1 = 1
        WHERE active_classification.derived_supporting_activity_id IS NULL
          OR active_classification.derived_supporting_activity_id
            <> candidate.activity_id
          OR active_classification.derived_supporting_gear_id
            <> candidate.gear_id
          OR active_classification.derived_cutover_at
            <> candidate.start_datetime_utc
        LIMIT 1000
      "),
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "trainerroad_power_cutover_not_set_by_other_gear",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = glue::glue("
        SELECT
          classification.derived_supporting_activity_id,
          classification.derived_supporting_gear_id,
          activities.gear_id
        FROM cycling_platform_admin.power_source_classification classification
        INNER JOIN cycling_platform_raw.activities activities
          ON activities.activity_id = classification.derived_supporting_activity_id
        WHERE classification.classification_name = 'strava_power_meter_cutover'
          AND classification.is_active = 1
          AND activities.gear_id <> {trainerroad_cutover_gear_id_sql}
        LIMIT 1000
      "),
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "trainerroad_power_cutover_candidate_not_indoor_or_virtual",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = "
        SELECT
          classification.derived_supporting_activity_id,
          activities.sport_type,
          JSON_UNQUOTE(JSON_EXTRACT(activities.raw_payload, '$.trainer'))
            AS trainer,
          activities.activity_name,
          JSON_UNQUOTE(JSON_EXTRACT(activities.raw_payload, '$.external_id'))
            AS external_id,
          JSON_UNQUOTE(JSON_EXTRACT(activities.raw_payload, '$.device_name'))
            AS device_name
        FROM cycling_platform_admin.power_source_classification classification
        INNER JOIN cycling_platform_raw.activities activities
          ON activities.activity_id = classification.derived_supporting_activity_id
        WHERE classification.classification_name = 'strava_power_meter_cutover'
          AND classification.is_active = 1
          AND (
            activities.sport_type = 'VirtualRide'
            OR COALESCE(
              JSON_UNQUOTE(JSON_EXTRACT(activities.raw_payload, '$.trainer')),
              'false'
            ) = 'true'
            OR LOWER(CONCAT_WS(
              ' ',
              COALESCE(activities.activity_name, ''),
              COALESCE(JSON_UNQUOTE(JSON_EXTRACT(activities.raw_payload, '$.external_id')), ''),
              COALESCE(JSON_UNQUOTE(JSON_EXTRACT(activities.raw_payload, '$.device_name')), '')
            )) LIKE '%trainerroad%'
            OR NOT EXISTS (
              SELECT 1
              FROM cycling_platform_raw.activity_streams streams
              WHERE streams.activity_id = activities.activity_id
                AND streams.stream_type = 'latlng'
            )
          )
        LIMIT 1000
      ",
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "trainerroad_power_pre_cutover_exclusion_only_applies_to_trainerroad",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = "
        SELECT
          activities.activity_id,
          activities.activity_name,
          activities.start_datetime_utc,
          activities.sport_type,
          activities.gear_id,
          activities.power_source_type,
          activities.is_power_record_eligible,
          activities.power_record_exclusion_reason,
          activities.power_classification_rule
        FROM cycling_platform_silver.activities activities
        INNER JOIN cycling_platform_raw.activities raw
          ON raw.activity_id = activities.activity_id
        WHERE activities.is_device_watts = 1
          AND activities.power_meter_cutover_at IS NOT NULL
          AND activities.start_datetime_utc < activities.power_meter_cutover_at
          AND activities.power_record_exclusion_reason =
            'trainerroad_virtual_power_before_roller_bike_power_cutover'
          AND LOWER(CONCAT_WS(
            ' ',
            COALESCE(activities.activity_name, ''),
            COALESCE(JSON_UNQUOTE(JSON_EXTRACT(raw.raw_payload, '$.external_id')), ''),
            COALESCE(JSON_UNQUOTE(JSON_EXTRACT(raw.raw_payload, '$.device_name')), '')
          )) NOT LIKE '%trainerroad%'
        LIMIT 1000
      ",
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "trainerroad_power_pre_cutover_trainerroad_not_eligible",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = "
        SELECT
          activities.activity_id,
          activities.activity_name,
          activities.start_datetime_utc,
          activities.power_source_type,
          activities.is_measured_power,
          activities.is_power_record_eligible,
          activities.power_record_exclusion_reason,
          activities.power_classification_rule
        FROM cycling_platform_silver.activities activities
        INNER JOIN cycling_platform_raw.activities raw
          ON raw.activity_id = activities.activity_id
        LEFT JOIN cycling_platform_admin.activity_power_overrides overrides
          ON overrides.activity_id = activities.activity_id
         AND overrides.is_active = 1
        WHERE activities.power_meter_cutover_at IS NOT NULL
          AND activities.start_datetime_utc < activities.power_meter_cutover_at
          AND (
            activities.is_device_watts = 1
            OR activities.average_power_watts IS NOT NULL
            OR activities.weighted_average_power_watts IS NOT NULL
          )
          AND LOWER(CONCAT_WS(
            ' ',
            COALESCE(activities.activity_name, ''),
            COALESCE(JSON_UNQUOTE(JSON_EXTRACT(raw.raw_payload, '$.external_id')), ''),
            COALESCE(JSON_UNQUOTE(JSON_EXTRACT(raw.raw_payload, '$.device_name')), '')
          )) LIKE '%trainerroad%'
          AND overrides.activity_id IS NULL
          AND (
            activities.power_source_type <> 'virtual'
            OR activities.is_measured_power <> 0
            OR activities.is_power_record_eligible <> 0
            OR activities.power_record_exclusion_reason <>
              'trainerroad_virtual_power_before_roller_bike_power_cutover'
            OR activities.power_classification_rule <>
              'trainerroad_virtual_power_before_roller_bike_power_cutover'
          )
        LIMIT 1000
      ",
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "power_source_pre_cutover_outdoor_device_watts_preserved",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = "
        SELECT
          activities.activity_id,
          activities.activity_name,
          activities.start_datetime_utc,
          activities.sport_type,
          activities.gear_id,
          activities.power_source_type,
          activities.is_measured_power,
          activities.is_power_record_eligible,
          activities.power_record_exclusion_reason
        FROM cycling_platform_silver.activities activities
        INNER JOIN cycling_platform_raw.activities raw
          ON raw.activity_id = activities.activity_id
        WHERE activities.is_device_watts = 1
          AND activities.power_meter_cutover_at IS NOT NULL
          AND activities.start_datetime_utc < activities.power_meter_cutover_at
          AND activities.sport_type IN (
            'Ride',
            'GravelRide',
            'MountainBikeRide',
            'EBikeRide',
            'Handcycle'
          )
          AND activities.sport_type <> 'VirtualRide'
          AND COALESCE(activities.is_trainer, 0) = 0
          AND LOWER(CONCAT_WS(
            ' ',
            COALESCE(activities.activity_name, ''),
            COALESCE(JSON_UNQUOTE(JSON_EXTRACT(raw.raw_payload, '$.external_id')), ''),
            COALESCE(JSON_UNQUOTE(JSON_EXTRACT(raw.raw_payload, '$.device_name')), '')
          )) NOT LIKE '%trainerroad%'
          AND EXISTS (
            SELECT 1
            FROM cycling_platform_raw.activity_streams streams
            WHERE streams.activity_id =
              activities.activity_id
              AND streams.stream_type = 'latlng'
          )
          AND (
            activities.power_source_type <> 'measured'
            OR activities.is_measured_power <> 1
            OR activities.is_power_record_eligible <> 1
            OR activities.power_record_exclusion_reason IS NOT NULL
          )
        LIMIT 1000
      ",
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  dplyr::bind_rows(checks)
}

gold_activity_achievements_publication_checks <- function(
  connection,
  config = list(),
  check_scope = "gold_publication",
  per_check_timeout_seconds = NULL,
  deadline = NULL
) {
  calculation_version <- gold_activity_achievements_calculation_version(
    config = config
  )

  calculation_version_sql <- gold_validation_sql_strings(
    connection = connection,
    values = calculation_version
  )

  achievement_types_sql <- gold_validation_sql_strings(
    connection = connection,
    values = c(
      "power_best_effort",
      "longest_distance",
      "longest_moving_duration",
      "highest_elevation_gain"
    )
  )

  comparison_scopes_sql <- gold_validation_sql_strings(
    connection = connection,
    values = c(
      "all_time",
      "calendar_year"
    )
  )

  durations <- config$transforms$gold_best_effort_durations

  if (is.null(durations)) {
    durations <- default_best_effort_durations()
  }

  durations_sql <- gold_validation_sql_values(
    as.integer(durations)
  )

  checks <- list()

  table_exists <- validation_table_exists(
    connection = connection,
    table_schema = "cycling_platform_gold",
    table_name = "activity_achievements"
  )

  checks <- append_validation_result(
    checks,
    validation_named_table_exists_result(
      table_exists = table_exists,
      check_name = "gold_activity_achievements_table_exists",
      check_scope = check_scope,
      table_schema = "cycling_platform_gold",
      table_name = "activity_achievements"
    )
  )

  if (!isTRUE(table_exists)) {
    return(dplyr::bind_rows(checks))
  }

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_achievements_latest_transform_success",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = "
        WITH latest AS (
          SELECT run_status, completed_at
          FROM cycling_platform_admin.transform_run
          WHERE layer_name = 'gold'
            AND entity_name = 'activity_achievements'
          ORDER BY transform_run_id DESC
          LIMIT 1
        )
        SELECT 'missing_or_failed_latest_gold_achievement_transform' AS issue_type
        FROM DUAL
        WHERE NOT EXISTS (
          SELECT 1
          FROM latest
          WHERE run_status = 'SUCCESS'
            AND completed_at IS NOT NULL
        )
      ",
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_achievements_latest_transform_fresh",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = "
        WITH achievements AS (
          SELECT completed_at
          FROM cycling_platform_admin.transform_run
          WHERE layer_name = 'gold'
            AND entity_name = 'activity_achievements'
            AND run_status = 'SUCCESS'
          ORDER BY transform_run_id DESC
          LIMIT 1
        ),
        best_efforts AS (
          SELECT completed_at
          FROM cycling_platform_admin.transform_run
          WHERE layer_name = 'gold'
            AND entity_name = 'activity_best_efforts'
            AND run_status = 'SUCCESS'
          ORDER BY transform_run_id DESC
          LIMIT 1
        )
        SELECT
          achievements.completed_at AS achievements_completed_at,
          best_efforts.completed_at AS best_efforts_completed_at
        FROM best_efforts
        LEFT JOIN achievements
          ON 1 = 1
        WHERE best_efforts.completed_at IS NOT NULL
          AND (
            achievements.completed_at IS NULL
            OR achievements.completed_at < best_efforts.completed_at
          )
      ",
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_achievements_duplicate_business_key",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = "
        SELECT
          activity_id,
          achievement_type,
          metric_name,
          duration_seconds,
          comparison_scope,
          comparison_period_start,
          comparison_period_end,
          COUNT(*) AS issue_count
        FROM cycling_platform_gold.activity_achievements
        GROUP BY
          activity_id,
          achievement_type,
          metric_name,
          duration_seconds,
          comparison_scope,
          comparison_period_start,
          comparison_period_end
        HAVING COUNT(*) > 1
        LIMIT 1000
      ",
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_achievements_orphaned_activity_ids",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = "
        SELECT achievements.activity_id
        FROM cycling_platform_gold.activity_achievements achievements
        LEFT JOIN cycling_platform_silver.activities activities
          ON activities.activity_id = achievements.activity_id
        WHERE activities.activity_id IS NULL
        GROUP BY achievements.activity_id
        LIMIT 1000
      ",
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_achievements_types_valid",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = glue::glue("
        SELECT DISTINCT achievement_type
        FROM cycling_platform_gold.activity_achievements
        WHERE achievement_type NOT IN ({achievement_types_sql})
        LIMIT 1000
      "),
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_achievements_scopes_valid",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = glue::glue("
        SELECT DISTINCT comparison_scope
        FROM cycling_platform_gold.activity_achievements
        WHERE comparison_scope NOT IN ({comparison_scopes_sql})
        LIMIT 1000
      "),
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_achievements_power_durations_valid",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = glue::glue("
        SELECT DISTINCT duration_seconds
        FROM cycling_platform_gold.activity_achievements
        WHERE achievement_type = 'power_best_effort'
          AND duration_seconds NOT IN ({durations_sql})
        LIMIT 1000
      "),
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_achievements_values_valid",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = "
        SELECT
          activity_achievement_key,
          metric_value,
          days_since_previous_best
        FROM cycling_platform_gold.activity_achievements
        WHERE metric_value IS NULL
           OR metric_value <= 0
           OR days_since_previous_best < 0
        LIMIT 1000
      ",
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_achievements_calculation_version_current",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = glue::glue("
        SELECT
          activity_achievement_key,
          calculation_version
        FROM cycling_platform_gold.activity_achievements
        WHERE calculation_version IS NULL
           OR calculation_version = ''
           OR calculation_version <> {calculation_version_sql}
        LIMIT 1000
      "),
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_achievements_power_eligible_only",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = "
        SELECT
          achievements.activity_achievement_key,
          achievements.activity_id,
          achievements.duration_seconds,
          best_efforts.is_record_eligible
        FROM cycling_platform_gold.activity_achievements achievements
        INNER JOIN cycling_platform_gold.activity_best_efforts best_efforts
          ON best_efforts.activity_id = achievements.activity_id
         AND best_efforts.metric_name = 'watts'
         AND best_efforts.duration_seconds = achievements.duration_seconds
        WHERE achievements.achievement_type = 'power_best_effort'
          AND best_efforts.is_record_eligible <> 1
        LIMIT 1000
      ",
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  dplyr::bind_rows(checks)
}

gold_publication_checks <- function(
  connection,
  config = list(),
  check_scope = "gold_publication",
  per_check_timeout_seconds = NULL,
  deadline = NULL
) {
  dplyr::bind_rows(
    gold_activity_best_efforts_publication_checks(
      connection = connection,
      config = config,
      check_scope = check_scope,
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    ),
    gold_activity_achievements_publication_checks(
      connection = connection,
      config = config,
      check_scope = check_scope,
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )
}

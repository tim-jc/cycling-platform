power_source_classification_version <- function(config = list()) {
  version <- config$transforms$power_source_classification_version

  if (is.null(version) || !nzchar(version)) {
    return("power_source_classification_v1")
  }

  as.character(version)
}

trainerroad_power_cutover_gear_id <- function(config = list()) {
  gear_id <- config$transforms$trainerroad_power_cutover_gear_id

  if (is.null(gear_id) || !nzchar(gear_id)) {
    return("b2708460")
  }

  as.character(
    unlist(
      gear_id,
      use.names = FALSE
    )[[1]]
  )
}

power_source_cutover_gear_ids <- function(config = list()) {
  trainerroad_power_cutover_gear_id(config)
}

ensure_table_column <- function(
  connection,
  table_schema,
  table_name,
  column_name,
  column_definition
) {
  table_exists <- DBI::dbGetQuery(
    conn = connection,
    statement = "
      SELECT COUNT(*) AS table_count
      FROM information_schema.TABLES
      WHERE TABLE_SCHEMA = ?
        AND TABLE_NAME = ?
    ",
    params = list(
      table_schema,
      table_name
    )
  )$table_count[[1]]

  if (table_exists == 0) {
    return(invisible(FALSE))
  }

  exists <- DBI::dbGetQuery(
    conn = connection,
    statement = "
      SELECT COUNT(*) AS column_count
      FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = ?
        AND TABLE_NAME = ?
        AND COLUMN_NAME = ?
    ",
    params = list(
      table_schema,
      table_name,
      column_name
    )
  )$column_count[[1]]

  if (exists > 0) {
    return(invisible(FALSE))
  }

  DBI::dbExecute(
    conn = connection,
    statement = glue::glue(
      "ALTER TABLE {table_schema}.{table_name} ",
      "ADD COLUMN {column_name} {column_definition}"
    )
  )

  invisible(TRUE)
}

ensure_power_source_classification_schema <- function(connection) {
  execute_sql_file(
    sql_file = file.path(
      "sql",
      "admin",
      "070_create_power_source_classification.sql"
    ),
    connection = connection
  )

  ensure_table_column(
    connection = connection,
    table_schema = "cycling_platform_admin",
    table_name = "power_source_classification",
    column_name = "derived_supporting_gear_id",
    column_definition = "VARCHAR(50) NULL"
  )

  silver_columns <- list(
    power_source_type = "VARCHAR(50) NULL",
    power_source_status = "VARCHAR(50) NULL",
    is_measured_power = "TINYINT(1) NOT NULL DEFAULT 0",
    is_power_record_eligible = "TINYINT(1) NOT NULL DEFAULT 0",
    power_record_exclusion_reason = "VARCHAR(150) NULL",
    power_classification_rule = "VARCHAR(150) NULL",
    power_classification_method = "VARCHAR(150) NULL",
    power_classification_version = "VARCHAR(50) NULL",
    power_meter_cutover_at = "DATETIME NULL"
  )

  for (column_name in names(silver_columns)) {
    ensure_table_column(
      connection = connection,
      table_schema = "cycling_platform_silver",
      table_name = "activities",
      column_name = column_name,
      column_definition = silver_columns[[column_name]]
    )
  }

  gold_columns <- list(
    is_record_eligible = "TINYINT(1) NOT NULL DEFAULT 1",
    record_exclusion_reason = "VARCHAR(150) NULL",
    source_classification = "VARCHAR(50) NULL",
    power_classification_version = "VARCHAR(50) NULL"
  )

  for (column_name in names(gold_columns)) {
    ensure_table_column(
      connection = connection,
      table_schema = "cycling_platform_gold",
      table_name = "activity_best_efforts",
      column_name = column_name,
      column_definition = gold_columns[[column_name]]
    )
  }

  invisible(TRUE)
}

power_source_sql_placeholders <- function(values) {
  paste(
    rep("?", length(values)),
    collapse = ", "
  )
}

derive_power_meter_cutover <- function(
  connection,
  approved_gear_ids = "b2708460"
) {
  approved_gear_ids <- as.character(approved_gear_ids)

  stopifnot(length(approved_gear_ids) > 0)

  DBI::dbGetQuery(
    conn = connection,
    statement = paste0(
      "
      SELECT
        activity_id,
        start_datetime_utc,
        gear_id
      FROM cycling_platform_raw.activities activities
      WHERE is_device_watts = 1
        AND gear_id IN (",
      power_source_sql_placeholders(approved_gear_ids),
      ")
        AND (
          average_power_watts IS NOT NULL
          OR weighted_average_power_watts IS NOT NULL
          OR EXISTS (
            SELECT 1
            FROM cycling_platform_raw.activity_streams power_streams
            WHERE power_streams.activity_id = activities.activity_id
              AND power_streams.stream_type = 'watts'
          )
        )
        AND start_datetime_utc IS NOT NULL
        AND sport_type IN (
          'Ride',
          'GravelRide',
          'MountainBikeRide',
          'EBikeRide',
          'Handcycle'
        )
        AND sport_type <> 'VirtualRide'
        AND COALESCE(
          JSON_UNQUOTE(JSON_EXTRACT(raw_payload, '$.trainer')),
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
          COALESCE(activity_name, ''),
          COALESCE(JSON_UNQUOTE(JSON_EXTRACT(raw_payload, '$.external_id')), ''),
          COALESCE(JSON_UNQUOTE(JSON_EXTRACT(raw_payload, '$.device_name')), '')
        )) NOT LIKE '%trainerroad%'
      ORDER BY start_datetime_utc, activity_id
      LIMIT 1
    "
    ),
    params = as.list(approved_gear_ids)
  )
}

refresh_power_source_classification <- function(
  connection,
  config = list()
) {
  ensure_power_source_classification_schema(connection)

  rule_version <- power_source_classification_version(config)
  trainerroad_cutover_gear_id <- trainerroad_power_cutover_gear_id(config)

  cutoff <- derive_power_meter_cutover(
    connection = connection,
    approved_gear_ids = trainerroad_cutover_gear_id
  )

  derived_cutover_at <- if (nrow(cutoff) == 0) {
    NA
  } else {
    cutoff$start_datetime_utc[[1]]
  }

  supporting_activity_id <- if (nrow(cutoff) == 0) {
    bit64::as.integer64(NA)
  } else {
    cutoff$activity_id[[1]]
  }

  supporting_gear_id <- if (nrow(cutoff) == 0) {
    NA_character_
  } else {
    cutoff$gear_id[[1]]
  }

  existing <- DBI::dbGetQuery(
    conn = connection,
    statement = "
      SELECT manual_cutover_at
      FROM cycling_platform_admin.power_source_classification
      WHERE classification_name = 'strava_power_meter_cutover'
      LIMIT 1
    "
  )

  manual_cutover_at <- if (nrow(existing) == 0) {
    NA
  } else {
    existing$manual_cutover_at[[1]]
  }

  effective_cutover_at <- if (!is.na(manual_cutover_at)) {
    manual_cutover_at
  } else {
    derived_cutover_at
  }

  DBI::dbExecute(
    conn = connection,
    statement = "
      INSERT INTO cycling_platform_admin.power_source_classification (
        classification_name,
        derived_cutover_at,
        derived_supporting_activity_id,
        derived_supporting_gear_id,
        derivation_method,
        manual_cutover_at,
        effective_cutover_at,
        rule_version,
        reason,
        is_active,
        derived_at
      )
      VALUES (
        'strava_power_meter_cutover',
        ?,
        ?,
        ?,
        'earliest_outdoor_device_watts_on_trainerroad_roller_bike',
        ?,
        ?,
        ?,
        'Inferred from earliest genuine outdoor ride where Strava reports device watts on the TrainerRoad roller bike.',
        1,
        UTC_TIMESTAMP()
      )
      ON DUPLICATE KEY UPDATE
        derived_cutover_at = VALUES(derived_cutover_at),
        derived_supporting_activity_id = VALUES(derived_supporting_activity_id),
        derived_supporting_gear_id = VALUES(derived_supporting_gear_id),
        derivation_method = VALUES(derivation_method),
        effective_cutover_at = VALUES(effective_cutover_at),
        rule_version = VALUES(rule_version),
        reason = VALUES(reason),
        is_active = VALUES(is_active),
        derived_at = VALUES(derived_at)
    ",
    params = list(
      derived_cutover_at,
      as.character(supporting_activity_id),
      supporting_gear_id,
      manual_cutover_at,
      effective_cutover_at,
      rule_version
    )
  )

  message(glue::glue(
    "Power source classification refreshed: cutoff={effective_cutover_at}, ",
    "supporting_activity_id={supporting_activity_id}, ",
    "supporting_gear_id={supporting_gear_id}, version={rule_version}."
  ))

  invisible(data.frame(
    effective_cutover_at = effective_cutover_at,
    supporting_activity_id = as.character(supporting_activity_id),
    supporting_gear_id = supporting_gear_id,
    rule_version = rule_version
  ))
}

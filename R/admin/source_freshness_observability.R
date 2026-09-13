source_entity_newest_data_queries <- function() {
  c(
    activities = "SELECT MAX(start_datetime_utc) value FROM cycling_platform_raw.activities",
    gear = "SELECT MAX(source_observed_at) value FROM cycling_platform_raw.gear_observations",
    activity_details = "SELECT MAX(retrieved_at) value FROM cycling_platform_raw.activity_details",
    activity_streams = "SELECT MAX(retrieved_at) value FROM cycling_platform_raw.activity_streams",
    activity_laps = "SELECT MAX(retrieved_at) value FROM cycling_platform_raw.activity_laps",
    google_health_heart_rate = "SELECT MAX(TIMESTAMP(activity_date)) value FROM cycling_platform_raw.google_health_heart_rate_responses",
    google_health_sleep_logs = "SELECT MAX(COALESCE(end_physical_time, start_physical_time)) value FROM cycling_platform_raw.google_health_sleep_logs",
    google_health_exercise = "SELECT MAX(COALESCE(interval_end_time, interval_start_time)) value FROM cycling_platform_raw.google_health_exercise",
    google_health_daily_resting_heart_rate = "SELECT MAX(TIMESTAMP(activity_date)) value FROM cycling_platform_raw.google_health_daily_resting_heart_rate",
    google_health_daily_heart_rate_variability = "SELECT MAX(TIMESTAMP(activity_date)) value FROM cycling_platform_raw.google_health_daily_heart_rate_variability",
    google_health_daily_respiratory_rate = "SELECT MAX(TIMESTAMP(activity_date)) value FROM cycling_platform_raw.google_health_daily_respiratory_rate"
  )
}

record_source_freshness_observations <- function(connection, run_id, pipeline_run_id = NULL) {
  entities <- DBI::dbGetQuery(
    connection,
    "SELECT run_entity_id, source_id, entity_name
       FROM cycling_platform_admin.etl_run_entity
      WHERE run_id = ? ORDER BY run_entity_id",
    params = list(run_id)
  )
  queries <- source_entity_newest_data_queries()
  unknown <- setdiff(entities$entity_name, names(queries))
  if (length(unknown) > 0L) {
    stop("No source-freshness contract for Raw entity: ", paste(unique(unknown), collapse = ", "), call. = FALSE)
  }
  for (index in seq_len(nrow(entities))) {
    newest <- DBI::dbGetQuery(connection, unname(queries[[entities$entity_name[[index]]]]))$value[[1]]
    DBI::dbExecute(
      connection,
      "INSERT INTO cycling_platform_admin.source_freshness_observation
         (pipeline_run_id, run_id, run_entity_id, source_id, entity_name,
          newest_source_data_at, observed_at)
       VALUES (?, ?, ?, ?, ?, ?, UTC_TIMESTAMP())
       ON DUPLICATE KEY UPDATE
         newest_source_data_at = VALUES(newest_source_data_at),
         observed_at = VALUES(observed_at)",
      params = list(
        if (is.null(pipeline_run_id)) NA_integer_ else pipeline_run_id,
        run_id, entities$run_entity_id[[index]], entities$source_id[[index]],
        entities$entity_name[[index]],
        if (is.na(newest)) as.POSIXct(NA, tz = "UTC") else as.POSIXct(newest, tz = "UTC")
      )
    )
  }
  invisible(nrow(entities))
}

#' Audit activity-to-gear resolution
report_gear_resolution <- function(connection) {
  DBI::dbGetQuery(
    connection,
    "
      SELECT
        activities.gear_id,
        CASE WHEN gear.gear_id IS NULL THEN 'UNRESOLVED' ELSE 'RESOLVED' END
          AS resolution_status,
        gear.gear_name,
        COUNT(*) AS activity_count,
        MIN(activities.start_date_local) AS earliest_activity_date,
        MAX(activities.start_date_local) AS latest_activity_date
      FROM cycling_platform_silver.activities activities
      LEFT JOIN cycling_platform_silver.gear gear
        ON gear.gear_id = activities.gear_id
      WHERE activities.gear_id IS NOT NULL
      GROUP BY activities.gear_id, gear.gear_id, gear.gear_name
      ORDER BY resolution_status DESC, activity_count DESC, activities.gear_id
    "
  )
}

#' Contract query for ride-summary consumers
#'
#' Consumers join Silver activities to this projection by activity_id. Gear
#' display semantics remain outside ingestion and canonical transforms.
get_activity_gear_display <- function(connection) {
  result <- DBI::dbGetQuery(
    connection,
    "
      SELECT
        activities.activity_id,
        activities.gear_id,
        gear.gear_name
      FROM cycling_platform_silver.activities activities
      LEFT JOIN cycling_platform_silver.gear gear
        ON gear.gear_id = activities.gear_id
    "
  )

  dplyr::mutate(
    result,
    gear_display_name = resolve_activity_gear_name(gear_id, gear_name)
  )
}

resolve_activity_gear_name <- function(gear_id, gear_name) {
  dplyr::case_when(
    is.na(gear_id) | !nzchar(gear_id) ~ "Not recorded",
    !is.na(gear_name) & nzchar(gear_name) ~ gear_name,
    TRUE ~ paste0("Unknown gear (", gear_id, ")")
  )
}

#' Database-independent reference model for the Silver gear selection rules
build_silver_gear_rows <- function(observations, latest_successful_run_id) {
  if (nrow(observations) == 0) {
    return(tibble::tibble())
  }

  observations |>
    dplyr::group_by(gear_id) |>
    dplyr::arrange(
      dplyr::desc(last_observed_at),
      .by_group = TRUE
    ) |>
    dplyr::summarise(
      source_id = dplyr::first(source_id),
      gear_type = dplyr::first(gear_type),
      gear_name = dplyr::first(gear_name),
      is_primary = dplyr::first(is_primary),
      source_distance_metres = dplyr::first(distance_metres),
      first_observed_at = min(first_observed_at),
      last_observed_at = max(last_observed_at),
      source_observation_run_id = dplyr::first(run_id),
      source_payload_hash = dplyr::first(payload_hash),
      is_current = any(
        run_id == latest_successful_run_id &
          observed_in_current_collection
      ),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      is_historical = !is_current,
      resolution_status = "RESOLVED",
      transform_version = "strava_gear_v1"
    )
}

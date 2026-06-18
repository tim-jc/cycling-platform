#' Get Activities
#'
#' Retrieve activities from the Strava API for a specified time window.
#'
#' @param run_id Integer ETL run identifier.
#' @param source_id Integer source identifier.
#' @param refresh_days Number of days to look back.
#'
#' @return Tibble containing one row per activity.
get_activities <- function(
  run_id,
  source_id,
  refresh_days
) {
  token <- get_access_token()

  response <- httr2::request(
    "https://www.strava.com/api/v3/athlete/activities"
  ) |>
    httr2::req_auth_bearer_token(token) |>
    httr2::req_url_query(
      after = as.integer(
        as.numeric(
          Sys.time() - lubridate::days(refresh_days)
        )
      ),
      per_page = 200,
      page = 1
    ) |>
    httr2::req_perform()

  body <- httr2::resp_body_json(
    response,
    simplifyVector = TRUE
  )

  body_tbl <- tibble::as_tibble(body)

  if (nrow(body_tbl) == 200) {
    warning(
      "Activity result set reached per_page limit; pagination not yet implemented."
    )
  }

  optional_columns <- c(
    "average_cadence",
    "average_heartrate",
    "average_watts",
    "weighted_average_watts",
    "kilojoules",
    "gear_id",
    "device_watts",
    "timezone"
  )

  missing_columns <- setdiff(
    optional_columns,
    names(body_tbl)
  )

  for (column in missing_columns) {
    body_tbl[[column]] <- NA
  }

  raw_payload <- purrr::map_chr(
    seq_len(nrow(body_tbl)),
    \(i) {
      jsonlite::toJSON(
        body_tbl[i, ],
        auto_unbox = TRUE,
        null = "null"
      )
    }
  )

  body_tbl |>
    dplyr::mutate(
      run_id = run_id,
      source_id = source_id,
      retrieved_at = Sys.time(),
      athlete_id = athlete$id,
      raw_payload = raw_payload
    ) |>
    dplyr::transmute(
      run_id,
      source_id,
      retrieved_at,
      raw_payload,

      activity_id = id,

      athlete_id,

      activity_name = name,

      sport_type,

      start_datetime_utc = lubridate::ymd_hms(
        start_date,
        tz = "UTC"
      ),

      start_datetime_local = lubridate::ymd_hms(
        start_date_local
      ),

      timezone_name = timezone,

      distance_metres = distance,

      moving_time_seconds = moving_time,

      elapsed_time_seconds = elapsed_time,

      elevation_gain_metres = total_elevation_gain,

      average_speed_metres_per_second = average_speed,

      average_cadence_rpm = average_cadence,

      average_heartrate_bpm = average_heartrate,

      average_power_watts = average_watts,

      weighted_average_power_watts = weighted_average_watts,

      energy_kilojoules = kilojoules,

      gear_id,

      is_device_watts = device_watts
    )
}

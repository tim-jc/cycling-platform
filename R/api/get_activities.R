#' Get Activities
#'
#' Get activities from Strava API for specified time window
#' @param refresh_days Number of days to look back when retrieving activities.
#'
#' @return Tibble containing one row per activity and raw_payload.
get_activities <- function(run_id, source_id, refresh_days) {
  token <- get_access_token()

  # TODO: implement pagination
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
  if (length(body) == 0) {
    return(tibble::tibble())
  }

  retrieved_at <- Sys.time()

  body_tbl <- tibble::as_tibble(body) |>
    dplyr::mutate(
      run_id = run_id,
      source_id = source_id,
      retrieved_at = retrieved_at,
      athlete_id = purrr::map_int(athlete, "id"),
      raw_payload = purrr::map_chr(
        body,
        ~ jsonlite::toJSON(
          .x,
          auto_unbox = TRUE,
          null = "null"
        )
      ),
      start_datetime_utc = lubridate::ymd_hms(
        start_date,
        tz = "UTC"
      ),
      start_datetime_local = lubridate::ymd_hms(
        start_date_local
      )
    ) |>
    dplyr::select(
      run_id,
      source_id,
      retrieved_at,
      raw_payload,
      activity_id = id,
      athlete_id,
      activity_name = name,
      sport_type,
      start_datetime_utc,
      start_datetime_local,
      timezone_name = timezone,
      distance_metres = distance,
      moving_time_seconds = moving_time,
      elapsed_time_seconds = elapsed_time,
      elevation_gain_metres = total_elevation_gain,
      average_speed_metres_per_second = average_speed,
      average_cadence_rpm = average_cadence,
      average_power_watts = average_watts,
      weighted_average_power_watts = weighted_average_watts,
      average_heartrate_bpm = average_heartrate,
      energy_kilojoules = kilojoules,
      gear_id,
      is_device_watts = device_watts
    )

  return(body_tbl)
}

#' Get Activities
#'
#' Get activities from Strava API for specified time window
#' @param refresh_days Number of days to look back when retrieving activities.
#'
#' @return Tibble containing one row per activity and raw_payload.
get_activities <- function(refresh_days) {
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

  tibble::as_tibble(body)
}

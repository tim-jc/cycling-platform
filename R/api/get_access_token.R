#' Get Access Token
#'
#' Refresh Strava token
#' @return Strava access token.
get_access_token <- function() {
  stopifnot(
    nzchar(Sys.getenv("STRAVA_CLIENT_ID")),
    nzchar(Sys.getenv("STRAVA_CLIENT_SECRET")),
    nzchar(Sys.getenv("STRAVA_REFRESH_TOKEN"))
  )

  response <- httr2::request(
    "https://www.strava.com/oauth/token"
  ) |>
    httr2::req_body_json(
      list(
        client_id = Sys.getenv("STRAVA_CLIENT_ID"),
        client_secret = Sys.getenv("STRAVA_CLIENT_SECRET"),
        refresh_token = Sys.getenv("STRAVA_REFRESH_TOKEN"),
        grant_type = "refresh_token"
      )
    ) |>
    httr2::req_perform()

  body <- httr2::resp_body_json(response)

  body$access_token
}

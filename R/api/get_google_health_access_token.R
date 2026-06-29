#' Get Google Health Access Token
#'
#' Refresh Google Health OAuth token.
#'
#' @return Google Health access token.
get_google_health_access_token <- function() {
  stopifnot(
    nzchar(Sys.getenv("GOOGLE_HEALTH_CLIENT_ID")),
    nzchar(Sys.getenv("GOOGLE_HEALTH_CLIENT_SECRET")),
    nzchar(Sys.getenv("GOOGLE_HEALTH_REFRESH_TOKEN"))
  )

  response <- httr2::request(
    "https://oauth2.googleapis.com/token"
  ) |>
    httr2::req_auth_basic(
      Sys.getenv("GOOGLE_HEALTH_CLIENT_ID"),
      Sys.getenv("GOOGLE_HEALTH_CLIENT_SECRET")
    ) |>
    httr2::req_body_form(
      grant_type = "refresh_token",
      refresh_token = Sys.getenv("GOOGLE_HEALTH_REFRESH_TOKEN")
    ) |>
    httr2::req_perform()

  body <- httr2::resp_body_json(
    response,
    simplifyVector = TRUE
  )

  if (!is.null(body$refresh_token)) {
    update_renviron(
      key = "GOOGLE_HEALTH_REFRESH_TOKEN",
      value = body$refresh_token
    )
  }

  body$access_token
}

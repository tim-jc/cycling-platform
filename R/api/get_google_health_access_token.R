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
    httr2::req_body_form(
      client_id = Sys.getenv("GOOGLE_HEALTH_CLIENT_ID"),
      client_secret = Sys.getenv("GOOGLE_HEALTH_CLIENT_SECRET"),
      grant_type = "refresh_token",
      refresh_token = Sys.getenv("GOOGLE_HEALTH_REFRESH_TOKEN")
    ) |>
    httr2::req_error(
      is_error = \(response) FALSE
    ) |>
    httr2::req_perform()

  body <- httr2::resp_body_json(
    response,
    simplifyVector = TRUE
  )

  if (httr2::resp_status(response) >= 400) {
    stop(
      paste(
        "Google Health token refresh failed:",
        paste(
          unlist(body),
          collapse = " "
        )
      ),
      call. = FALSE
    )
  }

  refresh_token <- body[["refresh_token"]]

  if (!is.null(refresh_token)) {
    update_renviron(
      key = "GOOGLE_HEALTH_REFRESH_TOKEN",
      value = refresh_token
    )
  }

  body[["access_token"]]
}

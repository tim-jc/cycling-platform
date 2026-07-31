#' Load Strava Refresh Configuration
#'
#' @param environment Named environment-variable vector.
#'
#' @return Named credential list without logging secret values.
load_strava_refresh_config <- function(environment = Sys.getenv()) {
  required_keys <- c(
    "STRAVA_CLIENT_ID",
    "STRAVA_CLIENT_SECRET",
    "STRAVA_REFRESH_TOKEN"
  )
  values <- environment[required_keys]
  values[is.na(values)] <- ""
  missing_keys <- required_keys[!nzchar(trimws(values))]

  if (length(missing_keys) > 0L) {
    stop(
      "Strava OAuth configuration is incomplete. Missing runtime ",
      "credential(s): ",
      paste(missing_keys, collapse = ", "),
      ". Re-authorise only if the credentials are present but rejected.",
      call. = FALSE
    )
  }

  list(
    client_id = values[["STRAVA_CLIENT_ID"]],
    client_secret = values[["STRAVA_CLIENT_SECRET"]],
    refresh_token = values[["STRAVA_REFRESH_TOKEN"]]
  )
}

#' Get Access Token
#'
#' Refresh Strava token
#' @return Strava access token.
get_access_token <- function() {
  token_config <- load_strava_refresh_config()

  response <- tryCatch(
    httr2::request(
      "https://www.strava.com/oauth/token"
    ) |>
      httr2::req_body_json(
        list(
          client_id = token_config$client_id,
          client_secret = token_config$client_secret,
          refresh_token = token_config$refresh_token,
          grant_type = "refresh_token"
        )
      ) |>
      httr2::req_perform(),
    error = function(e) {
      stop(
        "Strava token refresh failed with configured credentials. ",
        "The credentials may be invalid, expired, revoked, or unable to ",
        "reach Strava. Original error: ",
        conditionMessage(e),
        call. = FALSE
      )
    }
  )

  body <- httr2::resp_body_json(
    response,
    simplifyVector = TRUE
  )

  if (
    is.null(body$access_token) ||
      length(body$access_token) != 1L ||
      is.na(body$access_token) ||
      !nzchar(body$access_token)
  ) {
    stop(
      "Strava token refresh returned an incomplete response: access_token ",
      "was missing. Persistent credentials were not changed.",
      call. = FALSE
    )
  }

  if (
    !is.null(body$refresh_token) &&
      length(body$refresh_token) == 1L &&
      !is.na(body$refresh_token) &&
      nzchar(body$refresh_token)
  ) {
    update_renviron(
      key = "STRAVA_REFRESH_TOKEN",
      value = body$refresh_token
    )
  }

  body$access_token
}

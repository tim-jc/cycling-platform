google_health_token_diagnostics <- function(
  renviron_path = find_project_renviron()
) {
  refresh_token <- Sys.getenv(
    "GOOGLE_HEALTH_REFRESH_TOKEN"
  )

  data.frame(
    renviron_path = renviron_path,
    renviron_exists = file.exists(renviron_path),
    renviron_modified_at = if (file.exists(renviron_path)) {
      as.character(file.info(renviron_path)$mtime)
    } else {
      NA_character_
    },
    client_id_present = nzchar(Sys.getenv("GOOGLE_HEALTH_CLIENT_ID")),
    client_secret_present = nzchar(Sys.getenv("GOOGLE_HEALTH_CLIENT_SECRET")),
    refresh_token_present = nzchar(refresh_token),
    refresh_token_length = nchar(refresh_token),
    refresh_token_prefix = if (nzchar(refresh_token)) {
      substr(refresh_token, 1, 4)
    } else {
      NA_character_
    }
  )
}

load_google_health_token_config <- function(
  renviron_path = find_project_renviron(),
  verbose = FALSE
) {
  if (file.exists(renviron_path)) {
    readRenviron(renviron_path)
  }

  diagnostics <- google_health_token_diagnostics(
    renviron_path = renviron_path
  )

  if (isTRUE(verbose)) {
    message("Google Health token diagnostics:")
    print(diagnostics)
  }

  missing_keys <- c(
    if (!diagnostics$client_id_present) "GOOGLE_HEALTH_CLIENT_ID",
    if (!diagnostics$client_secret_present) "GOOGLE_HEALTH_CLIENT_SECRET",
    if (!diagnostics$refresh_token_present) "GOOGLE_HEALTH_REFRESH_TOKEN"
  )

  if (length(missing_keys) > 0) {
    stop(
      "Google Health OAuth configuration is incomplete. Missing: ",
      paste(
        missing_keys,
        collapse = ", "
      ),
      ". Token file: ",
      renviron_path,
      call. = FALSE
    )
  }

  list(
    client_id = Sys.getenv("GOOGLE_HEALTH_CLIENT_ID"),
    client_secret = Sys.getenv("GOOGLE_HEALTH_CLIENT_SECRET"),
    refresh_token = Sys.getenv("GOOGLE_HEALTH_REFRESH_TOKEN"),
    renviron_path = renviron_path,
    diagnostics = diagnostics
  )
}

save_google_health_refresh_token <- function(
  refresh_token,
  renviron_path = find_project_renviron()
) {
  if (is.null(refresh_token) || !nzchar(refresh_token)) {
    return(invisible(FALSE))
  }

  update_renviron(
    key = "GOOGLE_HEALTH_REFRESH_TOKEN",
    value = refresh_token,
    renviron_path = renviron_path
  )

  invisible(TRUE)
}

#' Get Google Health Access Token
#'
#' Refresh Google Health OAuth token.
#'
#' @param verbose Print token file diagnostics.
#'
#' @return Google Health access token.
get_google_health_access_token <- function(verbose = FALSE) {
  token_config <- load_google_health_token_config(
    verbose = verbose
  )

  response <- httr2::request(
    "https://oauth2.googleapis.com/token"
  ) |>
    httr2::req_body_form(
      client_id = token_config$client_id,
      client_secret = token_config$client_secret,
      grant_type = "refresh_token",
      refresh_token = token_config$refresh_token
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
    diagnostics <- google_health_token_diagnostics(
      renviron_path = token_config$renviron_path
    )

    stop(
      paste(
        "Google Health token refresh failed:",
        paste(
          unlist(body),
          collapse = " "
        ),
        "| token_file:",
        diagnostics$renviron_path,
        "| token_file_modified:",
        diagnostics$renviron_modified_at,
        "| refresh_token_present:",
        diagnostics$refresh_token_present,
        "| refresh_token_length:",
        diagnostics$refresh_token_length,
        "| refresh_token_prefix:",
        diagnostics$refresh_token_prefix
      ),
      call. = FALSE
    )
  }

  refresh_token <- body[["refresh_token"]]

  if (!is.null(refresh_token)) {
    save_google_health_refresh_token(
      refresh_token = refresh_token,
      renviron_path = token_config$renviron_path
    )

    if (isTRUE(verbose)) {
      message(
        "Google Health refresh succeeded; new refresh token was written to ",
        token_config$renviron_path,
        "."
      )
    }
  } else if (isTRUE(verbose)) {
    message(
      "Google Health refresh succeeded; response did not include a new refresh token."
    )
  }

  body[["access_token"]]
}

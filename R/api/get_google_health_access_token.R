google_health_required_scopes <- function() {
  c(
    "https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly",
    "https://www.googleapis.com/auth/googlehealth.sleep.readonly",
    "https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly"
  )
}

google_health_scope_report <- function(
  granted_scopes,
  required_scopes = google_health_required_scopes()
) {
  granted_scopes <- sort(unique(trimws(as.character(granted_scopes))))
  granted_scopes <- granted_scopes[nzchar(granted_scopes)]
  required_scopes <- sort(unique(as.character(required_scopes)))

  list(
    required = required_scopes,
    granted = granted_scopes,
    granted_required = intersect(required_scopes, granted_scopes),
    missing = setdiff(required_scopes, granted_scopes),
    unexpected = setdiff(granted_scopes, required_scopes),
    valid = all(required_scopes %in% granted_scopes)
  )
}

parse_google_health_token_scopes <- function(token_metadata) {
  scopes <- token_metadata$scope

  if (is.null(scopes) || length(scopes) == 0L || is.na(scopes[[1]])) {
    return(character())
  }

  unlist(strsplit(as.character(scopes[[1]]), "[[:space:]]+"))
}

get_google_health_granted_scopes <- function(
  access_token,
  request_perform = httr2::req_perform
) {
  if (length(access_token) != 1L || is.na(access_token) || !nzchar(access_token)) {
    stop("A Google Health access token is required for scope inspection.", call. = FALSE)
  }

  request <- httr2::request("https://oauth2.googleapis.com/tokeninfo") |>
    httr2::req_url_query(access_token = access_token) |>
    httr2::req_error(is_error = \(response) FALSE)

  response <- tryCatch(
    request_perform(request),
    error = function(e) {
      stop(
        "Google Health granted-scope inspection failed before a response was returned.",
        call. = FALSE
      )
    }
  )

  if (httr2::resp_status(response) >= 400L) {
    stop(
      "Google Health granted-scope inspection failed. The access token metadata endpoint rejected the request.",
      call. = FALSE
    )
  }

  metadata <- tryCatch(
    httr2::resp_body_json(response, simplifyVector = TRUE),
    error = function(e) {
      stop(
        "Google Health granted-scope inspection returned malformed metadata.",
        call. = FALSE
      )
    }
  )
  parse_google_health_token_scopes(metadata)
}

format_google_health_scope_name <- function(scope) {
  sub("^https://www[.]googleapis[.]com/auth/", "", scope)
}

assert_google_health_required_scopes <- function(granted_scopes) {
  scope_report <- google_health_scope_report(granted_scopes)

  if (!scope_report$valid) {
    stop(
      "Google Health OAuth scope validation failed. Missing required scopes: ",
      paste(
        vapply(
          scope_report$missing,
          format_google_health_scope_name,
          character(1)
        ),
        collapse = ", "
      ),
      ". Re-authorise with all required scopes; refresh exchange cannot add scopes.",
      call. = FALSE
    )
  }

  scope_report
}

check_google_health_authentication <- function(
  access_token_fetcher = get_google_health_access_token,
  scope_fetcher = get_google_health_granted_scopes,
  verbose = TRUE
) {
  access_token <- access_token_fetcher(verbose = verbose)
  scope_report <- assert_google_health_required_scopes(scope_fetcher(access_token))

  message("Google Health access token refresh succeeded.")
  message("Required scopes: ", length(scope_report$required))
  message("Granted required scopes: ", length(scope_report$granted_required))
  message("Granted scopes:")
  for (scope in scope_report$granted) {
    message("- ", format_google_health_scope_name(scope))
  }

  if (length(scope_report$unexpected) > 0L) {
    message("Unexpected additional scopes:")
    for (scope in scope_report$unexpected) {
      message("- ", format_google_health_scope_name(scope))
    }
  }

  message("Google Health OAuth scope validation succeeded.")
  invisible(scope_report)
}

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
    refresh_token_length = nchar(refresh_token)
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

    error_code <- if (!is.null(body$error)) {
      as.character(body$error[[1]])
    } else {
      "unknown_error"
    }
    error_description <- if (!is.null(body$error_description)) {
      as.character(body$error_description[[1]])
    } else {
      "No OAuth error description returned."
    }

    stop(
      paste(
        "Google Health token refresh failed:",
        error_code,
        error_description,
        "| token_file:",
        diagnostics$renviron_path,
        "| token_file_modified:",
        diagnostics$renviron_modified_at,
        "| refresh_token_present:",
        diagnostics$refresh_token_present,
        "| refresh_token_length:",
        diagnostics$refresh_token_length
      ),
      call. = FALSE
    )
  }

  if (
    is.null(body[["access_token"]]) ||
      length(body[["access_token"]]) != 1L ||
      is.na(body[["access_token"]]) ||
      !nzchar(body[["access_token"]])
  ) {
    stop(
      "Google Health token refresh returned an incomplete response: ",
      "access_token was missing. Persistent credentials were not changed.",
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

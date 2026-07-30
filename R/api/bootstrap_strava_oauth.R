strava_required_scopes <- function() {
  c(
    "read",
    "activity:read_all",
    "profile:read_all"
  )
}

parse_strava_scopes <- function(scopes) {
  if (
    is.null(scopes) ||
      length(scopes) == 0 ||
      is.na(scopes[[1]]) ||
      !nzchar(scopes[[1]])
  ) {
    return(character())
  }

  unique(
    Filter(
      nzchar,
      strsplit(
        scopes[[1]],
        split = "[,[:space:]]+"
      )[[1]]
    )
  )
}

validate_strava_scopes <- function(
  granted_scopes,
  required_scopes = strava_required_scopes()
) {
  granted_scopes <- parse_strava_scopes(
    paste(granted_scopes, collapse = " ")
  )
  missing_scopes <- setdiff(
    required_scopes,
    granted_scopes
  )

  if (length(missing_scopes) > 0) {
    stop(
      "Strava did not grant every required OAuth scope. Required: ",
      paste(required_scopes, collapse = ", "),
      ". Granted: ",
      if (length(granted_scopes) > 0) {
        paste(granted_scopes, collapse = ", ")
      } else {
        "<none reported>"
      },
      ". Missing: ",
      paste(missing_scopes, collapse = ", "),
      ". Repeat authorization and accept every requested permission.",
      call. = FALSE
    )
  }

  invisible(granted_scopes)
}

generate_strava_oauth_state <- function() {
  paste(
    sprintf(
      "%02x",
      as.integer(
        openssl::rand_bytes(32)
      )
    ),
    collapse = ""
  )
}

build_strava_authorization_url <- function(
  client_id = Sys.getenv("STRAVA_CLIENT_ID"),
  redirect_uri = Sys.getenv(
    "STRAVA_REDIRECT_URI",
    unset = "http://localhost"
  ),
  scopes = strava_required_scopes(),
  state = generate_strava_oauth_state()
) {
  if (!nzchar(client_id)) {
    stop(
      "STRAVA_CLIENT_ID is not configured.",
      call. = FALSE
    )
  }

  if (!nzchar(redirect_uri)) {
    stop(
      "The Strava OAuth redirect URI must not be empty.",
      call. = FALSE
    )
  }

  if (!nzchar(state)) {
    stop(
      "The Strava OAuth state value must not be empty.",
      call. = FALSE
    )
  }

  url <- httr2::url_parse(
    "https://www.strava.com/oauth/authorize"
  )
  url$query <- list(
    client_id = client_id,
    redirect_uri = redirect_uri,
    response_type = "code",
    approval_prompt = "force",
    scope = paste(scopes, collapse = ","),
    state = state
  )

  httr2::url_build(url)
}

parse_strava_authorization_redirect <- function(
  redirect_url,
  expected_state,
  expected_redirect_uri = Sys.getenv(
    "STRAVA_REDIRECT_URI",
    unset = "http://localhost"
  )
) {
  if (
    is.null(redirect_url) ||
      length(redirect_url) != 1 ||
      is.na(redirect_url) ||
      !nzchar(redirect_url)
  ) {
    stop(
      "No Strava redirect URL was supplied.",
      call. = FALSE
    )
  }

  parsed <- tryCatch(
    httr2::url_parse(redirect_url),
    error = function(error) NULL
  )

  if (is.null(parsed) || is.null(parsed$query)) {
    stop(
      paste(
        "Paste the complete URL from the browser after Strava redirects.",
        "The URL contains the one-time code, granted scopes, and state needed",
        "for safe validation."
      ),
      call. = FALSE
    )
  }

  expected_redirect <- tryCatch(
    httr2::url_parse(expected_redirect_uri),
    error = function(error) NULL
  )

  normalise_path <- function(path) {
    if (is.null(path) || !nzchar(path)) "/" else path
  }

  redirect_matches <- !is.null(expected_redirect) &&
    identical(parsed$scheme, expected_redirect$scheme) &&
    identical(parsed$hostname, expected_redirect$hostname) &&
    identical(parsed$port, expected_redirect$port) &&
    identical(
      normalise_path(parsed$path),
      normalise_path(expected_redirect$path)
    )

  if (!isTRUE(redirect_matches)) {
    stop(
      "The pasted URL does not match the configured Strava redirect URI (",
      expected_redirect_uri,
      "). Start the helper again and paste the complete Strava redirect.",
      call. = FALSE
    )
  }

  query <- parsed$query

  if (is.null(query$state) || !identical(query$state, expected_state)) {
    stop(
      "Strava authorization state validation failed. Start the helper again.",
      call. = FALSE
    )
  }

  if (!is.null(query$error)) {
    stop(
      "Strava authorization failed: ",
      query$error,
      ".",
      call. = FALSE
    )
  }

  if (is.null(query$code) || !nzchar(query$code)) {
    stop(
      "The Strava redirect URL does not contain an authorization code.",
      call. = FALSE
    )
  }

  granted_scopes <- parse_strava_scopes(query$scope)
  validate_strava_scopes(granted_scopes)

  list(
    code = query$code,
    scopes = granted_scopes
  )
}

build_strava_authorization_code_request <- function(
  code,
  client_id = Sys.getenv("STRAVA_CLIENT_ID"),
  client_secret = Sys.getenv("STRAVA_CLIENT_SECRET")
) {
  if (!nzchar(client_id) || !nzchar(client_secret)) {
    stop(
      paste(
        "Strava OAuth configuration is incomplete.",
        "STRAVA_CLIENT_ID and STRAVA_CLIENT_SECRET are required."
      ),
      call. = FALSE
    )
  }

  if (length(code) != 1 || is.na(code) || !nzchar(code)) {
    stop("The Strava authorization code must not be empty.", call. = FALSE)
  }

  httr2::request(
    "https://www.strava.com/oauth/token"
  ) |>
    httr2::req_body_form(
      client_id = client_id,
      client_secret = client_secret,
      code = code,
      grant_type = "authorization_code"
    ) |>
    httr2::req_error(
      is_error = \(response) FALSE
    )
}

perform_strava_authorization_code_exchange <- function(
  code,
  client_id = Sys.getenv("STRAVA_CLIENT_ID"),
  client_secret = Sys.getenv("STRAVA_CLIENT_SECRET")
) {
  request <- build_strava_authorization_code_request(
    code = code,
    client_id = client_id,
    client_secret = client_secret
  )

  response <- tryCatch(
    httr2::req_perform(request),
    error = function(error) {
      stop(
        paste(
          "The Strava authorization-code exchange could not be completed.",
          "No credentials were changed. Check network connectivity and retry",
          "with a newly generated authorization code."
        ),
        call. = FALSE
      )
    }
  )

  body <- tryCatch(
    httr2::resp_body_json(
      response,
      simplifyVector = TRUE
    ),
    error = function(error) list()
  )

  if (httr2::resp_is_error(response)) {
    stop(
      "Strava rejected the authorization-code exchange (HTTP ",
      httr2::resp_status(response),
      "): ",
      httr2::resp_status_desc(response),
      ". Generate a new authorization URL and try again; codes are short-lived ",
      "and single-use.",
      call. = FALSE
    )
  }

  body
}

validate_strava_token_response <- function(response) {
  required_fields <- c(
    "access_token",
    "refresh_token",
    "scope"
  )
  missing_fields <- required_fields[
    !vapply(
      required_fields,
      \(field) {
        value <- response[[field]]
        !is.null(value) &&
          length(value) > 0 &&
          !is.na(value[[1]]) &&
          nzchar(as.character(value[[1]]))
      },
      logical(1)
    )
  ]

  if (length(missing_fields) > 0) {
    stop(
      "Strava returned an incomplete token response. Missing: ",
      paste(missing_fields, collapse = ", "),
      ". No credentials were changed.",
      call. = FALSE
    )
  }

  granted_scopes <- parse_strava_scopes(response$scope)
  validate_strava_scopes(granted_scopes)

  invisible(granted_scopes)
}

prompt_for_strava_redirect <- function() {
  askpass::askpass(
    paste(
      "Paste the complete Strava redirect URL.",
      "The value will not be echoed or stored in shell history:"
    )
  )
}

bootstrap_strava_oauth <- function(
  redirect_input_fn = prompt_for_strava_redirect,
  exchange_fn = perform_strava_authorization_code_exchange,
  persist_fn = update_renviron,
  state_fn = generate_strava_oauth_state,
  renviron_path = find_project_renviron()
) {
  client_id <- Sys.getenv("STRAVA_CLIENT_ID")
  client_secret <- Sys.getenv("STRAVA_CLIENT_SECRET")

  if (!nzchar(client_id) || !nzchar(client_secret)) {
    stop(
      paste(
        "Strava OAuth configuration is incomplete.",
        "STRAVA_CLIENT_ID and STRAVA_CLIENT_SECRET are required."
      ),
      call. = FALSE
    )
  }

  if (!file.exists(renviron_path)) {
    stop(
      "The persistent credential file does not exist: ",
      renviron_path,
      ". Create and mount it before authorizing Strava.",
      call. = FALSE
    )
  }

  if (file.access(renviron_path, mode = 2) != 0) {
    stop(
      "The persistent credential file is not writable: ",
      renviron_path,
      ".",
      call. = FALSE
    )
  }

  state <- state_fn()
  redirect_uri <- Sys.getenv(
    "STRAVA_REDIRECT_URI",
    unset = "http://localhost"
  )
  authorization_url <- build_strava_authorization_url(
    client_id = client_id,
    redirect_uri = redirect_uri,
    state = state
  )

  message(
    "Open this URL in a browser and approve every requested permission:\n\n",
    authorization_url,
    "\n\nAfter Strava redirects, return here and paste the complete redirect URL."
  )

  redirect <- parse_strava_authorization_redirect(
    redirect_url = redirect_input_fn(),
    expected_state = state,
    expected_redirect_uri = redirect_uri
  )

  message(
    "Authorization redirect validated. Exchanging the one-time code with Strava..."
  )

  response <- exchange_fn(
    code = redirect$code,
    client_id = client_id,
    client_secret = client_secret
  )
  granted_scopes <- validate_strava_token_response(response)

  persist_fn(
    key = "STRAVA_REFRESH_TOKEN",
    value = response$refresh_token,
    renviron_path = renviron_path
  )

  message(
    "Strava authorization succeeded. Granted scopes: ",
    paste(granted_scopes, collapse = ", "),
    ". The refresh token was persisted to ",
    renviron_path,
    ". No token values were printed."
  )

  invisible(
    list(
      scopes = granted_scopes,
      renviron_path = renviron_path
    )
  )
}

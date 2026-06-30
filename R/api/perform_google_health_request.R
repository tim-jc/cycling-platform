#' Perform Google Health API Request
#'
#' Apply common Google Health request behaviour: base URL, bearer auth, timeout,
#' configured pause, and bounded retries for transient failures.
#'
#' @param path Google Health API path.
#' @param config Platform configuration.
#' @param query Named list of query parameters.
#' @param token Optional bearer token. Defaults to a refreshed Google token.
#'
#' @return httr2 response object.
perform_google_health_request <- function(
  path,
  config,
  query = list(),
  token = get_google_health_access_token()
) {
  value_or_default <- function(value, default) {
    if (is.null(value)) {
      return(default)
    }

    value
  }

  api_base_url <- config$sources$google_health$api_base_url

  timeout_seconds <- value_or_default(
    config$ingestion$timeout_seconds,
    60
  )

  max_retries <- value_or_default(
    config$ingestion$max_retries,
    3
  )

  request_pause_seconds <- value_or_default(
    config$ingestion$google_health_request_pause_seconds,
    config$ingestion$request_pause_seconds
  )

  request_pause_seconds <- value_or_default(
    request_pause_seconds,
    0.25
  )

  stopifnot(nzchar(api_base_url))
  stopifnot(timeout_seconds > 0)
  stopifnot(max_retries >= 0)
  stopifnot(request_pause_seconds >= 0)

  request <- httr2::request(
    paste0(api_base_url, path)
  ) |>
    httr2::req_auth_bearer_token(token) |>
    httr2::req_timeout(timeout_seconds) |>
    httr2::req_options(
      connecttimeout = timeout_seconds
    )

  if (length(query) > 0) {
    request <- do.call(
      httr2::req_url_query,
      c(list(request), query)
    )
  }

  total_attempts <- max_retries + 1

  google_health_error_message <- function(response) {
    if (is.null(response$resp)) {
      return(conditionMessage(response))
    }

    body <- tryCatch(
      httr2::resp_body_json(
        response$resp,
        simplifyVector = TRUE
      ),
      error = function(e) NULL
    )

    if (!is.null(body)) {
      return(
        paste(
          unlist(body),
          collapse = " "
        )
      )
    }

    body <- tryCatch(
      httr2::resp_body_string(response$resp),
      error = function(e) NULL
    )

    if (!is.null(body) && nzchar(body)) {
      return(body)
    }

    conditionMessage(response)
  }

  for (attempt in seq_len(total_attempts)) {
    response <- tryCatch(
      httr2::req_perform(request),
      error = function(e) e
    )

    Sys.sleep(request_pause_seconds)

    if (!inherits(response, "error")) {
      return(response)
    }

    if (inherits(response, "httr2_http_429")) {
      retry_after <- NA_character_

      if (!is.null(response$resp)) {
        retry_after <- httr2::resp_header(
          response$resp,
          "retry-after",
          default = NA_character_
        )
      }

      message(glue::glue(
        "Google Health rate limit reached.",
        ifelse(
          is.na(retry_after),
          "",
          paste0(" Retry-After: ", retry_after, ".")
        )
      ))

      stop(response)
    }

    is_retryable <- inherits(response, "httr2_failure") ||
      inherits(response, "httr2_http_500") ||
      inherits(response, "httr2_http_502") ||
      inherits(response, "httr2_http_503") ||
      inherits(response, "httr2_http_504")

    if (!is_retryable) {
      stop(
        paste(
          "Google Health request failed:",
          google_health_error_message(response)
        ),
        call. = FALSE
      )
    }

    if (attempt == total_attempts) {
      message(glue::glue(
        "Google Health request failed after {total_attempts} attempts. ",
        "Error: {conditionMessage(response)}"
      ))

      stop(response)
    }

    sleep_seconds <- 2 ^ (attempt - 1)

    message(glue::glue(
      "Google Health request failed with a transient error; retrying in ",
      "{sleep_seconds}s ({attempt}/{max_retries}). Error: ",
      "{conditionMessage(response)}"
    ))

    Sys.sleep(sleep_seconds)
  }
}

#' Perform Strava API Request
#'
#' Apply common Strava request behaviour: base URL, bearer auth, timeout,
#' and bounded retries for transient failures.
#'
#' @param path Strava API path, for example "/athlete/activities".
#' @param config Platform configuration.
#' @param query Named list of query parameters.
#' @param token Optional bearer token. Defaults to a refreshed Strava token.
#'
#' @return httr2 response object.
perform_strava_request <- function(
  path,
  config,
  query = list(),
  token = get_access_token()
) {
  value_or_default <- function(value, default) {
    if (is.null(value)) {
      return(default)
    }

    value
  }

  parse_rate_limit_header <- function(value) {
    if (is.null(value) || is.na(value) || !nzchar(value)) {
      return(integer())
    }

    strsplit(
      value,
      ",",
      fixed = TRUE
    )[[1]] |>
      trimws() |>
      as.integer()
  }

  log_rate_limit_headers <- function(response) {
    limit_header <- httr2::resp_header(
      response,
      "x-ratelimit-limit",
      default = NA_character_
    )

    usage_header <- httr2::resp_header(
      response,
      "x-ratelimit-usage",
      default = NA_character_
    )

    limits <- parse_rate_limit_header(limit_header)

    usage <- parse_rate_limit_header(usage_header)

    if (length(limits) < 2 || length(usage) < 2) {
      return(invisible(NULL))
    }

    message(glue::glue(
      "Strava rate limit usage: ",
      "15-minute {usage[[1]]}/{limits[[1]]}; ",
      "daily {usage[[2]]}/{limits[[2]]}."
    ))

    invisible(NULL)
  }

  api_base_url <- config$sources$strava$api_base_url

  timeout_seconds <- value_or_default(
    config$ingestion$timeout_seconds,
    60
  )

  max_retries <- value_or_default(
    config$ingestion$max_retries,
    3
  )

  stopifnot(nzchar(api_base_url))
  stopifnot(timeout_seconds > 0)
  stopifnot(max_retries >= 0)

  request <- httr2::request(
    paste0(api_base_url, path)
  ) |>
    httr2::req_auth_bearer_token(token) |>
    httr2::req_timeout(timeout_seconds)

  if (length(query) > 0) {
    request <- do.call(
      httr2::req_url_query,
      c(list(request), query)
    )
  }

  total_attempts <- max_retries + 1

  for (attempt in seq_len(total_attempts)) {
    response <- tryCatch(
      httr2::req_perform(request),
      error = function(e) e
    )

    if (!inherits(response, "error")) {
      log_rate_limit_headers(response)

      return(response)
    }

    if (inherits(response, "httr2_http") && !is.null(response$resp)) {
      log_rate_limit_headers(response$resp)
    }

    if (inherits(response, "httr2_http_429")) {
      message(
        "Rate limit reached; stopping without immediate retry."
      )

      stop(response)
    }

    is_retryable <- inherits(response, "httr2_http_500") ||
      inherits(response, "httr2_http_502") ||
      inherits(response, "httr2_http_503") ||
      inherits(response, "httr2_http_504")

    if (!is_retryable || attempt == total_attempts) {
      stop(response)
    }

    pause_seconds <- min(
      2 ^ (attempt - 1),
      60
    )

    message(glue::glue(
      "Strava request failed with a transient error; ",
      "retrying in {pause_seconds}s ",
      "({attempt}/{total_attempts})."
    ))

    Sys.sleep(pause_seconds)
  }
}

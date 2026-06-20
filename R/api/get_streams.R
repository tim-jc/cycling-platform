#' Get Streams
#'
#' Retrieve streams from the Strava API for a set of activity ids.
#'
#' @param run_id Integer ETL run identifier.
#' @param source_id Integer source identifier.
#' @param refresh_days Number of days to look back.
#'
#' @return Tibble containing one row per activity.
get_streams <- function(
  run_id,
  source_id,
  activity_ids,
  config
) {
  token <- get_access_token()

  api_base_url <- config$sources$strava$api_base_url

  request_pause_seconds <- config$ingestion$request_pause_seconds

  stream_types <- config$sources$strava$stream_types

  n_streams_to_get <- length(activity_ids)

  stream_index <- 1

  stopifnot(n_streams_to_get > 0)

  stopifnot(request_pause_seconds >= 0)

  stopifnot(nzchar(api_base_url))

  while (stream_index <= n_streams_to_get) {
    activity_to_get <- activity_ids[stream_index]

    message(glue::glue(
      "Retrieving stream for activity id {activity_to_get}..."
    ))

    stream_url <- paste(
      api_base_url,
      "activities",
      activity_to_get,
      "streams",
      paste0(
        stream_types,
        collapse = ","
      ),
      sep = "/"
    )

    response <- httr2::request(
      paste0(
        api_base_url,
        "/activities/",
        activity_to_get,
        "/streams"
      )
    ) |>
      httr2::req_auth_bearer_token(token) |>
      httr2::req_url_query(
        keys = paste(stream_types, collapse = ","),
        key_by_type = "true"
      ) |>
      httr2::req_perform()

    body_tbl <- httr2::resp_body_json(
      response,
      simplifyVector = FALSE
    )

    if (nrow(body_tbl) == 0) {
      break
    }

    # short pause to get ahead of Strava API rate limiting
    Sys.sleep(request_pause_seconds)

    stream_index <- stream_index + 1
  }
}

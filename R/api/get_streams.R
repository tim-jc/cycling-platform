#' Get Streams
#'
#' Retrieve streams from the Strava API for a set of activity ids.
#'
#' @param run_id Integer ETL run identifier.
#' @param source_id Integer source identifier.
#' @param activity_ids Integer vector of activity IDs.
#' @param config Platform configuration.
#'
#' @return Tibble containing one row per activity_id × stream_type.
get_streams <- function(
  run_id,
  source_id,
  activity_ids,
  config
) {
  token <- get_access_token()

  retrieved_at <- Sys.time()

  api_base_url <- config$sources$strava$api_base_url

  request_pause_seconds <- config$ingestion$request_pause_seconds

  stream_types <- config$sources$strava$stream_types

  stream_keys <- paste(
    stream_types,
    collapse = ","
  )

  stopifnot(length(activity_ids) > 0)

  stopifnot(request_pause_seconds >= 0)

  stopifnot(nzchar(api_base_url))

  purrr::map_dfr(
    activity_ids,
    \(activity_to_get) {
      message(glue::glue(
        "Retrieving stream for activity id {activity_to_get}..."
      ))

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
          keys = stream_keys,
          key_by_type = "true"
        ) |>
        httr2::req_perform()

      body <- httr2::resp_body_json(
        response,
        simplifyVector = FALSE
      )

      message(glue::glue(
        "Retrieved {length(body)} streams for activity {activity_to_get}"
      ))

      if (length(body) == 0) {
        return(tibble::tibble())
      }

      Sys.sleep(request_pause_seconds)

      purrr::imap_dfr(
        body,
        \(stream, stream_type) {
          tibble::tibble(
            run_id = run_id,
            source_id = source_id,
            retrieved_at = retrieved_at,

            activity_id = activity_to_get,
            stream_type = stream_type,

            series_type = stream$series_type,
            original_size = stream$original_size,
            resolution = stream$resolution,

            stream_payload = as.character(
              jsonlite::toJSON(
                stream$data,
                auto_unbox = TRUE,
                null = "null"
              )
            )
          )
        }
      )
    }
  )
}

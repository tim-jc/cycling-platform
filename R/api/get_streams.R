#' Get Streams
#'
#' Retrieve streams from the Strava API for a set of activity ids.
#'
#' @param run_id Integer ETL run identifier.
#' @param source_id Integer source identifier.
#' @param activity_ids Integer64 vector of activity IDs.
#' @param config Platform configuration.
#'
#' @return Named list containing:
#'   - streams: tibble containing one row per activity_id × stream_type
#'   - not_found_ids: integer64 vector of activity IDs with no streams
stream_payload_to_json <- function(x) {
  as.character(
    jsonlite::toJSON(
      x,
      auto_unbox = TRUE,
      null = "null",
      digits = NA
    )
  )
}

get_streams <- function(
  run_id,
  source_id,
  activity_ids,
  config
) {
  empty_streams <- function() {
    tibble::tibble(
      run_id = bit64::integer64(),

      source_id = integer(),

      retrieved_at = as.POSIXct(
        character(),
        tz = "UTC"
      ),

      activity_id = bit64::integer64(),

      stream_type = character(),

      series_type = character(),

      original_size = integer(),

      resolution = character(),

      stream_payload = character()
    )
  }

  if (length(activity_ids) == 0) {
    return(
      list(
        streams = empty_streams(),
        not_found_ids = bit64::integer64()
      )
    )
  }

  token <- get_access_token()

  retrieved_at <- Sys.time()

  request_pause_seconds <- config$ingestion$request_pause_seconds

  stream_keys <- paste(
    config$sources$strava$stream_types,
    collapse = ","
  )

  stopifnot(request_pause_seconds >= 0)

  # Track activities with no stream data (HTTP 404)
  not_found_ids <- bit64::integer64()

  streams <- purrr::map_dfr(
    seq_along(activity_ids),
    \(i) {
      activity_to_get <- activity_ids[[i]]

      response <- tryCatch(
        {
          perform_strava_request(
            path = paste0(
              "/activities/",
              activity_to_get,
              "/streams"
            ),
            config = config,
            query = list(
              keys = stream_keys,
              key_by_type = "true"
            ),
            token = token
          )
        },

        error = function(e) {
          if (inherits(e, "httr2_http_404")) {
            message(glue::glue(
              "No streams available for activity {activity_to_get}"
            ))

            not_found_ids <<- c(
              not_found_ids,
              bit64::as.integer64(activity_to_get)
            )

            return(NULL)
          }

          stop(e)
        }
      )

      Sys.sleep(request_pause_seconds)

      if (is.null(response)) {
        return(
          empty_streams()
        )
      }

      body <- httr2::resp_body_json(
        response,
        simplifyVector = FALSE
      )

      if (length(body) == 0) {
        message(glue::glue(
          "Empty stream response for activity {activity_to_get}"
        ))

        return(
          empty_streams()
        )
      }

      purrr::imap_dfr(
        body,
        \(stream, stream_type) {
          tibble::tibble(
            run_id = run_id,

            source_id = source_id,

            retrieved_at = retrieved_at,

            activity_id = bit64::as.integer64(
              activity_to_get
            ),

            stream_type = stream_type,

            series_type = stream$series_type,

            original_size = stream$original_size,

            resolution = stream$resolution,

            stream_payload = stream_payload_to_json(
              stream$data
            )
          )
        }
      )
    }
  )

  list(
    streams = streams,

    not_found_ids = unique(
      bit64::as.integer64(not_found_ids)
    )
  )
}

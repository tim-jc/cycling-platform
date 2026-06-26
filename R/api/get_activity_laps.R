#' Get Activity Laps
#'
#' Retrieve laps from the Strava API for a set of activity ids.
#'
#' @param run_id Integer ETL run identifier.
#' @param source_id Integer source identifier.
#' @param activity_ids Integer64 vector of activity IDs.
#' @param config Platform configuration.
#'
#' @return Named list containing:
#'   - laps: tibble containing one row per activity_id x lap_index
#'   - not_found_ids: integer64 vector of activity IDs with no laps
get_activity_laps <- function(
  run_id,
  source_id,
  activity_ids,
  config
) {
  empty_laps <- function() {
    tibble::tibble(
      run_id = bit64::integer64(),

      source_id = integer(),

      retrieved_at = as.POSIXct(
        character(),
        tz = "UTC"
      ),

      activity_id = bit64::integer64(),

      lap_index = integer(),

      lap_payload = character()
    )
  }

  if (length(activity_ids) == 0) {
    return(
      list(
        laps = empty_laps(),
        not_found_ids = bit64::integer64()
      )
    )
  }

  token <- get_access_token()

  request_pause_seconds <- config$ingestion$lap_request_pause_seconds

  if (is.null(request_pause_seconds)) {
    request_pause_seconds <- config$ingestion$request_pause_seconds
  }

  stopifnot(request_pause_seconds >= 0)

  not_found_ids <- bit64::integer64()

  laps <- purrr::map_dfr(
    seq_along(activity_ids),
    \(i) {
      activity_to_get <- activity_ids[[i]]

      response <- tryCatch(
        {
          perform_strava_request(
            path = paste0(
              "/activities/",
              activity_to_get,
              "/laps"
            ),
            config = config,
            token = token
          )
        },

        error = function(e) {
          if (inherits(e, "httr2_http_404")) {
            message(glue::glue(
              "No laps available for activity {activity_to_get}"
            ))

            not_found_ids <<- c(
              not_found_ids,
              bit64::as.integer64(activity_to_get)
            )

            return(NULL)
          }

          if (inherits(e, "httr2_http_429")) {
            message(
              "Rate limit reached."
            )

            stop(e)
          }

          stop(e)
        }
      )

      Sys.sleep(request_pause_seconds)

      if (is.null(response)) {
        return(
          empty_laps()
        )
      }

      body <- httr2::resp_body_json(
        response,
        simplifyVector = FALSE
      )

      if (length(body) == 0) {
        message(glue::glue(
          "Empty laps response for activity {activity_to_get}"
        ))

        not_found_ids <<- c(
          not_found_ids,
          bit64::as.integer64(activity_to_get)
        )

        return(
          empty_laps()
        )
      }

      retrieved_at <- Sys.time()

      purrr::map_dfr(
        seq_along(body),
        \(lap_index) {
          tibble::tibble(
            run_id = run_id,

            source_id = source_id,

            retrieved_at = retrieved_at,

            activity_id = bit64::as.integer64(
              activity_to_get
            ),

            lap_index = lap_index,

            lap_payload = as.character(
              jsonlite::toJSON(
                body[[lap_index]],
                auto_unbox = TRUE,
                null = "null"
              )
            )
          )
        }
      )
    }
  )

  list(
    laps = laps,

    not_found_ids = unique(
      bit64::as.integer64(not_found_ids)
    )
  )
}

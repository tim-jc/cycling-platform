#' Get Activity Details
#'
#' Retrieve activity details from the Strava API for a set of activity ids.
#'
#' @param run_id Integer ETL run identifier.
#' @param source_id Integer source identifier.
#' @param activity_ids Integer64 vector of activity IDs.
#' @param config Platform configuration.
#'
#' @return Named list containing:
#'   - details: tibble containing one row per activity_id
#'   - not_found_ids: integer64 vector of activity IDs with no details
get_activity_details <- function(
  run_id,
  source_id,
  activity_ids,
  config
) {
  empty_details <- function() {
    tibble::tibble(
      run_id = bit64::integer64(),

      source_id = integer(),

      retrieved_at = as.POSIXct(
        character(),
        tz = "UTC"
      ),

      activity_id = bit64::integer64(),

      details_payload = character()
    )
  }

  if (length(activity_ids) == 0) {
    return(
      list(
        details = empty_details(),
        not_found_ids = bit64::integer64()
      )
    )
  }

  token <- get_access_token()

  api_base_url <- config$sources$strava$api_base_url

  request_pause_seconds <- config$ingestion$request_pause_seconds

  stopifnot(request_pause_seconds >= 0)

  stopifnot(nzchar(api_base_url))

  n_details_to_get <- length(activity_ids)

  # Track activities with no details (HTTP 404)
  not_found_ids <- bit64::integer64()

  details <- purrr::map_dfr(
    seq_along(activity_ids),
    \(i) {
      activity_to_get <- activity_ids[[i]]

      pct_complete <- round(
        i / n_details_to_get * 100,
        digits = 1
      )

      message(glue::glue(
        "[{i}/{n_details_to_get} | {pct_complete}%] ",
        "Retrieving details for activity {activity_to_get}"
      ))

      response <- tryCatch(
        {
          httr2::request(
            paste0(
              api_base_url,
              "/activities/",
              activity_to_get
            )
          ) |>
            httr2::req_auth_bearer_token(token) |>
            httr2::req_perform()
        },

        error = function(e) {
          if (inherits(e, "httr2_http_404")) {
            message(glue::glue(
              "No details available for activity {activity_to_get}"
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
          empty_details()
        )
      }

      body <- httr2::resp_body_json(
        response,
        simplifyVector = FALSE
      )

      if (length(body) == 0) {
        message(glue::glue(
          "Empty details response for activity {activity_to_get}"
        ))

        return(
          empty_details()
        )
      }

      tibble::tibble(
        run_id = run_id,

        source_id = source_id,

        retrieved_at = Sys.time(),

        activity_id = bit64::as.integer64(
          activity_to_get
        ),

        details_payload = as.character(
          jsonlite::toJSON(
            body,
            auto_unbox = TRUE,
            null = "null"
          )
        )
      )
    }
  )

  list(
    details = details,
    not_found_ids = unique(
      bit64::as.integer64(not_found_ids)
    )
  )
}

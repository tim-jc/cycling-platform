#' Parse a Strava gear object
#'
#' @param gear Named list returned by Strava.
#' @param gear_type Controlled type: bike, shoes, or unknown.
#' @param observed_in_current_collection Whether /athlete listed this gear.
#' @param observed_at Observation timestamp.
#' @param run_id ETL run identifier.
#' @param source_id Data source identifier.
#'
#' @return One-row tibble.
parse_strava_gear <- function(
  gear,
  gear_type = "unknown",
  observed_in_current_collection = FALSE,
  observed_at = Sys.time(),
  run_id,
  source_id
) {
  required <- c("id", "name")

  if (!is.list(gear) || !all(required %in% names(gear))) {
    stop(
      "Malformed Strava gear response: id and name are required.",
      call. = FALSE
    )
  }

  gear_type <- match.arg(gear_type, c("bike", "shoes", "unknown"))

  scalar <- function(name, default = NA) {
    value <- gear[[name]]
    if (is.null(value) || length(value) == 0) default else value[[1]]
  }

  payload <- jsonlite::toJSON(
    gear,
    auto_unbox = TRUE,
    null = "null",
    digits = NA
  )

  if (
    !nzchar(as.character(scalar("id"))) ||
      !nzchar(as.character(scalar("name")))
  ) {
    stop(
      "Malformed Strava gear response: id and name must be non-blank.",
      call. = FALSE
    )
  }

  tibble::tibble(
    gear_id = as.character(scalar("id")),
    payload_hash = digest::digest(payload, algo = "sha256", serialize = FALSE),
    run_id = run_id,
    source_id = source_id,
    gear_type = gear_type,
    gear_name = as.character(scalar("name")),
    is_primary = as.logical(scalar("primary")),
    distance_metres = as.numeric(scalar("distance")),
    brand_name = as.character(scalar("brand_name")),
    model_name = as.character(scalar("model_name")),
    frame_type = as.integer(scalar("frame_type")),
    description = as.character(scalar("description")),
    resource_state = as.integer(scalar("resource_state")),
    observed_in_current_collection =
      isTRUE(observed_in_current_collection),
    source_payload = as.character(payload),
    source_observed_at = observed_at,
    first_observed_at = observed_at,
    last_observed_at = observed_at
  )
}

strava_http_status <- function(error) {
  if (!is.null(error$status_code)) {
    return(as.integer(error$status_code))
  }

  if (inherits(error, "httr2_http") && !is.null(error$resp)) {
    return(httr2::resp_status(error$resp))
  }

  NA_integer_
}

#' Retrieve Strava gear
#'
#' Fetch the authenticated athlete to discover current bikes and shoes, then
#' retrieve DetailedGear for current and activity-referenced historical IDs.
#'
#' @return List with observations, unresolved IDs, and request counts.
get_gear <- function(
  run_id,
  source_id,
  activity_gear_ids = character(),
  config,
  token_fn = get_access_token,
  request_fn = perform_strava_request,
  body_fn = function(response) {
    httr2::resp_body_json(response, simplifyVector = FALSE)
  }
) {
  token <- token_fn()
  observed_at <- Sys.time()
  request_count <- 0L

  athlete_response <- request_fn(
    path = "/athlete",
    config = config,
    token = token
  )
  request_count <- request_count + 1L
  athlete <- body_fn(athlete_response)

  if (!all(c("bikes", "shoes") %in% names(athlete))) {
    stop(
      "Strava /athlete response omitted bikes or shoes. ",
      "Gear collection ingestion requires profile:read_all scope.",
      call. = FALSE
    )
  }

  collection <- list()
  for (type_name in c("bikes", "shoes")) {
    entries <- athlete[[type_name]]
    if (is.null(entries)) entries <- list()
    if (!is.list(entries)) {
      stop("Malformed Strava athlete gear collection.", call. = FALSE)
    }
    for (entry in entries) {
      if (
        !is.list(entry) ||
          is.null(entry$id) ||
          !nzchar(as.character(entry$id[[1]]))
      ) {
        stop("Malformed Strava athlete gear collection.", call. = FALSE)
      }
      collection[[length(collection) + 1L]] <- list(
        gear_id = as.character(entry$id),
        gear_type = if (identical(type_name, "bikes")) "bike" else "shoes"
      )
    }
  }

  current_ids <- vapply(collection, `[[`, character(1), "gear_id")
  type_by_id <- stats::setNames(
    vapply(collection, `[[`, character(1), "gear_type"),
    current_ids
  )
  requested_ids <- unique(c(current_ids, as.character(activity_gear_ids)))
  requested_ids <- requested_ids[!is.na(requested_ids) & nzchar(requested_ids)]

  observations <- list()
  unresolved <- list()

  for (gear_id in requested_ids) {
    request_count <- request_count + 1L
    response <- tryCatch(
      {
        request_fn(
          path = paste0("/gear/", utils::URLencode(gear_id, reserved = TRUE)),
          config = config,
          token = token
        )
      },
      error = function(e) e
    )

    if (inherits(response, "error")) {
      status <- strava_http_status(response)
      if (!is.na(status) && status %in% c(403L, 404L)) {
        if (gear_id %in% current_ids) {
          stop(
            "Strava current gear lookup failed for ",
            gear_id,
            " with HTTP ",
            status,
            "; refusing an incomplete current snapshot.",
            call. = FALSE
          )
        }
        unresolved[[length(unresolved) + 1L]] <- tibble::tibble(
          gear_id = gear_id,
          resolution_status = if (status == 404L) "NOT_FOUND" else "FORBIDDEN",
          attempted_at = observed_at
        )
        next
      }
      stop(response)
    }

    body <- body_fn(response)
    observations[[length(observations) + 1L]] <- parse_strava_gear(
      gear = body,
      gear_type = if (gear_id %in% names(type_by_id)) {
        type_by_id[[gear_id]]
      } else {
        "unknown"
      },
      observed_in_current_collection = gear_id %in% current_ids,
      observed_at = observed_at,
      run_id = run_id,
      source_id = source_id
    )
  }

  list(
    observations = dplyr::bind_rows(observations),
    unresolved = dplyr::bind_rows(unresolved),
    request_count = request_count,
    source_records = length(current_ids),
    historical_lookup_count = length(setdiff(requested_ids, current_ids))
  )
}

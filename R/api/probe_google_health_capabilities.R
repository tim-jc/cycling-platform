google_health_capability_path <- function(data_type, google_user_id = "me") {
  paste0(
    "/users/",
    utils::URLencode(google_user_id, reserved = TRUE),
    "/dataTypes/",
    utils::URLencode(data_type, reserved = TRUE),
    "/dataPoints"
  )
}

google_health_interval_filter <- function(
  data_type,
  start_date,
  end_date
) {
  start_time <- format(
    as.POSIXct(as.Date(start_date), tz = "UTC"),
    "%Y-%m-%dT%H:%M:%SZ"
  )
  end_time <- format(
    as.POSIXct(as.Date(end_date), tz = "UTC"),
    "%Y-%m-%dT%H:%M:%SZ"
  )
  field_name <- paste0(gsub("-", "_", data_type), ".interval.start_time")

  paste0(
    field_name,
    ' >= "',
    start_time,
    '" AND ',
    field_name,
    ' < "',
    end_time,
    '"'
  )
}

google_health_probe_data_points <- function(
  data_type,
  filter,
  page_size,
  google_user_id,
  config,
  token,
  request_performer = perform_google_health_request
) {
  path <- google_health_capability_path(data_type, google_user_id)
  next_page_token <- NULL
  pages <- list()
  data_points <- list()

  repeat {
    query <- list(filter = filter, pageSize = page_size)
    if (!is.null(next_page_token)) {
      query$pageToken <- next_page_token
    }

    response <- request_performer(
      path = path,
      config = config,
      query = query,
      token = token
    )
    body <- httr2::resp_body_json(response, simplifyVector = FALSE)
    page_data_points <- body$dataPoints %||% body$data_points %||% list()
    next_page_token <- body$nextPageToken %||% body$next_page_token

    pages <- c(pages, list(body))
    data_points <- c(data_points, page_data_points)

    if (is.null(next_page_token) || !nzchar(next_page_token)) {
      break
    }
  }

  list(
    success = TRUE,
    data_type = data_type,
    filter = filter,
    page_count = length(pages),
    data_point_count = length(data_points),
    data_points = data_points,
    error_message = NA_character_
  )
}

run_google_health_capability_probe <- function(
  probe_name,
  data_type,
  filter,
  page_size,
  google_user_id,
  config,
  token,
  request_performer = perform_google_health_request,
  clock = Sys.time
) {
  message("")
  message("Probe: starting ", probe_name, ".")
  start_time <- clock()
  result <- NULL

  for (filter_candidate in filter) {
    message("Probe filter: ", filter_candidate)
    result <- tryCatch(
      google_health_probe_data_points(
        data_type = data_type,
        filter = filter_candidate,
        page_size = page_size,
        google_user_id = google_user_id,
        config = config,
        token = token,
        request_performer = request_performer
      ),
      error = function(e) {
        list(
          success = FALSE,
          data_type = data_type,
          filter = filter_candidate,
          page_count = NA_integer_,
          data_point_count = NA_integer_,
          data_points = list(),
          error_message = conditionMessage(e)
        )
      }
    )
    if (isTRUE(result$success)) {
      break
    }
  }

  result$probe_name <- probe_name
  result$elapsed_seconds <- round(
    as.numeric(difftime(clock(), start_time, units = "secs")),
    1
  )

  if (isTRUE(result$success)) {
    message(
      "Probe: completed ", probe_name, " in ", result$elapsed_seconds,
      "s; pages=", result$page_count,
      "; data_points=", result$data_point_count, "."
    )
  } else {
    message("Probe: failed ", probe_name, " in ", result$elapsed_seconds, "s.")
    message("Probe error: ", result$error_message)
  }

  result
}

format_google_health_exercise_capability <- function(result) {
  if (!isTRUE(result$success)) {
    return(paste0("exercise: FAILED · ", result$error_message))
  }
  if (isTRUE(result$data_point_count == 0L)) {
    return(paste0(
      "exercise: SUCCESS · accessible, zero records · ",
      result$page_count,
      " pages · scope/capability confirmed"
    ))
  }
  paste0(
    "exercise: SUCCESS · ",
    result$data_point_count,
    " data points · ",
    result$page_count,
    " pages · scope/capability confirmed"
  )
}

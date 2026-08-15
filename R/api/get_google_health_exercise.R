google_health_interval_filter <- function(
  data_type,
  start_datetime,
  end_datetime
) {
  start_time <- format(
    as.POSIXct(start_datetime, tz = "UTC"),
    "%Y-%m-%dT%H:%M:%SZ"
  )
  end_time <- format(
    as.POSIXct(end_datetime, tz = "UTC"),
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

google_health_exercise_observation_key <- function(
  google_health_user_id,
  source_data_point_id,
  payload
) {
  source_data_point_id <- google_health_null_to_na(source_data_point_id)
  if (is.na(source_data_point_id) || !nzchar(trimws(source_data_point_id))) {
    stop(
      "Google Health Exercise data point is missing its source name/id.",
      call. = FALSE
    )
  }

  key <- as.character(openssl::sha256(charToRaw(paste(
    google_health_user_id,
    source_data_point_id,
    payload,
    sep = "|"
  ))))
  attributes(key) <- NULL
  key
}

google_health_empty_exercise <- function() {
  tibble::tibble(
    exercise_observation_key = character(),
    source_id = integer(),
    google_health_user_id = character(),
    source_data_point_id = character(),
    exercise_type = character(),
    display_name = character(),
    interval_start_time = as.POSIXct(character(), tz = "UTC"),
    interval_end_time = as.POSIXct(character(), tz = "UTC"),
    start_utc_offset = character(),
    end_utc_offset = character(),
    source_update_time = as.POSIXct(character(), tz = "UTC"),
    source_name = character(),
    source_ecosystem = character(),
    source_platform = character(),
    source_recording_method = character(),
    source_device_manufacturer = character(),
    source_device_model = character(),
    run_id = bit64::integer64(),
    retrieved_at = as.POSIXct(character(), tz = "UTC"),
    exercise_payload = character()
  )
}

google_health_shape_exercise <- function(
  data_points,
  google_health_user_id,
  run_id,
  source_id,
  retrieved_at
) {
  if (length(data_points) == 0L) {
    return(google_health_empty_exercise())
  }

  purrr::map_dfr(data_points, \(data_point) {
    if (!is.list(data_point) || is.null(data_point$exercise)) {
      stop(
        "Malformed Google Health Exercise data point: exercise payload is missing.",
        call. = FALSE
      )
    }

    payload <- google_health_payload_to_json(data_point)
    source_data_point_id <- google_health_extract_first(
      data_point,
      list(c("name"))
    )
    source_name <- google_health_extract_first(
      data_point,
      list(c("dataSource", "name"), c("data_source", "name"), c("source", "name"))
    )
    provenance <- google_health_daily_source_provenance(data_point)

    interval_start <- google_health_extract_first(data_point, list(
      c("exercise", "interval", "startTime", "physicalTime"),
      c("exercise", "interval", "startTime"),
      c("exercise", "interval", "start_time", "physical_time"),
      c("exercise", "interval", "start_time")
    ))
    interval_end <- google_health_extract_first(data_point, list(
      c("exercise", "interval", "endTime", "physicalTime"),
      c("exercise", "interval", "endTime"),
      c("exercise", "interval", "end_time", "physical_time"),
      c("exercise", "interval", "end_time")
    ))
    start_offset <- google_health_extract_first(data_point, list(
      c("exercise", "interval", "startTime", "utcOffset"),
      c("exercise", "interval", "startUtcOffset"),
      c("exercise", "interval", "start_time", "utc_offset"),
      c("exercise", "interval", "start_utc_offset")
    ))
    end_offset <- google_health_extract_first(data_point, list(
      c("exercise", "interval", "endTime", "utcOffset"),
      c("exercise", "interval", "endUtcOffset"),
      c("exercise", "interval", "end_time", "utc_offset"),
      c("exercise", "interval", "end_utc_offset")
    ))

    tibble::tibble(
      exercise_observation_key = google_health_exercise_observation_key(
        google_health_user_id,
        source_data_point_id,
        payload
      ),
      source_id = source_id,
      google_health_user_id = google_health_user_id,
      source_data_point_id = google_health_null_to_na(source_data_point_id),
      exercise_type = google_health_null_to_na(google_health_extract_first(
        data_point,
        list(c("exercise", "exerciseType"), c("exercise", "exercise_type"))
      )),
      display_name = google_health_null_to_na(google_health_extract_first(
        data_point,
        list(c("exercise", "displayName"), c("exercise", "display_name"))
      )),
      interval_start_time = google_health_physical_time(interval_start),
      interval_end_time = google_health_physical_time(interval_end),
      start_utc_offset = google_health_null_to_na(start_offset),
      end_utc_offset = google_health_null_to_na(end_offset),
      source_update_time = google_health_physical_time(
        google_health_extract_first(
          data_point,
          list(
            c("exercise", "updateTime", "physicalTime"),
            c("exercise", "updateTime"),
            c("exercise", "update_time", "physical_time"),
            c("exercise", "update_time")
          )
        )
      ),
      source_name = google_health_null_to_na(source_name),
      source_ecosystem = provenance$source_ecosystem[[1]],
      source_platform = provenance$source_platform[[1]],
      source_recording_method = provenance$source_recording_method[[1]],
      source_device_manufacturer = provenance$source_device_manufacturer[[1]],
      source_device_model = provenance$source_device_model[[1]],
      run_id = run_id,
      retrieved_at = retrieved_at,
      exercise_payload = payload
    )
  })
}

get_google_health_exercise <- function(
  run_id,
  source_id,
  start_datetime,
  end_datetime,
  config,
  token = get_google_health_access_token(),
  request_performer = perform_google_health_request,
  retrieved_at = Sys.time()
) {
  google_health_user_id <- config$sources$google_health$user_id %||% "me"
  page_size <- config$ingestion$google_health_page_size %||% 1000L
  path <- paste0(
    "/users/",
    utils::URLencode(google_health_user_id, reserved = TRUE),
    "/dataTypes/exercise/dataPoints"
  )
  filter <- google_health_interval_filter(
    "exercise",
    start_datetime,
    end_datetime
  )
  next_page_token <- NULL
  data_points <- list()
  page_count <- 0L

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
    data_points <- c(data_points, page_data_points)
    page_count <- page_count + 1L

    if (is.null(next_page_token) || !nzchar(next_page_token)) {
      break
    }
  }

  result <- google_health_shape_exercise(
    data_points = data_points,
    google_health_user_id = google_health_user_id,
    run_id = run_id,
    source_id = source_id,
    retrieved_at = retrieved_at
  )
  attr(result, "page_count") <- page_count
  attr(result, "request_count") <- page_count
  result
}

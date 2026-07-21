google_health_sleep_log_key <- function(
  source_log_id,
  start_physical_time,
  end_physical_time,
  source_name,
  payload
) {
  source_log_id <- google_health_null_to_na(source_log_id)

  if (!is.na(source_log_id) && nzchar(source_log_id)) {
    key_material <- source_log_id
  } else {
    key_material <- paste(
      "sleep",
      google_health_null_to_na(start_physical_time),
      google_health_null_to_na(end_physical_time),
      google_health_null_to_na(source_name),
      payload,
      sep = "|"
    )
  }

  sleep_log_key <- as.character(
    openssl::sha256(
      charToRaw(key_material)
    )
  )

  attributes(sleep_log_key) <- NULL

  sleep_log_key
}

google_health_empty_sleep_logs <- function() {
  tibble::tibble(
    sleep_log_key = character(),

    source_log_id = character(),

    google_user_id = character(),

    run_id = bit64::integer64(),

    source_id = integer(),

    retrieved_at = as.POSIXct(
      character(),
      tz = "UTC"
    ),

    source_name = character(),

    start_physical_time = as.POSIXct(
      character(),
      tz = "UTC"
    ),

    end_physical_time = as.POSIXct(
      character(),
      tz = "UTC"
    ),

    start_utc_offset = character(),

    end_utc_offset = character(),

    start_civil_date = as.Date(character()),

    end_civil_date = as.Date(character()),

    sleep_type = character(),

    stages_status = character(),

    is_processed = integer(),

    is_nap = integer(),

    is_manually_edited = integer(),

    has_sleep_stages = integer(),

    sleep_stage_count = integer(),

    has_sleep_summary = integer(),

    sleep_log_payload = character()
  )
}

google_health_logical_to_integer <- function(value) {
  if (is.null(value) || length(value) == 0) {
    return(NA_integer_)
  }

  value <- value[[1]]

  if (is.logical(value)) {
    return(as.integer(value))
  }

  if (is.character(value)) {
    value <- tolower(value)

    if (value %in% c("true", "1", "yes")) {
      return(1L)
    }

    if (value %in% c("false", "0", "no")) {
      return(0L)
    }
  }

  NA_integer_
}

google_health_path_count <- function(x, paths) {
  value <- google_health_extract_first(
    x = x,
    paths = paths
  )

  if (is.null(value)) {
    return(0L)
  }

  length(value)
}

google_health_shape_sleep_logs <- function(
  sleep_logs,
  google_user_id,
  run_id,
  source_id,
  retrieved_at
) {
  if (length(sleep_logs) == 0) {
    return(
      google_health_empty_sleep_logs()
    )
  }

  purrr::map_dfr(
    sleep_logs,
    \(sleep_log) {
      payload <- google_health_payload_to_json(
        sleep_log
      )

      source_log_id <- google_health_extract_first(
        sleep_log,
        list(
          c("name")
        )
      )

      source_name <- google_health_extract_first(
        sleep_log,
        list(
          c("dataSource", "name"),
          c("data_source", "name"),
          c("source", "name")
        )
      )

      start_physical_time <- google_health_extract_first(
        sleep_log,
        list(
          c("sleep", "interval", "startTime", "physicalTime"),
          c("sleep", "interval", "startTime"),
          c("sleep", "interval", "start_time", "physical_time"),
          c("sleep", "interval", "start_time"),
          c("interval", "startTime", "physicalTime"),
          c("interval", "startTime"),
          c("interval", "start_time", "physical_time"),
          c("interval", "start_time")
        )
      )

      end_physical_time <- google_health_extract_first(
        sleep_log,
        list(
          c("sleep", "interval", "endTime", "physicalTime"),
          c("sleep", "interval", "endTime"),
          c("sleep", "interval", "end_time", "physical_time"),
          c("sleep", "interval", "end_time"),
          c("interval", "endTime", "physicalTime"),
          c("interval", "endTime"),
          c("interval", "end_time", "physical_time"),
          c("interval", "end_time")
        )
      )

      start_utc_offset <- google_health_extract_first(
        sleep_log,
        list(
          c("sleep", "interval", "startTime", "utcOffset"),
          c("sleep", "interval", "startUtcOffset"),
          c("sleep", "interval", "start_time", "utc_offset"),
          c("sleep", "interval", "start_utc_offset"),
          c("interval", "startTime", "utcOffset"),
          c("interval", "startUtcOffset"),
          c("interval", "start_time", "utc_offset"),
          c("interval", "start_utc_offset")
        )
      )

      end_utc_offset <- google_health_extract_first(
        sleep_log,
        list(
          c("sleep", "interval", "endTime", "utcOffset"),
          c("sleep", "interval", "endUtcOffset"),
          c("sleep", "interval", "end_time", "utc_offset"),
          c("sleep", "interval", "end_utc_offset"),
          c("interval", "endTime", "utcOffset"),
          c("interval", "endUtcOffset"),
          c("interval", "end_time", "utc_offset"),
          c("interval", "end_utc_offset")
        )
      )

      start_civil_date <- google_health_extract_first(
        sleep_log,
        list(
          c("sleep", "interval", "startTime", "civilTime", "date"),
          c("sleep", "interval", "start_time", "civil_time", "date"),
          c("interval", "startTime", "civilTime", "date"),
          c("interval", "start_time", "civil_time", "date")
        )
      )

      end_civil_date <- google_health_extract_first(
        sleep_log,
        list(
          c("sleep", "interval", "endTime", "civilTime", "date"),
          c("sleep", "interval", "end_time", "civil_time", "date"),
          c("interval", "endTime", "civilTime", "date"),
          c("interval", "end_time", "civil_time", "date")
        )
      )

      sleep_type <- google_health_extract_first(
        sleep_log,
        list(
          c("sleep", "type")
        )
      )

      stages_status <- google_health_extract_first(
        sleep_log,
        list(
          c("sleep", "metadata", "stagesStatus"),
          c("sleep", "metadata", "stages_status")
        )
      )

      is_processed <- google_health_extract_first(
        sleep_log,
        list(
          c("sleep", "metadata", "processed")
        )
      )

      is_nap <- google_health_extract_first(
        sleep_log,
        list(
          c("sleep", "metadata", "nap")
        )
      )

      is_manually_edited <- google_health_extract_first(
        sleep_log,
        list(
          c("sleep", "metadata", "manuallyEdited"),
          c("sleep", "metadata", "manually_edited")
        )
      )

      sleep_stage_count <- google_health_path_count(
        sleep_log,
        list(
          c("sleep", "stages")
        )
      )

      has_sleep_summary <- !is.null(
        google_health_extract_first(
          sleep_log,
          list(
            c("sleep", "summary")
          )
        )
      )

      tibble::tibble(
        sleep_log_key = google_health_sleep_log_key(
          source_log_id = source_log_id,
          start_physical_time = start_physical_time,
          end_physical_time = end_physical_time,
          source_name = source_name,
          payload = payload
        ),

        source_log_id = google_health_null_to_na(
          source_log_id
        ),

        google_user_id = google_user_id,

        run_id = run_id,

        source_id = source_id,

        retrieved_at = retrieved_at,

        source_name = google_health_null_to_na(
          source_name
        ),

        start_physical_time = google_health_physical_time(
          start_physical_time
        ),

        end_physical_time = google_health_physical_time(
          end_physical_time
        ),

        start_utc_offset = google_health_null_to_na(
          start_utc_offset
        ),

        end_utc_offset = google_health_null_to_na(
          end_utc_offset
        ),

        start_civil_date = google_health_civil_date(
          start_civil_date
        ),

        end_civil_date = google_health_civil_date(
          end_civil_date
        ),

        sleep_type = google_health_null_to_na(
          sleep_type
        ),

        stages_status = google_health_null_to_na(
          stages_status
        ),

        is_processed = google_health_logical_to_integer(
          is_processed
        ),

        is_nap = google_health_logical_to_integer(
          is_nap
        ),

        is_manually_edited = google_health_logical_to_integer(
          is_manually_edited
        ),

        has_sleep_stages = as.integer(
          sleep_stage_count > 0L
        ),

        sleep_stage_count = sleep_stage_count,

        has_sleep_summary = as.integer(
          has_sleep_summary
        ),

        sleep_log_payload = payload
      )
    }
  )
}

#' Get Google Health Sleep Logs
#'
#' Retrieve Google Health sleep data points for a datetime window.
#'
#' @param run_id Integer ETL run identifier.
#' @param source_id Integer source identifier.
#' @param start_datetime Inclusive UTC window start.
#' @param end_datetime Exclusive UTC window end.
#' @param config Platform configuration.
#'
#' @return Tibble of raw Google Health sleep logs.
get_google_health_sleep_logs <- function(
  run_id,
  source_id,
  start_datetime,
  end_datetime,
  config
) {
  value_or_default <- function(value, default) {
    if (is.null(value)) {
      return(default)
    }

    value
  }

  google_user_id <- value_or_default(
    config$sources$google_health$user_id,
    "me"
  )

  page_size <- value_or_default(
    config$ingestion$google_health_page_size,
    25
  )

  page_size <- min(
    page_size,
    25
  )

  token <- get_google_health_access_token()

  path <- paste0(
    "/users/",
    utils::URLencode(
      google_user_id,
      reserved = TRUE
    ),
    "/dataTypes/sleep/dataPoints"
  )

  filter <- glue::glue(
    'sleep.interval.end_time >= ',
    '"{format(as.POSIXct(start_datetime, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ")}" ',
    'AND sleep.interval.end_time < ',
    '"{format(as.POSIXct(end_datetime, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ")}"'
  )

  next_page_token <- NULL

  retrieved_at <- Sys.time()

  all_sleep_logs <- list()

  repeat {
    query <- list(
      filter = as.character(filter),
      pageSize = page_size
    )

    if (!is.null(next_page_token)) {
      query$pageToken <- next_page_token
    }

    response <- perform_google_health_request(
      path = path,
      config = config,
      query = query,
      token = token
    )

    body <- httr2::resp_body_json(
      response,
      simplifyVector = FALSE
    )

    page_sleep_logs <- body$dataPoints

    if (is.null(page_sleep_logs)) {
      page_sleep_logs <- body$data_points
    }

    if (is.null(page_sleep_logs)) {
      page_sleep_logs <- list()
    }

    all_sleep_logs <- c(
      all_sleep_logs,
      page_sleep_logs
    )

    next_page_token <- body$nextPageToken

    if (is.null(next_page_token)) {
      next_page_token <- body$next_page_token
    }

    if (is.null(next_page_token) || !nzchar(next_page_token)) {
      break
    }
  }

  google_health_shape_sleep_logs(
    sleep_logs = all_sleep_logs,
    google_user_id = google_user_id,
    run_id = run_id,
    source_id = source_id,
    retrieved_at = retrieved_at
  )
}

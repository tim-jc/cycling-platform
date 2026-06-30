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

    sleep_log_payload = character()
  )
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
          c("sleep", "interval", "start_time", "physical_time"),
          c("interval", "startTime", "physicalTime"),
          c("interval", "start_time", "physical_time")
        )
      )

      end_physical_time <- google_health_extract_first(
        sleep_log,
        list(
          c("sleep", "interval", "endTime", "physicalTime"),
          c("sleep", "interval", "end_time", "physical_time"),
          c("interval", "endTime", "physicalTime"),
          c("interval", "end_time", "physical_time")
        )
      )

      start_utc_offset <- google_health_extract_first(
        sleep_log,
        list(
          c("sleep", "interval", "startTime", "utcOffset"),
          c("sleep", "interval", "start_time", "utc_offset"),
          c("interval", "startTime", "utcOffset"),
          c("interval", "start_time", "utc_offset")
        )
      )

      end_utc_offset <- google_health_extract_first(
        sleep_log,
        list(
          c("sleep", "interval", "endTime", "utcOffset"),
          c("sleep", "interval", "end_time", "utc_offset"),
          c("interval", "endTime", "utcOffset"),
          c("interval", "end_time", "utc_offset")
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

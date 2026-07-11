source("bootstrap.R")

config <- load_config()

args <- commandArgs(trailingOnly = TRUE)

if (length(args) == 0) {
  end_date <- Sys.Date()
  start_date <- end_date - 7L
} else if (length(args) == 2) {
  start_date <- as.Date(args[[1]])
  end_date <- as.Date(args[[2]])
} else {
  stop(
    paste(
      "Usage:",
      "Rscript run_google_health_capability_probe.R",
      "[start_date end_date]"
    ),
    call. = FALSE
  )
}

if (is.na(start_date) || is.na(end_date) || start_date >= end_date) {
  stop(
    "Provide a valid date window where start_date < end_date.",
    call. = FALSE
  )
}

if (is.null(config$sources$google_health$enabled) ||
    !isTRUE(config$sources$google_health$enabled)) {
  stop(
    "Google Health source is not enabled in config/platform.yml.",
    call. = FALSE
  )
}

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
  10000
)

token <- get_google_health_access_token(
  verbose = TRUE
)

message(
  "Google Health capability probe window: ",
  start_date,
  " to ",
  end_date,
  " (end exclusive)."
)

google_health_probe_path <- function(data_type) {
  paste0(
    "/users/",
    utils::URLencode(
      google_user_id,
      reserved = TRUE
    ),
    "/dataTypes/",
    utils::URLencode(
      data_type,
      reserved = TRUE
    ),
    "/dataPoints"
  )
}

google_health_probe_data_points <- function(
  data_type,
  filter,
  page_size
) {
  path <- google_health_probe_path(
    data_type = data_type
  )

  next_page_token <- NULL
  pages <- list()
  data_points <- list()

  repeat {
    query <- list(
      filter = filter,
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

    pages <- c(
      pages,
      list(body)
    )

    page_data_points <- body$dataPoints

    if (is.null(page_data_points)) {
      page_data_points <- body$data_points
    }

    if (is.null(page_data_points)) {
      page_data_points <- list()
    }

    data_points <- c(
      data_points,
      page_data_points
    )

    next_page_token <- body$nextPageToken

    if (is.null(next_page_token)) {
      next_page_token <- body$next_page_token
    }

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

run_probe <- function(
  probe_name,
  data_type,
  filter,
  page_size
) {
  message("")
  message("Probe: starting ", probe_name, ".")
  start_time <- Sys.time()

  result <- NULL

  for (filter_candidate in filter) {
    message(
      "Probe filter: ",
      filter_candidate
    )

    result <- tryCatch(
      google_health_probe_data_points(
        data_type = data_type,
        filter = filter_candidate,
        page_size = page_size
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

  elapsed_seconds <- round(
    as.numeric(
      difftime(
        Sys.time(),
        start_time,
        units = "secs"
      )
    ),
    1
  )

  if (isTRUE(result$success)) {
    message(
      "Probe: completed ",
      probe_name,
      " in ",
      elapsed_seconds,
      "s; pages=",
      result$page_count,
      "; data_points=",
      result$data_point_count,
      "."
    )
  } else {
    message(
      "Probe: failed ",
      probe_name,
      " in ",
      elapsed_seconds,
      "s."
    )
    message(
      "Probe error: ",
      result$error_message
    )
  }

  result$probe_name <- probe_name
  result$elapsed_seconds <- elapsed_seconds
  result
}

extract_scalar <- function(x, paths) {
  value <- google_health_extract_first(
    x = x,
    paths = paths
  )

  google_health_null_to_na(
    value
  )
}

extract_date_value <- function(x, paths) {
  value <- google_health_extract_first(
    x = x,
    paths = paths
  )

  if (is.null(value)) {
    return(as.Date(NA))
  }

  google_health_civil_date(
    value
  )
}

shape_daily_rhr_probe <- function(data_points) {
  if (length(data_points) == 0) {
    return(
      tibble::tibble(
        activity_date = as.Date(character()),
        resting_heart_rate_bpm = character(),
        calculation_method = character(),
        source_data_point_id = character()
      )
    )
  }

  purrr::map_dfr(
    data_points,
    \(data_point) {
      tibble::tibble(
        activity_date = extract_date_value(
          data_point,
          list(
            c("dailyRestingHeartRate", "date"),
            c("daily_resting_heart_rate", "date")
          )
        ),
        resting_heart_rate_bpm = extract_scalar(
          data_point,
          list(
            c("dailyRestingHeartRate", "beatsPerMinute"),
            c("daily_resting_heart_rate", "beats_per_minute")
          )
        ),
        calculation_method = extract_scalar(
          data_point,
          list(
            c(
              "dailyRestingHeartRate",
              "dailyRestingHeartRateMetadata",
              "calculationMethod"
            ),
            c(
              "daily_resting_heart_rate",
              "daily_resting_heart_rate_metadata",
              "calculation_method"
            )
          )
        ),
        source_data_point_id = extract_scalar(
          data_point,
          list(
            c("name")
          )
        )
      )
    }
  )
}

shape_daily_hrv_probe <- function(data_points) {
  if (length(data_points) == 0) {
    return(
      tibble::tibble(
        activity_date = as.Date(character()),
        average_hrv_milliseconds = character(),
        non_rem_heart_rate_bpm = character(),
        entropy = character(),
        deep_sleep_rmssd_milliseconds = character(),
        source_data_point_id = character()
      )
    )
  }

  purrr::map_dfr(
    data_points,
    \(data_point) {
      tibble::tibble(
        activity_date = extract_date_value(
          data_point,
          list(
            c("dailyHeartRateVariability", "date"),
            c("daily_heart_rate_variability", "date")
          )
        ),
        average_hrv_milliseconds = extract_scalar(
          data_point,
          list(
            c(
              "dailyHeartRateVariability",
              "averageHeartRateVariabilityMilliseconds"
            ),
            c(
              "daily_heart_rate_variability",
              "average_heart_rate_variability_milliseconds"
            )
          )
        ),
        non_rem_heart_rate_bpm = extract_scalar(
          data_point,
          list(
            c(
              "dailyHeartRateVariability",
              "nonRemHeartRateBeatsPerMinute"
            ),
            c(
              "daily_heart_rate_variability",
              "non_rem_heart_rate_beats_per_minute"
            )
          )
        ),
        entropy = extract_scalar(
          data_point,
          list(
            c("dailyHeartRateVariability", "entropy"),
            c("daily_heart_rate_variability", "entropy")
          )
        ),
        deep_sleep_rmssd_milliseconds = extract_scalar(
          data_point,
          list(
            c(
              "dailyHeartRateVariability",
              "deepSleepRootMeanSquareOfSuccessiveDifferencesMilliseconds"
            ),
            c(
              "daily_heart_rate_variability",
              "deep_sleep_root_mean_square_of_successive_differences_milliseconds"
            )
          )
        ),
        source_data_point_id = extract_scalar(
          data_point,
          list(
            c("name")
          )
        )
      )
    }
  )
}

count_path_items <- function(x, paths) {
  value <- google_health_extract_first(
    x = x,
    paths = paths
  )

  if (is.null(value)) {
    return(0L)
  }

  length(value)
}

has_path <- function(x, paths) {
  !is.null(
    google_health_extract_first(
      x = x,
      paths = paths
    )
  )
}

shape_sleep_probe <- function(data_points) {
  if (length(data_points) == 0) {
    return(
      tibble::tibble(
        source_data_point_id = character(),
        sleep_type = character(),
        stages_status = character(),
        stage_count = integer(),
        out_of_bed_segment_count = integer(),
        has_summary = logical(),
        stage_summary_count = integer(),
        is_processed = character(),
        is_nap = character(),
        is_manually_edited = character()
      )
    )
  }

  purrr::map_dfr(
    data_points,
    \(data_point) {
      tibble::tibble(
        source_data_point_id = extract_scalar(
          data_point,
          list(
            c("name")
          )
        ),
        sleep_type = extract_scalar(
          data_point,
          list(
            c("sleep", "type")
          )
        ),
        stages_status = extract_scalar(
          data_point,
          list(
            c("sleep", "metadata", "stagesStatus"),
            c("sleep", "metadata", "stages_status")
          )
        ),
        stage_count = count_path_items(
          data_point,
          list(
            c("sleep", "stages")
          )
        ),
        out_of_bed_segment_count = count_path_items(
          data_point,
          list(
            c("sleep", "outOfBedSegments"),
            c("sleep", "out_of_bed_segments")
          )
        ),
        has_summary = has_path(
          data_point,
          list(
            c("sleep", "summary")
          )
        ),
        stage_summary_count = count_path_items(
          data_point,
          list(
            c("sleep", "summary", "stagesSummary"),
            c("sleep", "summary", "stages_summary")
          )
        ),
        is_processed = extract_scalar(
          data_point,
          list(
            c("sleep", "metadata", "processed")
          )
        ),
        is_nap = extract_scalar(
          data_point,
          list(
            c("sleep", "metadata", "nap")
          )
        ),
        is_manually_edited = extract_scalar(
          data_point,
          list(
            c("sleep", "metadata", "manuallyEdited"),
            c("sleep", "metadata", "manually_edited")
          )
        )
      )
    }
  )
}

date_filter <- function(
  field_name,
  start_date,
  end_date
) {
  paste0(
    field_name,
    ' >= "',
    start_date,
    '" AND ',
    field_name,
    ' < "',
    end_date,
    '"'
  )
}

datetime_filter <- function(
  field_name,
  start_date,
  end_date
) {
  paste0(
    field_name,
    ' >= "',
    format(
      as.POSIXct(
        start_date,
        tz = "UTC"
      ),
      "%Y-%m-%dT%H:%M:%SZ"
    ),
    '" AND ',
    field_name,
    ' < "',
    format(
      as.POSIXct(
        end_date,
        tz = "UTC"
      ),
      "%Y-%m-%dT%H:%M:%SZ"
    ),
    '"'
  )
}

rhr_result <- run_probe(
  probe_name = "daily resting heart rate",
  data_type = "daily-resting-heart-rate",
  filter = c(
    date_filter(
      field_name = "daily_resting_heart_rate.date",
      start_date = start_date,
      end_date = end_date
    ),
    date_filter(
      field_name = "dailyRestingHeartRate.date",
      start_date = start_date,
      end_date = end_date
    )
  ),
  page_size = page_size
)

rhr_rows <- shape_daily_rhr_probe(
  rhr_result$data_points
)

message("")
message("Daily resting heart-rate rows:")
print(
  utils::head(
    rhr_rows,
    10L
  ),
  width = Inf
)

hrv_result <- run_probe(
  probe_name = "daily heart-rate variability",
  data_type = "daily-heart-rate-variability",
  filter = c(
    date_filter(
      field_name = "daily_heart_rate_variability.date",
      start_date = start_date,
      end_date = end_date
    ),
    date_filter(
      field_name = "dailyHeartRateVariability.date",
      start_date = start_date,
      end_date = end_date
    )
  ),
  page_size = page_size
)

hrv_rows <- shape_daily_hrv_probe(
  hrv_result$data_points
)

message("")
message("Daily HRV rows:")
print(
  utils::head(
    hrv_rows,
    10L
  ),
  width = Inf
)

sleep_result <- run_probe(
  probe_name = "sleep payload richness",
  data_type = "sleep",
  filter = datetime_filter(
    field_name = "sleep.interval.end_time",
    start_date = start_date,
    end_date = end_date
  ),
  page_size = min(
    page_size,
    25L
  )
)

sleep_rows <- shape_sleep_probe(
  sleep_result$data_points
)

message("")
message("Sleep payload richness rows:")
print(
  utils::head(
    sleep_rows,
    20L
  ),
  width = Inf
)

summary <- tibble::tibble(
  probe_name = c(
    rhr_result$probe_name,
    hrv_result$probe_name,
    sleep_result$probe_name
  ),
  data_type = c(
    rhr_result$data_type,
    hrv_result$data_type,
    sleep_result$data_type
  ),
  success = c(
    rhr_result$success,
    hrv_result$success,
    sleep_result$success
  ),
  data_point_count = c(
    rhr_result$data_point_count,
    hrv_result$data_point_count,
    sleep_result$data_point_count
  ),
  page_count = c(
    rhr_result$page_count,
    hrv_result$page_count,
    sleep_result$page_count
  ),
  elapsed_seconds = c(
    rhr_result$elapsed_seconds,
    hrv_result$elapsed_seconds,
    sleep_result$elapsed_seconds
  ),
  evidence = c(
    paste0(
      sum(!is.na(rhr_rows$resting_heart_rate_bpm)),
      " rows with resting_heart_rate_bpm"
    ),
    paste0(
      sum(!is.na(hrv_rows$average_hrv_milliseconds)),
      " rows with average_hrv_milliseconds"
    ),
    paste0(
      sum(sleep_rows$stage_count > 0L),
      " sleep logs with stages; ",
      sum(sleep_rows$has_summary),
      " with summary"
    )
  ),
  error_message = c(
    rhr_result$error_message,
    hrv_result$error_message,
    sleep_result$error_message
  )
)

message("")
message("Google Health capability probe summary:")
print(
  summary,
  width = Inf
)

if (any(!summary$success)) {
  message("")
  message(
    "One or more probes failed. Treat this as capability evidence, not an ",
    "ingestion failure. Check OAuth scopes, API data-type support and account ",
    "data availability."
  )
}

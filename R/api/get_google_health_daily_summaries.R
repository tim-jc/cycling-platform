google_health_daily_data_point_key <- function(
  data_type,
  google_health_user_id,
  source_data_point_id,
  activity_date,
  source_name,
  payload
) {
  source_data_point_id <- google_health_null_to_na(
    source_data_point_id
  )

  if (!is.na(source_data_point_id) && nzchar(source_data_point_id)) {
    key_material <- paste(
      data_type,
      source_data_point_id,
      sep = "|"
    )
  } else {
    key_material <- paste(
      data_type,
      google_health_null_to_na(google_health_user_id),
      google_health_null_to_na(activity_date),
      google_health_null_to_na(source_name),
      as.character(
        openssl::sha256(
          charToRaw(payload)
        )
      ),
      sep = "|"
    )
  }

  key <- as.character(
    openssl::sha256(
      charToRaw(key_material)
    )
  )

  attributes(key) <- NULL

  key
}

google_health_daily_source_grain_key <- function(
  data_type,
  google_health_user_id,
  source_data_point_id,
  activity_date,
  source_platform,
  source_recording_method,
  source_device_manufacturer,
  source_device_model,
  payload
) {
  source_data_point_id <- google_health_null_to_na(
    source_data_point_id
  )

  if (!is.na(source_data_point_id) && nzchar(source_data_point_id)) {
    key_material <- paste(
      data_type,
      source_data_point_id,
      sep = "|"
    )
  } else {
    key_material <- paste(
      data_type,
      google_health_null_to_na(google_health_user_id),
      google_health_null_to_na(activity_date),
      google_health_null_to_na(source_platform),
      google_health_null_to_na(source_recording_method),
      google_health_null_to_na(source_device_manufacturer),
      google_health_null_to_na(source_device_model),
      as.character(
        openssl::sha256(
          charToRaw(payload)
        )
      ),
      sep = "|"
    )
  }

  key <- as.character(
    openssl::sha256(
      charToRaw(key_material)
    )
  )

  attributes(key) <- NULL

  key
}

google_health_source_ecosystem <- function(
  source_platform,
  source_device_manufacturer = NA_character_
) {
  source_platform <- toupper(
    google_health_null_to_na(source_platform)
  )

  source_device_manufacturer <- tolower(
    google_health_null_to_na(source_device_manufacturer)
  )

  if (!is.na(source_platform) && source_platform == "FITBIT") {
    return("fitbit")
  }

  if (!is.na(source_platform) && source_platform == "HEALTH_KIT") {
    return("apple_health")
  }

  if (!is.na(source_platform) && source_platform == "GOOGLE_FIT") {
    return("google_fit")
  }

  if (
    !is.na(source_device_manufacturer) &&
      grepl("apple", source_device_manufacturer, fixed = TRUE)
  ) {
    return("apple_health")
  }

  if (
    !is.na(source_device_manufacturer) &&
      grepl("fitbit", source_device_manufacturer, fixed = TRUE)
  ) {
    return("fitbit")
  }

  "unknown"
}

google_health_numeric_or_na <- function(x) {
  x <- google_health_null_to_na(x)

  if (is.na(x) || !nzchar(x)) {
    return(NA_real_)
  }

  as.numeric(x)
}

google_health_data_source_field <- function(
  data_point,
  field
) {
  snake_field <- gsub(
    "([a-z0-9])([A-Z])",
    "\\1_\\2",
    field
  )
  snake_field <- tolower(snake_field)

  google_health_null_to_na(
    google_health_extract_first(
      data_point,
      list(
        c("dataSource", field),
        c("dataSource", snake_field),
        c("data_source", field),
        c("data_source", snake_field),
        c("source", field),
        c("source", snake_field)
      )
    )
  )
}

google_health_data_source_device_field <- function(
  data_point,
  field
) {
  snake_field <- gsub(
    "([a-z0-9])([A-Z])",
    "\\1_\\2",
    field
  )
  snake_field <- tolower(snake_field)

  google_health_null_to_na(
    google_health_extract_first(
      data_point,
      list(
        c("dataSource", "device", field),
        c("dataSource", "device", snake_field),
        c("data_source", "device", field),
        c("data_source", "device", snake_field),
        c("source", "device", field),
        c("source", "device", snake_field)
      )
    )
  )
}

google_health_daily_source_provenance <- function(data_point) {
  source_platform <- google_health_data_source_field(
    data_point = data_point,
    field = "platform"
  )

  source_device_manufacturer <- google_health_data_source_device_field(
    data_point = data_point,
    field = "manufacturer"
  )

  tibble::tibble(
    source_ecosystem = google_health_source_ecosystem(
      source_platform = source_platform,
      source_device_manufacturer = source_device_manufacturer
    ),
    source_platform = source_platform,
    source_recording_method = google_health_data_source_field(
      data_point = data_point,
      field = "recordingMethod"
    ),
    source_device_manufacturer = source_device_manufacturer,
    source_device_model = google_health_data_source_device_field(
      data_point = data_point,
      field = "model"
    )
  )
}

google_health_empty_daily_resting_heart_rate <- function() {
  tibble::tibble(
    daily_resting_heart_rate_key = character(),
    source_id = integer(),
    google_health_user_id = character(),
    source_data_point_id = character(),
    activity_date = as.Date(character()),
    resting_heart_rate_bpm = numeric(),
    calculation_method = character(),
    source_name = character(),
    source_ecosystem = character(),
    source_platform = character(),
    source_recording_method = character(),
    source_device_manufacturer = character(),
    source_device_model = character(),
    run_id = bit64::integer64(),
    retrieved_at = as.POSIXct(
      character(),
      tz = "UTC"
    ),
    daily_resting_heart_rate_payload = character()
  )
}

google_health_empty_daily_heart_rate_variability <- function() {
  tibble::tibble(
    daily_heart_rate_variability_key = character(),
    source_id = integer(),
    google_health_user_id = character(),
    source_data_point_id = character(),
    activity_date = as.Date(character()),
    average_hrv_milliseconds = numeric(),
    deep_sleep_rmssd_milliseconds = numeric(),
    non_rem_heart_rate_bpm = numeric(),
    entropy = numeric(),
    source_name = character(),
    source_ecosystem = character(),
    source_platform = character(),
    source_recording_method = character(),
    source_device_manufacturer = character(),
    source_device_model = character(),
    run_id = bit64::integer64(),
    retrieved_at = as.POSIXct(
      character(),
      tz = "UTC"
    ),
    daily_heart_rate_variability_payload = character()
  )
}

google_health_empty_daily_respiratory_rate <- function() {
  tibble::tibble(
    daily_respiratory_rate_key = character(),
    source_id = integer(),
    google_health_user_id = character(),
    source_data_point_id = character(),
    activity_date = as.Date(character()),
    respiratory_rate_brpm = numeric(),
    source_name = character(),
    source_ecosystem = character(),
    source_platform = character(),
    source_recording_method = character(),
    source_device_manufacturer = character(),
    source_device_model = character(),
    run_id = bit64::integer64(),
    retrieved_at = as.POSIXct(
      character(),
      tz = "UTC"
    ),
    daily_respiratory_rate_payload = character()
  )
}

google_health_get_daily_data_points <- function(
  data_type,
  date_field,
  start_date,
  end_date,
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
    10000
  )

  token <- get_google_health_access_token()

  path <- paste0(
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

  filter <- paste0(
    date_field,
    ' >= "',
    as.Date(start_date),
    '" AND ',
    date_field,
    ' < "',
    as.Date(end_date),
    '"'
  )

  next_page_token <- NULL
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

  data_points
}

google_health_shape_daily_resting_heart_rate <- function(
  data_points,
  google_health_user_id,
  run_id,
  source_id,
  retrieved_at
) {
  if (length(data_points) == 0) {
    return(
      google_health_empty_daily_resting_heart_rate()
    )
  }

  purrr::map_dfr(
    data_points,
    \(data_point) {
      payload <- google_health_payload_to_json(
        data_point
      )

      source_data_point_id <- google_health_extract_first(
        data_point,
        list(
          c("name")
        )
      )

      source_name <- google_health_extract_first(
        data_point,
        list(
          c("dataSource", "name"),
          c("data_source", "name"),
          c("source", "name")
        )
      )

      source_provenance <- google_health_daily_source_provenance(
        data_point = data_point
      )

      activity_date <- google_health_civil_date(
        google_health_extract_first(
          data_point,
          list(
            c("dailyRestingHeartRate", "date"),
            c("daily_resting_heart_rate", "date")
          )
        )
      )

      tibble::tibble(
        daily_resting_heart_rate_key = google_health_daily_data_point_key(
          data_type = "daily-resting-heart-rate",
          google_health_user_id = google_health_user_id,
          source_data_point_id = source_data_point_id,
          activity_date = activity_date,
          source_name = source_name,
          payload = payload
        ),
        source_id = source_id,
        google_health_user_id = google_health_user_id,
        source_data_point_id = google_health_null_to_na(
          source_data_point_id
        ),
        activity_date = activity_date,
        resting_heart_rate_bpm = google_health_numeric_or_na(
          google_health_extract_first(
            data_point,
            list(
              c("dailyRestingHeartRate", "beatsPerMinute"),
              c("daily_resting_heart_rate", "beats_per_minute")
            )
          )
        ),
        calculation_method = google_health_null_to_na(
          google_health_extract_first(
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
          )
        ),
        source_name = google_health_null_to_na(
          source_name
        ),
        source_ecosystem = source_provenance$source_ecosystem[[1]],
        source_platform = source_provenance$source_platform[[1]],
        source_recording_method =
          source_provenance$source_recording_method[[1]],
        source_device_manufacturer =
          source_provenance$source_device_manufacturer[[1]],
        source_device_model = source_provenance$source_device_model[[1]],
        run_id = run_id,
        retrieved_at = retrieved_at,
        daily_resting_heart_rate_payload = payload
      )
    }
  )
}

google_health_shape_daily_heart_rate_variability <- function(
  data_points,
  google_health_user_id,
  run_id,
  source_id,
  retrieved_at
) {
  if (length(data_points) == 0) {
    return(
      google_health_empty_daily_heart_rate_variability()
    )
  }

  purrr::map_dfr(
    data_points,
    \(data_point) {
      payload <- google_health_payload_to_json(
        data_point
      )

      source_data_point_id <- google_health_extract_first(
        data_point,
        list(
          c("name")
        )
      )

      source_name <- google_health_extract_first(
        data_point,
        list(
          c("dataSource", "name"),
          c("data_source", "name"),
          c("source", "name")
        )
      )

      source_provenance <- google_health_daily_source_provenance(
        data_point = data_point
      )

      activity_date <- google_health_civil_date(
        google_health_extract_first(
          data_point,
          list(
            c("dailyHeartRateVariability", "date"),
            c("daily_heart_rate_variability", "date")
          )
        )
      )

      tibble::tibble(
        daily_heart_rate_variability_key = google_health_daily_data_point_key(
          data_type = "daily-heart-rate-variability",
          google_health_user_id = google_health_user_id,
          source_data_point_id = source_data_point_id,
          activity_date = activity_date,
          source_name = source_name,
          payload = payload
        ),
        source_id = source_id,
        google_health_user_id = google_health_user_id,
        source_data_point_id = google_health_null_to_na(
          source_data_point_id
        ),
        activity_date = activity_date,
        average_hrv_milliseconds = google_health_numeric_or_na(
          google_health_extract_first(
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
          )
        ),
        deep_sleep_rmssd_milliseconds = google_health_numeric_or_na(
          google_health_extract_first(
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
          )
        ),
        non_rem_heart_rate_bpm = google_health_numeric_or_na(
          google_health_extract_first(
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
          )
        ),
        entropy = google_health_numeric_or_na(
          google_health_extract_first(
            data_point,
            list(
              c("dailyHeartRateVariability", "entropy"),
              c("daily_heart_rate_variability", "entropy")
            )
          )
        ),
        source_name = google_health_null_to_na(
          source_name
        ),
        source_ecosystem = source_provenance$source_ecosystem[[1]],
        source_platform = source_provenance$source_platform[[1]],
        source_recording_method =
          source_provenance$source_recording_method[[1]],
        source_device_manufacturer =
          source_provenance$source_device_manufacturer[[1]],
        source_device_model = source_provenance$source_device_model[[1]],
        run_id = run_id,
        retrieved_at = retrieved_at,
        daily_heart_rate_variability_payload = payload
      )
    }
  )
}

google_health_shape_daily_respiratory_rate <- function(
  data_points,
  google_health_user_id,
  run_id,
  source_id,
  retrieved_at
) {
  if (length(data_points) == 0) {
    return(
      google_health_empty_daily_respiratory_rate()
    )
  }

  purrr::map_dfr(
    data_points,
    \(data_point) {
      payload <- google_health_payload_to_json(
        data_point
      )

      source_data_point_id <- google_health_extract_first(
        data_point,
        list(
          c("name")
        )
      )

      source_name <- google_health_extract_first(
        data_point,
        list(
          c("dataSource", "name"),
          c("data_source", "name"),
          c("source", "name")
        )
      )

      source_provenance <- google_health_daily_source_provenance(
        data_point = data_point
      )

      activity_date <- google_health_civil_date(
        google_health_extract_first(
          data_point,
          list(
            c("dailyRespiratoryRate", "date"),
            c("daily_respiratory_rate", "date")
          )
        )
      )

      tibble::tibble(
        daily_respiratory_rate_key = google_health_daily_data_point_key(
          data_type = "daily-respiratory-rate",
          google_health_user_id = google_health_user_id,
          source_data_point_id = source_data_point_id,
          activity_date = activity_date,
          source_name = source_name,
          payload = payload
        ),
        source_id = source_id,
        google_health_user_id = google_health_user_id,
        source_data_point_id = google_health_null_to_na(
          source_data_point_id
        ),
        activity_date = activity_date,
        respiratory_rate_brpm = google_health_numeric_or_na(
          google_health_extract_first(
            data_point,
            list(
              c("dailyRespiratoryRate", "breathsPerMinute"),
              c("daily_respiratory_rate", "breaths_per_minute")
            )
          )
        ),
        source_name = google_health_null_to_na(
          source_name
        ),
        source_ecosystem = source_provenance$source_ecosystem[[1]],
        source_platform = source_provenance$source_platform[[1]],
        source_recording_method =
          source_provenance$source_recording_method[[1]],
        source_device_manufacturer =
          source_provenance$source_device_manufacturer[[1]],
        source_device_model = source_provenance$source_device_model[[1]],
        run_id = run_id,
        retrieved_at = retrieved_at,
        daily_respiratory_rate_payload = payload
      )
    }
  )
}

get_google_health_daily_resting_heart_rate <- function(
  run_id,
  source_id,
  start_date,
  end_date,
  config
) {
  google_health_user_id <- if (is.null(config$sources$google_health$user_id)) {
    "me"
  } else {
    config$sources$google_health$user_id
  }

  retrieved_at <- Sys.time()

  data_points <- google_health_get_daily_data_points(
    data_type = "daily-resting-heart-rate",
    date_field = "daily_resting_heart_rate.date",
    start_date = start_date,
    end_date = end_date,
    config = config
  )

  google_health_shape_daily_resting_heart_rate(
    data_points = data_points,
    google_health_user_id = google_health_user_id,
    run_id = run_id,
    source_id = source_id,
    retrieved_at = retrieved_at
  )
}

get_google_health_daily_heart_rate_variability <- function(
  run_id,
  source_id,
  start_date,
  end_date,
  config
) {
  google_health_user_id <- if (is.null(config$sources$google_health$user_id)) {
    "me"
  } else {
    config$sources$google_health$user_id
  }

  retrieved_at <- Sys.time()

  data_points <- google_health_get_daily_data_points(
    data_type = "daily-heart-rate-variability",
    date_field = "daily_heart_rate_variability.date",
    start_date = start_date,
    end_date = end_date,
    config = config
  )

  google_health_shape_daily_heart_rate_variability(
    data_points = data_points,
    google_health_user_id = google_health_user_id,
    run_id = run_id,
    source_id = source_id,
    retrieved_at = retrieved_at
  )
}

get_google_health_daily_respiratory_rate <- function(
  run_id,
  source_id,
  start_date,
  end_date,
  config
) {
  google_health_user_id <- if (is.null(config$sources$google_health$user_id)) {
    "me"
  } else {
    config$sources$google_health$user_id
  }

  retrieved_at <- Sys.time()

  data_points <- google_health_get_daily_data_points(
    data_type = "daily-respiratory-rate",
    date_field = "daily_respiratory_rate.date",
    start_date = start_date,
    end_date = end_date,
    config = config
  )

  google_health_shape_daily_respiratory_rate(
    data_points = data_points,
    google_health_user_id = google_health_user_id,
    run_id = run_id,
    source_id = source_id,
    retrieved_at = retrieved_at
  )
}

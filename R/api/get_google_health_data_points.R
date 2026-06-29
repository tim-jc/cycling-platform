#' Serialize Google Health Payload
#'
#' Preserve source numeric fidelity when storing raw Google Health payloads.
#'
#' @param x Object to serialize.
#'
#' @return JSON string.
google_health_payload_to_json <- function(x) {
  as.character(
    jsonlite::toJSON(
      x,
      auto_unbox = TRUE,
      null = "null",
      digits = NA
    )
  )
}

google_health_extract_path <- function(x, path) {
  value <- x

  for (part in path) {
    if (is.null(value) || is.null(value[[part]])) {
      return(NULL)
    }

    value <- value[[part]]
  }

  value
}

google_health_extract_first <- function(x, paths) {
  for (path in paths) {
    value <- google_health_extract_path(
      x = x,
      path = path
    )

    if (!is.null(value)) {
      return(value)
    }
  }

  NULL
}

google_health_null_to_na <- function(x) {
  if (is.null(x) || length(x) == 0) {
    return(NA_character_)
  }

  as.character(x[[1]])
}

google_health_civil_date <- function(value) {
  if (is.null(value)) {
    return(as.Date(NA))
  }

  if (is.character(value)) {
    return(as.Date(value[[1]]))
  }

  year <- google_health_extract_first(
    value,
    list(
      c("year")
    )
  )

  month <- google_health_extract_first(
    value,
    list(
      c("month")
    )
  )

  day <- google_health_extract_first(
    value,
    list(
      c("day")
    )
  )

  if (is.null(year) || is.null(month) || is.null(day)) {
    return(as.Date(NA))
  }

  as.Date(
    sprintf(
      "%04d-%02d-%02d",
      as.integer(year[[1]]),
      as.integer(month[[1]]),
      as.integer(day[[1]])
    )
  )
}

google_health_physical_time <- function(value) {
  value <- google_health_null_to_na(value)

  if (is.na(value) || !nzchar(value)) {
    return(as.POSIXct(NA))
  }

  as.POSIXct(
    strptime(
      value,
      format = "%Y-%m-%dT%H:%M:%SZ",
      tz = "UTC"
    ),
    tz = "UTC"
  )
}

google_health_data_point_key <- function(
  data_type,
  data_point_name,
  sample_physical_time,
  source_name,
  payload
) {
  key_material <- paste(
    data_type,
    google_health_null_to_na(data_point_name),
    google_health_null_to_na(sample_physical_time),
    google_health_null_to_na(source_name),
    payload,
    sep = "|"
  )

  data_point_key <- as.character(
    openssl::sha256(
      charToRaw(key_material)
    )
  )

  attributes(data_point_key) <- NULL

  data_point_key
}

google_health_empty_data_points <- function() {
  tibble::tibble(
    data_point_key = character(),

    data_type = character(),

    google_user_id = character(),

    run_id = bit64::integer64(),

    source_id = integer(),

    retrieved_at = as.POSIXct(
      character(),
      tz = "UTC"
    ),

    source_name = character(),

    sample_physical_time = as.POSIXct(
      character(),
      tz = "UTC"
    ),

    sample_utc_offset = character(),

    sample_civil_date = as.Date(character()),

    value_numeric = numeric(),

    value_name = character(),

    data_point_name = character(),

    data_point_payload = character()
  )
}

google_health_shape_data_points <- function(
  data_points,
  data_type,
  google_user_id,
  run_id,
  source_id,
  retrieved_at
) {
  if (length(data_points) == 0) {
    return(
      google_health_empty_data_points()
    )
  }

  purrr::map_dfr(
    data_points,
    \(data_point) {
      payload <- google_health_payload_to_json(
        data_point
      )

      sample_physical_time <- google_health_extract_first(
        data_point,
        list(
          c("heartRate", "sampleTime", "physicalTime"),
          c("heart_rate", "sample_time", "physical_time"),
          c("sampleTime", "physicalTime"),
          c("sample_time", "physical_time")
        )
      )

      sample_utc_offset <- google_health_extract_first(
        data_point,
        list(
          c("heartRate", "sampleTime", "utcOffset"),
          c("heart_rate", "sample_time", "utc_offset"),
          c("sampleTime", "utcOffset"),
          c("sample_time", "utc_offset")
        )
      )

      sample_civil_date <- google_health_extract_first(
        data_point,
        list(
          c("heartRate", "sampleTime", "civilTime", "date"),
          c("heart_rate", "sample_time", "civil_date"),
          c("sampleTime", "civilDate"),
          c("sample_time", "civil_date")
        )
      )

      value_numeric <- google_health_extract_first(
        data_point,
        list(
          c("heartRate", "beatsPerMinute"),
          c("heart_rate", "beats_per_minute")
        )
      )

      data_point_name <- google_health_extract_first(
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

      tibble::tibble(
        data_point_key = google_health_data_point_key(
          data_type = data_type,
          data_point_name = data_point_name,
          sample_physical_time = sample_physical_time,
          source_name = source_name,
          payload = payload
        ),

        data_type = data_type,

        google_user_id = google_user_id,

        run_id = run_id,

        source_id = source_id,

        retrieved_at = retrieved_at,

        source_name = google_health_null_to_na(source_name),

        sample_physical_time = google_health_physical_time(
          sample_physical_time
        ),

        sample_utc_offset = google_health_null_to_na(
          sample_utc_offset
        ),

        sample_civil_date = google_health_civil_date(
          sample_civil_date
        ),

        value_numeric = as.numeric(
          google_health_null_to_na(value_numeric)
        ),

        value_name = if (identical(data_type, "heart-rate")) {
          "beats_per_minute"
        } else {
          NA_character_
        },

        data_point_name = google_health_null_to_na(
          data_point_name
        ),

        data_point_payload = payload
      )
    }
  )
}

#' Get Google Health Data Points
#'
#' Retrieve Google Health data points for a data type and datetime window.
#'
#' @param run_id Integer ETL run identifier.
#' @param source_id Integer source identifier.
#' @param data_type Google Health data type, for example `heart-rate`.
#' @param start_datetime Inclusive UTC window start.
#' @param end_datetime Exclusive UTC window end.
#' @param config Platform configuration.
#'
#' @return Tibble of raw Google Health data points.
get_google_health_data_points <- function(
  run_id,
  source_id,
  data_type,
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

  filter <- glue::glue(
    '{gsub("-", "_", data_type)}.sample_time.physical_time >= ',
    '"{format(as.POSIXct(start_datetime, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ")}" ',
    'AND {gsub("-", "_", data_type)}.sample_time.physical_time < ',
    '"{format(as.POSIXct(end_datetime, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ")}"'
  )

  next_page_token <- NULL

  retrieved_at <- Sys.time()

  all_data_points <- list()

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

    page_data_points <- body$dataPoints

    if (is.null(page_data_points)) {
      page_data_points <- body$data_points
    }

    if (is.null(page_data_points)) {
      page_data_points <- list()
    }

    all_data_points <- c(
      all_data_points,
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

  google_health_shape_data_points(
    data_points = all_data_points,
    data_type = data_type,
    google_user_id = google_user_id,
    run_id = run_id,
    source_id = source_id,
    retrieved_at = retrieved_at
  )
}

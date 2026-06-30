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
    if (
      is.null(value) ||
      !is.list(value) ||
      is.null(names(value)) ||
      !part %in% names(value) ||
      is.null(value[[part]])
    ) {
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

  parsed_time <- strptime(
    value,
    format = "%Y-%m-%dT%H:%M:%OSZ",
    tz = "UTC"
  )

  if (is.na(parsed_time)) {
    parsed_time <- strptime(
      value,
      format = "%Y-%m-%dT%H:%M:%SZ",
      tz = "UTC"
    )
  }

  as.POSIXct(
    parsed_time,
    tz = "UTC"
  )
}

google_health_empty_data_points <- function() {
  tibble::tibble(
    source_id = integer(),

    run_id = bit64::integer64(),

    retrieved_at = as.POSIXct(
      character(),
      tz = "UTC"
    ),

    fitbit_user_id = character(),

    activity_date = as.Date(character()),

    detail_level = character(),

    dataset_interval = integer(),

    heart_rate_payload = character()
  )
}

google_health_shape_heart_rate_response <- function(
  response_payload,
  fitbit_user_id,
  activity_date,
  detail_level,
  run_id,
  source_id,
  retrieved_at
) {
  tibble::tibble(
    source_id = source_id,

    run_id = run_id,

    retrieved_at = retrieved_at,

    fitbit_user_id = fitbit_user_id,

    activity_date = as.Date(activity_date),

    detail_level = detail_level,

    dataset_interval = NA_integer_,

    heart_rate_payload = google_health_payload_to_json(
      response_payload
    )
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
#' @return Tibble containing one raw response row for the requested window.
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

  detail_level <- value_or_default(
    config$ingestion$google_health_heart_rate_detail_level,
    "data_points"
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

  response_pages <- list()

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

    response_pages <- c(
      response_pages,
      list(body)
    )

    next_page_token <- body$nextPageToken

    if (is.null(next_page_token)) {
      next_page_token <- body$next_page_token
    }

    if (is.null(next_page_token) || !nzchar(next_page_token)) {
      break
    }
  }

  response_payload <- list(
    data_type = data_type,
    filter = as.character(filter),
    page_count = length(response_pages),
    pages = response_pages
  )

  google_health_shape_heart_rate_response(
    response_payload = response_payload,
    fitbit_user_id = google_user_id,
    activity_date = as.Date(start_datetime),
    detail_level = detail_level,
    run_id = run_id,
    source_id = source_id,
    retrieved_at = retrieved_at
  )
}

#' Calculate Haversine Distance
#'
#' Calculate great-circle distance between coordinate vectors using the mean
#' Earth radius defined by IUGG. Invalid coordinates must be removed by the
#' caller; this function deliberately performs no track qualification.
#'
#' @return Numeric vector of distances in metres.
haversine_distance_metres <- function(
  latitude_from,
  longitude_from,
  latitude_to,
  longitude_to
) {
  earth_radius_metres <- 6371008.8
  to_radians <- pi / 180

  latitude_from_radians <- latitude_from * to_radians
  latitude_to_radians <- latitude_to * to_radians
  latitude_delta <- (latitude_to - latitude_from) * to_radians
  longitude_delta <- (longitude_to - longitude_from) * to_radians

  haversine <- sin(latitude_delta / 2)^2 +
    cos(latitude_from_radians) * cos(latitude_to_radians) *
      sin(longitude_delta / 2)^2

  # Floating-point rounding can otherwise put values just outside [0, 1].
  haversine <- pmin(1, pmax(0, haversine))
  2 * earth_radius_metres * atan2(sqrt(haversine), sqrt(1 - haversine))
}

track_coordinate_is_valid <- function(latitude, longitude) {
  is.finite(latitude) & is.finite(longitude) &
    latitude >= -90 & latitude <= 90 &
    longitude >= -180 & longitude <= 180
}

track_metric_distribution <- function(values) {
  values <- values[is.finite(values)]
  probabilities <- c(0, 0.5, 0.9, 0.95, 0.99, 1)
  names <- c("minimum", "p50", "p90", "p95", "p99", "maximum")

  if (length(values) == 0L) {
    result <- stats::setNames(rep(NA_real_, length(probabilities)), names)
  } else {
    result <- stats::setNames(
      as.numeric(stats::quantile(values, probabilities, names = FALSE, type = 7)),
      names
    )
  }

  c(count = length(values), mean = if (length(values)) mean(values) else NA_real_, result)
}

empty_track_diagnostics <- function() {
  data.frame(
    diagnostic_type = character(),
    activity_id = character(),
    from_sample_index = integer(),
    to_sample_index = integer(),
    from_latitude = numeric(),
    from_longitude = numeric(),
    to_latitude = numeric(),
    to_longitude = numeric(),
    elapsed_time_difference_seconds = numeric(),
    geographic_displacement_metres = numeric(),
    implied_geographic_speed_metres_per_second = numeric(),
    device_distance_difference_metres = numeric(),
    gps_device_distance_signed_difference_metres = numeric(),
    gps_device_distance_absolute_difference_metres = numeric(),
    gps_device_distance_relative_discrepancy = numeric(),
    stringsAsFactors = FALSE
  )
}

track_segment_diagnostic_rows <- function(
  segments,
  indexes,
  diagnostic_type,
  limit
) {
  indexes <- indexes[seq_len(min(length(indexes), limit))]
  if (length(indexes) == 0L) return(empty_track_diagnostics())

  result <- segments[indexes, , drop = FALSE]
  result$diagnostic_type <- diagnostic_type
  result[, names(empty_track_diagnostics()), drop = FALSE]
}

track_point_diagnostic_rows <- function(
  samples,
  indexes,
  diagnostic_type,
  activity_id,
  limit
) {
  indexes <- indexes[seq_len(min(length(indexes), limit))]
  if (length(indexes) == 0L) return(empty_track_diagnostics())

  data.frame(
    diagnostic_type = rep(diagnostic_type, length(indexes)),
    activity_id = rep(activity_id, length(indexes)),
    from_sample_index = as.integer(samples$sample_index[indexes]),
    to_sample_index = as.integer(samples$sample_index[indexes]),
    from_latitude = as.numeric(samples$latitude[indexes]),
    from_longitude = as.numeric(samples$longitude[indexes]),
    to_latitude = as.numeric(samples$latitude[indexes]),
    to_longitude = as.numeric(samples$longitude[indexes]),
    elapsed_time_difference_seconds = NA_real_,
    geographic_displacement_metres = NA_real_,
    implied_geographic_speed_metres_per_second = NA_real_,
    device_distance_difference_metres = NA_real_,
    gps_device_distance_signed_difference_metres = NA_real_,
    gps_device_distance_absolute_difference_metres = NA_real_,
    gps_device_distance_relative_discrepancy = NA_real_,
    stringsAsFactors = FALSE
  )
}

#' Profile One Activity Track
#'
#' Measures point and consecutive-observation integrity without deciding whether
#' an activity or segment is suitable for interpolation, Explorer tiles, or
#' country allocation. Input order is preserved: malformed ordering is reported,
#' never silently repaired.
#'
#' @param samples One activity's Silver stream samples in retrieval order.
#' @param diagnostic_limit Maximum rows retained for each diagnostic category.
#' @param include_segments Return the derived consecutive-segment frame. This is
#'   intended for bounded calibration tooling; the default keeps the POC's
#'   memory-light public result unchanged.
#'
#' @return A list containing `summary` (named activity metrics) and a bounded
#'   `diagnostics` data frame.
profile_activity_track_integrity <- function(
  samples,
  diagnostic_limit = 5L,
  include_segments = FALSE
) {
  required_columns <- c(
    "activity_id", "sample_index", "latitude", "longitude",
    "time_seconds", "distance_metres"
  )
  missing_columns <- setdiff(required_columns, names(samples))
  if (length(missing_columns) > 0L) {
    stop(
      "Track samples are missing required column(s): ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }
  if (length(diagnostic_limit) != 1L || is.na(diagnostic_limit) ||
      diagnostic_limit < 1L || diagnostic_limit != as.integer(diagnostic_limit)) {
    stop("diagnostic_limit must be a positive integer.", call. = FALSE)
  }
  diagnostic_limit <- as.integer(diagnostic_limit)
  if (length(include_segments) != 1L || is.na(include_segments) ||
      !is.logical(include_segments)) {
    stop("include_segments must be TRUE or FALSE.", call. = FALSE)
  }

  if (nrow(samples) == 0L) {
    result <- list(
      summary = list(
        activity_id = NA_character_, sample_count = 0L,
        valid_coordinate_count = 0L, invalid_coordinate_count = 0L,
        zero_zero_coordinate_count = 0L,
        first_sample_index = NA_integer_, last_sample_index = NA_integer_,
        sample_index_non_increasing_count = 0L, sample_index_gap_count = 0L,
        elapsed_time_interval_seconds = track_metric_distribution(numeric()),
        geographic_displacement_metres = track_metric_distribution(numeric()),
        implied_geographic_speed_metres_per_second = track_metric_distribution(numeric()),
        device_distance_increment_metres = track_metric_distribution(numeric()),
        gps_device_distance_signed_difference_metres = track_metric_distribution(numeric()),
        gps_device_distance_absolute_difference_metres = track_metric_distribution(numeric()),
        gps_device_distance_relative_discrepancy = track_metric_distribution(numeric()),
        non_increasing_timestamp_count = 0L,
        duplicate_timestamp_count = 0L,
        decreasing_timestamp_count = 0L,
        decreasing_cumulative_distance_count = 0L,
        repeated_cumulative_distance_count = 0L,
        repeated_coordinate_segment_count = 0L,
        maximum_time_gap_seconds = NA_real_,
        maximum_implied_geographic_speed_metres_per_second = NA_real_
      ),
      diagnostics = empty_track_diagnostics()
    )
    if (include_segments) {
      result$segments <- empty_track_diagnostics()[
        , setdiff(names(empty_track_diagnostics()), "diagnostic_type"), drop = FALSE
      ]
    }
    return(result)
  }

  activity_ids <- unique(as.character(samples$activity_id))
  if (length(activity_ids) != 1L || is.na(activity_ids[[1]]) || !nzchar(activity_ids[[1]])) {
    stop("Track samples must contain exactly one non-missing activity_id.", call. = FALSE)
  }
  activity_id <- activity_ids[[1]]

  numeric_columns <- c(
    "sample_index", "latitude", "longitude", "time_seconds", "distance_metres"
  )
  if (any(!vapply(samples[numeric_columns], is.numeric, logical(1)))) {
    stop("Track sample measurement columns must be numeric.", call. = FALSE)
  }

  valid_coordinates <- track_coordinate_is_valid(samples$latitude, samples$longitude)
  zero_zero <- valid_coordinates & samples$latitude == 0 & samples$longitude == 0
  sample_index_delta <- diff(samples$sample_index)

  segment_count <- max(0L, nrow(samples) - 1L)
  if (segment_count > 0L) {
    from <- seq_len(segment_count)
    to <- from + 1L
    valid_endpoints <- valid_coordinates[from] & valid_coordinates[to]
    displacement <- rep(NA_real_, segment_count)
    displacement[valid_endpoints] <- haversine_distance_metres(
      samples$latitude[from][valid_endpoints],
      samples$longitude[from][valid_endpoints],
      samples$latitude[to][valid_endpoints],
      samples$longitude[to][valid_endpoints]
    )
    elapsed_delta <- samples$time_seconds[to] - samples$time_seconds[from]
    distance_delta <- samples$distance_metres[to] - samples$distance_metres[from]
    implied_speed <- rep(NA_real_, segment_count)
    speed_eligible <- is.finite(displacement) & is.finite(elapsed_delta) & elapsed_delta > 0
    implied_speed[speed_eligible] <- displacement[speed_eligible] / elapsed_delta[speed_eligible]

    discrepancy_eligible <- is.finite(displacement) & is.finite(distance_delta)
    signed_distance_difference <- rep(NA_real_, segment_count)
    signed_distance_difference[discrepancy_eligible] <-
      displacement[discrepancy_eligible] - distance_delta[discrepancy_eligible]
    absolute_distance_difference <- abs(signed_distance_difference)
    relative_distance_discrepancy <- rep(NA_real_, segment_count)
    discrepancy_denominator <- pmax(abs(displacement), abs(distance_delta))
    both_effectively_zero <- discrepancy_eligible & discrepancy_denominator <= 1e-9
    relative_distance_discrepancy[both_effectively_zero] <- 0
    relative_eligible <- discrepancy_eligible & !both_effectively_zero
    relative_distance_discrepancy[relative_eligible] <-
      absolute_distance_difference[relative_eligible] /
        discrepancy_denominator[relative_eligible]

    segments <- data.frame(
      activity_id = rep(activity_id, segment_count),
      from_sample_index = as.integer(samples$sample_index[from]),
      to_sample_index = as.integer(samples$sample_index[to]),
      from_latitude = as.numeric(samples$latitude[from]),
      from_longitude = as.numeric(samples$longitude[from]),
      to_latitude = as.numeric(samples$latitude[to]),
      to_longitude = as.numeric(samples$longitude[to]),
      elapsed_time_difference_seconds = as.numeric(elapsed_delta),
      geographic_displacement_metres = displacement,
      implied_geographic_speed_metres_per_second = implied_speed,
      device_distance_difference_metres = as.numeric(distance_delta),
      gps_device_distance_signed_difference_metres = signed_distance_difference,
      gps_device_distance_absolute_difference_metres = absolute_distance_difference,
      gps_device_distance_relative_discrepancy = relative_distance_discrepancy,
      stringsAsFactors = FALSE
    )
  } else {
    elapsed_delta <- distance_delta <- displacement <- implied_speed <- numeric()
    signed_distance_difference <- absolute_distance_difference <-
      relative_distance_discrepancy <- numeric()
    segments <- empty_track_diagnostics()[, setdiff(names(empty_track_diagnostics()), "diagnostic_type"), drop = FALSE]
  }

  descending_finite <- function(values) {
    indexes <- which(is.finite(values))
    indexes[order(values[indexes], decreasing = TRUE)]
  }

  diagnostics <- rbind(
    track_segment_diagnostic_rows(
      segments,
      descending_finite(ifelse(elapsed_delta > 0, elapsed_delta, NA_real_)),
      "LARGEST_TIME_GAP",
      diagnostic_limit
    ),
    track_segment_diagnostic_rows(
      segments, descending_finite(implied_speed), "HIGHEST_IMPLIED_SPEED", diagnostic_limit
    ),
    track_segment_diagnostic_rows(
      segments, descending_finite(displacement), "LARGEST_DISPLACEMENT", diagnostic_limit
    ),
    track_segment_diagnostic_rows(
      segments,
      descending_finite(absolute_distance_difference),
      "LARGEST_GPS_DEVICE_DISTANCE_DISCREPANCY",
      diagnostic_limit
    ),
    track_segment_diagnostic_rows(
      segments, which(is.finite(elapsed_delta) & elapsed_delta <= 0),
      "NON_INCREASING_TIME", diagnostic_limit
    ),
    track_segment_diagnostic_rows(
      segments, which(is.finite(distance_delta) & distance_delta < 0),
      "DISTANCE_REGRESSION", diagnostic_limit
    ),
    track_point_diagnostic_rows(
      samples, which(!valid_coordinates), "INVALID_COORDINATE", activity_id, diagnostic_limit
    ),
    track_point_diagnostic_rows(
      samples, which(zero_zero), "ZERO_ZERO_COORDINATE", activity_id, diagnostic_limit
    ),
    track_segment_diagnostic_rows(
      segments, which(is.finite(sample_index_delta) & sample_index_delta <= 0),
      "NON_INCREASING_SAMPLE_INDEX", diagnostic_limit
    ),
    track_segment_diagnostic_rows(
      segments, which(is.finite(sample_index_delta) & sample_index_delta > 1),
      "SAMPLE_INDEX_GAP", diagnostic_limit
    )
  )
  rownames(diagnostics) <- NULL

  result <- list(
    summary = list(
      activity_id = activity_id,
      sample_count = nrow(samples),
      valid_coordinate_count = sum(valid_coordinates),
      invalid_coordinate_count = sum(!valid_coordinates),
      zero_zero_coordinate_count = sum(zero_zero),
      first_sample_index = as.integer(samples$sample_index[[1]]),
      last_sample_index = as.integer(samples$sample_index[[nrow(samples)]]),
      sample_index_non_increasing_count = sum(sample_index_delta <= 0, na.rm = TRUE),
      sample_index_gap_count = sum(sample_index_delta > 1, na.rm = TRUE),
      elapsed_time_interval_seconds = track_metric_distribution(elapsed_delta),
      geographic_displacement_metres = track_metric_distribution(displacement),
      implied_geographic_speed_metres_per_second = track_metric_distribution(implied_speed),
      device_distance_increment_metres = track_metric_distribution(distance_delta),
      gps_device_distance_signed_difference_metres = track_metric_distribution(signed_distance_difference),
      gps_device_distance_absolute_difference_metres = track_metric_distribution(absolute_distance_difference),
      gps_device_distance_relative_discrepancy = track_metric_distribution(relative_distance_discrepancy),
      non_increasing_timestamp_count = sum(elapsed_delta <= 0, na.rm = TRUE),
      duplicate_timestamp_count = sum(elapsed_delta == 0, na.rm = TRUE),
      decreasing_timestamp_count = sum(elapsed_delta < 0, na.rm = TRUE),
      decreasing_cumulative_distance_count = sum(distance_delta < 0, na.rm = TRUE),
      repeated_cumulative_distance_count = sum(distance_delta == 0, na.rm = TRUE),
      repeated_coordinate_segment_count = sum(displacement == 0, na.rm = TRUE),
      maximum_time_gap_seconds = if (any(is.finite(elapsed_delta) & elapsed_delta > 0)) {
        max(elapsed_delta[is.finite(elapsed_delta) & elapsed_delta > 0])
      } else {
        NA_real_
      },
      maximum_implied_geographic_speed_metres_per_second = if (any(is.finite(implied_speed))) max(implied_speed, na.rm = TRUE) else NA_real_
    ),
    diagnostics = diagnostics
  )
  if (include_segments) result$segments <- segments
  result
}

validate_track_audit_activity_ids <- function(activity_ids, maximum_ids = 50L) {
  activity_ids <- unique(trimws(as.character(activity_ids)))
  if (length(activity_ids) == 0L || any(!nzchar(activity_ids))) {
    stop("Provide at least one explicit activity ID.", call. = FALSE)
  }
  if (length(activity_ids) > maximum_ids) {
    stop("At most ", maximum_ids, " activity IDs may be audited at once.", call. = FALSE)
  }
  if (any(!grepl("^[0-9]+$", activity_ids))) {
    stop("Activity IDs must contain digits only.", call. = FALSE)
  }
  activity_ids
}

#' Fetch Explicit Silver Activity Tracks
#'
#' Read-only retrieval for a deliberately bounded list of activity IDs.
fetch_activity_track_samples <- function(
  connection,
  activity_ids,
  get_query = DBI::dbGetQuery
) {
  activity_ids <- validate_track_audit_activity_ids(activity_ids)
  placeholders <- paste(rep("?", length(activity_ids)), collapse = ", ")
  get_query(
    connection,
    paste0(
      "SELECT activity_id, sample_index, latitude, longitude, time_seconds, ",
      "distance_metres FROM cycling_platform_silver.activity_streams ",
      "WHERE activity_id IN (", placeholders, ") ",
      "ORDER BY activity_id, sample_index"
    ),
    params = as.list(activity_ids)
  )
}

track_integrity_summary_row <- function(result) {
  summary <- result$summary
  data.frame(
    activity_id = summary$activity_id,
    sample_count = summary$sample_count,
    valid_coordinates = summary$valid_coordinate_count,
    invalid_coordinates = summary$invalid_coordinate_count,
    zero_zero_coordinates = summary$zero_zero_coordinate_count,
    non_increasing_sample_indexes = summary$sample_index_non_increasing_count,
    sample_index_gaps = summary$sample_index_gap_count,
    non_increasing_timestamps = summary$non_increasing_timestamp_count,
    decreasing_distances = summary$decreasing_cumulative_distance_count,
    repeated_coordinates = summary$repeated_coordinate_segment_count,
    maximum_time_gap_seconds = summary$maximum_time_gap_seconds,
    maximum_implied_speed_mps = summary$maximum_implied_geographic_speed_metres_per_second,
    maximum_gps_device_absolute_difference_metres =
      unname(summary$gps_device_distance_absolute_difference_metres[["maximum"]]),
    maximum_gps_device_relative_discrepancy =
      unname(summary$gps_device_distance_relative_discrepancy[["maximum"]]),
    p50_time_interval_seconds = unname(summary$elapsed_time_interval_seconds[["p50"]]),
    p99_time_interval_seconds = unname(summary$elapsed_time_interval_seconds[["p99"]]),
    p99_displacement_metres = unname(summary$geographic_displacement_metres[["p99"]]),
    p99_implied_speed_mps = unname(summary$implied_geographic_speed_metres_per_second[["p99"]]),
    stringsAsFactors = FALSE
  )
}

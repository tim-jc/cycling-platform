geographic_evidence_path <- function(...) {
  path <- file.path(...)
  if (!file.exists(path)) path <- file.path("..", "..", path)
  path
}

source(geographic_evidence_path("R", "quality", "profile_activity_track_integrity.R"))
source(geographic_evidence_path("R", "quality", "calibrate_activity_track_integrity.R"))
source(geographic_evidence_path("R", "quality", "profile_geographic_calibration_evidence.R"))

geographic_samples <- function(
  latitude = c(53, 53.001, 53.002), longitude = rep(-2, length(latitude)),
  time_seconds = seq(0, by = 1, length.out = length(latitude)),
  distance_metres = seq(0, by = 100, length.out = length(latitude)),
  activity_id = "123"
) {
  data.frame(
    activity_id = activity_id, sample_index = seq_along(latitude),
    latitude = latitude, longitude = longitude, time_seconds = time_seconds,
    distance_metres = distance_metres, stringsAsFactors = FALSE
  )
}

geographic_candidates <- function(n = 12L) {
  sequence <- seq_len(n)
  data.frame(
    activity_id = as.character(8000000000 + sequence),
    activity_name = paste("Outdoor", sequence),
    sport_type = rep(c("Ride", "Run", "Hike"), length.out = n),
    is_manual = 0L,
    start_datetime_utc = as.POSIXct("2020-01-01", tz = "UTC") + sequence * 86400,
    start_datetime_local = as.POSIXct("2020-01-01", tz = "UTC") + sequence * 86400,
    start_date_local = as.Date("2020-01-01") + sequence,
    distance_metres = sequence * 1000, moving_time_seconds = 900 + sequence,
    elapsed_time_seconds = 1200 + sequence, gps_sample_count = 100 + sequence,
    time_sample_count = 100 + sequence, distance_sample_count = 100 + sequence,
    gps_retrieved_at = as.POSIXct("2026-01-01", tz = "UTC"),
    source_trainer = "false", provenance_text = "outdoor",
    deterministic_rank = sprintf("%064d", rev(sequence)), stringsAsFactors = FALSE
  )
}

geographic_context <- function(samples, indexes = samples$sample_index) {
  profile <- profile_activity_track_integrity(samples, include_segments = TRUE)
  activity_observation_local_context(samples, profile$segments, indexes)
}

testthat::test_that("isolated excursion has two jumps, a short bridge and reversal", {
  context <- geographic_context(geographic_samples(
    latitude = c(53, 54, 53.0001), time_seconds = c(0, 1, 2),
    distance_metres = c(0, 100, 200)
  ), 2L)

  testthat::expect_gt(context$previous_to_current_displacement_metres, 100000)
  testthat::expect_gt(context$current_to_next_displacement_metres, 100000)
  testthat::expect_lt(context$previous_to_next_displacement_metres, 20)
  testthat::expect_gt(context$absolute_bearing_change_degrees, 170)
})

testthat::test_that("recording gaps and stationary intervals preserve supporting evidence", {
  moving <- geographic_context(geographic_samples(
    latitude = c(53, 53.001, 53.01), time_seconds = c(0, 1, 601),
    distance_metres = c(0, 100, 1100)
  ), 2L)
  stationary <- geographic_context(geographic_samples(
    latitude = rep(53, 3), time_seconds = c(0, 1, 3601),
    distance_metres = c(0, 0, 0)
  ), 2L)

  testthat::expect_equal(moving$current_to_next_elapsed_seconds, 600)
  testthat::expect_true(is.finite(moving$current_to_next_implied_speed_mps))
  testthat::expect_equal(stationary$current_to_next_displacement_metres, 0)
  testthat::expect_equal(stationary$current_to_next_implied_speed_mps, 0)
})

testthat::test_that("duplicate timestamps and missing coordinates never fabricate speed or geometry", {
  duplicate <- geographic_context(geographic_samples(
    time_seconds = c(0, 0, 1)
  ), 1L)
  missing <- geographic_context(geographic_samples(
    latitude = c(53, NA, 53.002)
  ), 2L)

  testthat::expect_equal(duplicate$current_to_next_elapsed_seconds, 0)
  testthat::expect_true(is.na(duplicate$current_to_next_implied_speed_mps))
  testthat::expect_true(is.na(missing$previous_to_current_displacement_metres))
  testthat::expect_true(is.na(missing$current_to_next_displacement_metres))
  testthat::expect_true(is.finite(missing$previous_to_next_displacement_metres))
  testthat::expect_true(is.na(missing$absolute_bearing_change_degrees))

  incomplete <- geographic_samples()
  incomplete$time_seconds[[2]] <- NA_real_
  incomplete$distance_metres[[2]] <- NA_real_
  incomplete_context <- geographic_context(incomplete, 2L)
  testthat::expect_true(is.na(incomplete_context$previous_to_current_elapsed_seconds))
  testthat::expect_true(is.na(incomplete_context$previous_to_current_device_distance_metres))
  testthat::expect_true(is.na(incomplete_context$previous_to_current_implied_speed_mps))
})

testthat::test_that("boundaries remain missing and repeated-coordinate runs are measured", {
  samples <- geographic_samples(
    latitude = c(53, 53, 53, 53.001), longitude = rep(-2, 4),
    time_seconds = c(0, 5, 10, 11), distance_metres = c(0, 0, 0, 100)
  )
  context <- geographic_context(samples, c(1L, 2L, 4L))

  testthat::expect_true(is.na(context$previous_sample_index[context$sample_index == 1L]))
  testthat::expect_true(is.na(context$next_sample_index[context$sample_index == 4L]))
  middle <- context[context$sample_index == 2L, ]
  testthat::expect_equal(middle$repeated_coordinate_run_length, 3L)
  testthat::expect_equal(middle$repeated_coordinate_run_elapsed_seconds, 10)
})

testthat::test_that("population aggregation is deterministic with explicit denominators", {
  samples <- geographic_samples(latitude = c(53, 53, NA, 53.003))
  segments <- profile_activity_track_integrity(samples, include_segments = TRUE)$segments
  first <- new_geographic_population_aggregator()
  second <- new_geographic_population_aggregator()
  add_activity_to_geographic_population(first, segments, "CYCLING", "MIDDLE", 4L)
  add_activity_to_geographic_population(second, segments, "CYCLING", "MIDDLE", 4L)
  one <- geographic_population_aggregation_result(first)
  two <- geographic_population_aggregation_result(second)

  testthat::expect_equal(one, two)
  testthat::expect_equal(one$activity_count, 1L)
  testthat::expect_equal(one$sample_count, 4L)
  testthat::expect_equal(one$segment_count, 3L)
  testthat::expect_true(all(
    one$stratum_summary$segment_denominator ==
      one$stratum_summary$valid_count + one$stratum_summary$missing_count +
        one$stratum_summary$invalid_count
  ))
})

testthat::test_that("population runner is deterministic, sequential and bounded", {
  candidates <- geographic_candidates(12L)
  active <- maximum_active <- 0L
  fetch <- function(connection, activity_id) {
    active <<- active + 1L
    maximum_active <<- max(maximum_active, active)
    on.exit(active <<- active - 1L)
    geographic_samples(activity_id = activity_id)
  }
  first <- run_geographic_population_calibration(
    NULL, candidates, maximum_activities = 6L, get_samples = fetch
  )
  second <- run_geographic_population_calibration(
    NULL, candidates, maximum_activities = 6L, get_samples = fetch
  )

  testthat::expect_equal(first$activity_execution$activity_id,
    second$activity_execution$activity_id)
  testthat::expect_equal(first$histogram, second$histogram)
  testthat::expect_equal(maximum_active, 1L)
  testthat::expect_equal(first$eligible_population_count, 12L)
  testthat::expect_equal(first$activity_count, 6L)
  testthat::expect_false("segments" %in% names(first))
})

testthat::test_that("reference registry distinguishes current and cropped historical evidence", {
  requests <- geographic_reference_window_requests()
  testthat::expect_setequal(unique(requests$activity_id), c(
    "20445541114", "3057187825", "2705450947", "31709557",
    "659466921", "9283774065", "15562928333", "227124704"
  ))
  cropped <- requests$activity_id %in% c("659466921", "227124704")
  testthat::expect_true(all(requests$evidence_provenance[cropped] ==
    "HISTORICAL_EVIDENCE_REQUIRED"))
  testthat::expect_true(all(is.na(requests$focus_from_sample_index[cropped])))
})

testthat::test_that("manual labels keep observation and segment grains and split by activity", {
  observations <- data.frame(
    activity_id = c("1", "2"), sample_index = c(10L, 20L),
    case_key = c("A", "B"), evidence_provenance = "CURRENT", stringsAsFactors = FALSE
  )
  segments <- data.frame(
    activity_id = c("1", "2"), from_sample_index = c(10L, 20L),
    to_sample_index = c(11L, 21L), case_key = c("A", "B"),
    evidence_provenance = "CURRENT", stringsAsFactors = FALSE
  )
  labels <- geographic_manual_label_template(observations, segments)

  testthat::expect_setequal(labels$entity_type, c("OBSERVATION", "SEGMENT"))
  testthat::expect_true(all(labels$manual_label == "UNREVIEWED"))
  testthat::expect_equal(length(unique(labels$calibration_partition[labels$activity_id == "1"])), 1L)
  testthat::expect_silent(validate_geographic_manual_labels(labels))
  labels$manual_label[[1]] <- "AUTOMATICALLY_REJECTED"
  testthat::expect_error(validate_geographic_manual_labels(labels), "Unsupported")
})

testthat::test_that("reference extraction is bounded and unresolved windows remain explicit", {
  requests <- data.frame(
    case_key = c("LOCATED", "UNLOCATED"), activity_id = c("1", "2"),
    focus_from_sample_index = c(2L, NA_integer_),
    focus_to_sample_index = c(3L, NA_integer_), window_radius = c(1L, 1L),
    evidence_provenance = c("CURRENT", "CURRENT_SOURCE_LOOKUP_REQUIRED"),
    evidence_note = c("fixture", "locate by review"), stringsAsFactors = FALSE
  )
  result <- extract_geographic_reference_windows(
    NULL, requests,
    get_samples = function(connection, activity_id) geographic_samples(activity_id = activity_id)
  )

  testthat::expect_equal(nrow(result$observations), 3L)
  testthat::expect_equal(nrow(result$segments), 2L)
  testthat::expect_setequal(result$status$extraction_status,
    c("SUCCESS", "WINDOW_NOT_LOCATED"))
  testthat::expect_true(all(result$observations$case_key == "LOCATED"))
})

testthat::test_that("population and reference outputs are bounded named reports", {
  state <- new_geographic_population_aggregator()
  segments <- profile_activity_track_integrity(
    geographic_samples(), include_segments = TRUE
  )$segments
  add_activity_to_geographic_population(state, segments, "CYCLING", "LOW", 3L)
  population <- geographic_population_aggregation_result(state)
  population$activity_execution <- data.frame(
    activity_id = "1", processing_status = "SUCCESS", stringsAsFactors = FALSE
  )
  directory <- tempfile()
  write_geographic_population_calibration_outputs(population, directory)
  testthat::expect_setequal(list.files(directory), c(
    "population_activity_execution.csv", "population_failures.csv",
    "population_segment_histogram.csv", "population_stratum_summary.csv"
  ))
})

testthat::test_that("population writer checks every collision before writing", {
  population <- list(
    histogram = data.frame(metric = "elapsed", segment_count = 1),
    stratum_summary = data.frame(metric = "elapsed", valid_count = 1),
    activity_execution = data.frame(
      activity_id = "1", processing_status = "SUCCESS", stringsAsFactors = FALSE
    )
  )
  directory <- tempfile("gps-population-collision-")
  dir.create(directory)
  collision <- file.path(directory, "population_failures.csv")
  writeBin(charToRaw("existing population evidence"), collision)
  before <- readBin(collision, "raw", n = file.info(collision)$size)

  testthat::expect_error(
    write_geographic_population_calibration_outputs(population, directory),
    "Refusing to overwrite"
  )
  testthat::expect_identical(
    readBin(collision, "raw", n = file.info(collision)$size), before
  )
  testthat::expect_setequal(list.files(directory), "population_failures.csv")
})

testthat::test_that("reference writer accepts new and empty external destinations", {
  result <- list(
    observations = data.frame(
      activity_id = "1", sample_index = 10L, case_key = "CASE",
      evidence_provenance = "FIXTURE", stringsAsFactors = FALSE
    ),
    segments = data.frame(
      activity_id = "1", from_sample_index = 10L, to_sample_index = 11L,
      case_key = "CASE", evidence_provenance = "FIXTURE", stringsAsFactors = FALSE
    ),
    status = data.frame(
      activity_id = "1", extraction_status = "SUCCESS", stringsAsFactors = FALSE
    )
  )
  for (directory in c(tempfile("gps-reference-new-"), tempfile("gps-reference-empty-"))) {
    if (grepl("empty", directory, fixed = TRUE)) dir.create(directory)
    testthat::expect_silent(
      write_geographic_reference_window_outputs(result, directory)
    )
    testthat::expect_identical(
      names(utils::read.csv(file.path(directory, "reference_window_observations.csv"))),
      names(result$observations)
    )
  }
})

testthat::test_that("reference writer rejects local and symlinked repository destinations", {
  repository <- normalizePath(geographic_evidence_path("."), mustWork = TRUE)
  local_destination <- tempfile("gps-reference-", tmpdir = repository)
  testthat::expect_error(
    write_geographic_reference_window_outputs(list(), local_destination),
    "outside the repository"
  )

  link <- tempfile("gps-reference-link-")
  testthat::skip_if_not(file.symlink(repository, link), "Symbolic links unavailable")
  testthat::expect_error(
    write_geographic_reference_window_outputs(
      list(), file.path(link, "nested"), repository_root = repository
    ),
    "outside the repository"
  )
})

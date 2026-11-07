batch_test_path <- function(...) {
  path <- file.path(...)
  if (!file.exists(path)) path <- file.path("..", "..", path)
  path
}

source(batch_test_path("R", "quality", "profile_activity_track_integrity.R"))
source(batch_test_path("R", "quality", "profile_geographic_calibration_evidence.R"))
source(batch_test_path("R", "quality", "fetch_gps_investigation_evidence.R"))
source(batch_test_path("R", "quality", "extract_duplicate_timestamp_evidence.R"))
source(batch_test_path("R", "quality", "extract_governed_gps_reference_window.R"))
source(batch_test_path("R", "quality", "extract_gps_qualification_batch.R"))

qualification_batch_fixture <- function(count = 24L, activity_id = "48062184") {
  time <- seq.int(0L, count - 1L)
  latitude <- 51 + seq_len(count) / 100000
  longitude <- -0.3 - seq_len(count) / 100000
  distance <- seq(0, by = 5, length.out = count)
  raw <- data.frame(
    activity_id = activity_id,
    stream_type = c("time", "latlng", "distance"),
    original_size = count,
    stream_payload = c(
      jsonlite::toJSON(as.list(time), auto_unbox = TRUE),
      jsonlite::toJSON(Map(c, latitude, longitude), auto_unbox = TRUE, digits = NA),
      jsonlite::toJSON(as.list(distance), auto_unbox = TRUE)
    ),
    stringsAsFactors = FALSE
  )
  parsed_latlng <- jsonlite::fromJSON(
    raw$stream_payload[raw$stream_type == "latlng"],
    simplifyVector = FALSE
  )
  silver <- data.frame(
    activity_id = activity_id, sample_index = seq_len(count),
    time_seconds = time,
    latitude = vapply(parsed_latlng, \(value) as.numeric(value[[1L]]), numeric(1)),
    longitude = vapply(parsed_latlng, \(value) as.numeric(value[[2L]]), numeric(1)),
    distance_metres = distance, stringsAsFactors = FALSE
  )
  list(raw_streams = raw, silver_samples = silver)
}

qualification_batch_request <- function(
  activity_id = "48062184", case_key = "CASE", from = 4L, to = 18L,
  focus_from = 10L, focus_to = 11L
) {
  data.frame(
    activity_id = activity_id, case_key = case_key,
    window_from_sample_index = from, window_to_sample_index = to,
    focus_from_sample_index = focus_from, focus_to_sample_index = focus_to,
    focus_segment_from_sample_index = focus_from,
    focus_segment_to_sample_index = focus_to,
    evidence_note = "synthetic fixture", stringsAsFactors = FALSE
  )
}

build_qualification_batch_fixture <- function(source = qualification_batch_fixture(),
                                              request = qualification_batch_request()) {
  governed <- build_governed_gps_reference_window(
    source$raw_streams, source$silver_samples,
    request$window_from_sample_index, request$window_to_sample_index,
    request$focus_from_sample_index, request$focus_to_sample_index,
    request$focus_segment_from_sample_index,
    request$focus_segment_to_sample_index,
    request$case_key, request$evidence_note
  )
  diagnostics <- build_gps_qualification_context_diagnostics(
    source, request, governed
  )
  list(governed = governed, diagnostics = diagnostics)
}

testthat::test_that("experimental context reports three and five segment evidence", {
  fixture <- build_qualification_batch_fixture()
  observations <- fixture$diagnostics$observation_context
  segments <- fixture$diagnostics$segment_context

  testthat::expect_equal(sort(unique(observations$context_window_segments)), c(3L, 5L))
  testthat::expect_equal(sort(unique(segments$context_window_segments)), c(3L, 5L))
  testthat::expect_equal(nrow(observations), 4L)
  testthat::expect_equal(nrow(segments), 6L)
  testthat::expect_true(all(observations$preceding_context_complete))
  testthat::expect_true(all(observations$following_context_complete))
  testthat::expect_true(all(is.finite(segments$focus_displacement_to_neighbour_median_ratio)))
  testthat::expect_identical(
    fixture$diagnostics$source_context$device_distance_provenance, "UNKNOWN"
  )
})

testthat::test_that("actual boundaries and unavailable review segments stay explicit", {
  source <- qualification_batch_fixture(count = 12L)
  request <- qualification_batch_request(from = 1L, to = 7L, focus_from = 1L, focus_to = 2L)
  fixture <- build_qualification_batch_fixture(source, request)
  review <- build_gps_qualification_manual_review_worksheet(
    request, source, fixture$diagnostics
  )

  testthat::expect_true(fixture$diagnostics$source_context$requested_start_is_actual_boundary)
  testthat::expect_false(fixture$diagnostics$source_context$requested_end_is_actual_boundary)
  testthat::expect_false(all(fixture$diagnostics$observation_context$preceding_context_complete))
  testthat::expect_equal(nrow(review), 5L)
  testthat::expect_true(all(review$manual_label == "UNREVIEWED"))
  preceding <- review$review_role == "IMMEDIATELY_PRECEDING_SEGMENT"
  testthat::expect_equal(review$availability_status[preceding], "NOT_APPLICABLE")
  testthat::expect_equal(review$not_applicable_reason[preceding], "TRUE_ACTIVITY_START")
})

testthat::test_that("missing measurements and timestamp anomalies are not converted to zero", {
  source <- qualification_batch_fixture()
  source$silver_samples$latitude[[8L]] <- NA_real_
  source$silver_samples$longitude[[8L]] <- NA_real_
  source$silver_samples$distance_metres[[9L]] <- NA_real_
  source$silver_samples$time_seconds[[12L]] <- source$silver_samples$time_seconds[[11L]]
  profile <- profile_activity_track_integrity(source$silver_samples, include_segments = TRUE)
  stationary <- gps_exact_stationary_run_evidence(source$silver_samples)
  row <- gps_context_observation_row(
    source$silver_samples, profile$segments, stationary, 10L, "CASE", 5L
  )

  testthat::expect_lt(row$preceding_displacement_metres_valid_count, 5L)
  testthat::expect_lt(row$preceding_relative_discrepancy_valid_count, 5L)
  testthat::expect_gt(row$following_nonpositive_elapsed_count, 0L)
})

testthat::test_that("stationary runs and zero bridge displacement are preserved", {
  source <- qualification_batch_fixture(count = 14L)
  source$silver_samples$latitude[4:10] <- source$silver_samples$latitude[[4L]]
  source$silver_samples$longitude[4:10] <- source$silver_samples$longitude[[4L]]
  source$silver_samples$distance_metres[4:10] <- source$silver_samples$distance_metres[[4L]]
  profile <- profile_activity_track_integrity(source$silver_samples, include_segments = TRUE)
  stationary <- gps_exact_stationary_run_evidence(source$silver_samples)
  row <- gps_context_observation_row(
    source$silver_samples, profile$segments, stationary, 7L, "CASE", 3L
  )

  testthat::expect_equal(row$exact_stationary_run_length, 7L)
  testthat::expect_equal(row$exact_stationary_run_position, "INTERIOR")
  testthat::expect_true(row$bridge_distance_zero)
  testthat::expect_true(is.na(row$path_to_bridge_ratio))
})

testthat::test_that("bearing summaries handle north wraparound", {
  testthat::expect_gt(gps_context_circular_resultant_length(c(359, 1, 2)), 0.99)
  testthat::expect_equal(gps_context_maximum_bearing_change(c(359, 1, 2)), 2)
})

testthat::test_that("source inputs and output ordering remain deterministic", {
  source <- qualification_batch_fixture()
  original <- unserialize(serialize(source, NULL))
  first <- build_qualification_batch_fixture(source)
  second <- build_qualification_batch_fixture(source)

  testthat::expect_identical(source, original)
  testthat::expect_equal(first$diagnostics, second$diagnostics)
  testthat::expect_equal(
    first$governed$reference_window_observations$sample_index, 4:18
  )
  testthat::expect_equal(
    first$governed$reference_window_segments$from_sample_index, 4:17
  )
})

testthat::test_that("batch validation binds focus segments, bounds, and partition", {
  request <- qualification_batch_request()
  diagnostic <- data.frame(
    activity_id = "48062184", from_sample_index = 10L, to_sample_index = 11L
  )
  manifest <- data.frame(activity_id = "48062184", gps_sample_count = 24L)
  validated <- validate_gps_qualification_batch_requests(request, diagnostic, manifest)

  testthat::expect_equal(validated$calibration_partition, "CALIBRATION")
  testthat::expect_equal(validated$recorded_sample_count, 24L)
  bad <- diagnostic
  bad$from_sample_index <- 9L
  testthat::expect_error(
    validate_gps_qualification_batch_requests(request, bad, manifest),
    "absent from the diagnostic artifact"
  )
  request$window_to_sample_index <- 25L
  testthat::expect_error(
    validate_gps_qualification_batch_requests(request, diagnostic, manifest),
    "exceed recorded sample count"
  )
})

testthat::test_that("all-case destination preflight prevents partial publication", {
  requests <- rbind(
    qualification_batch_request(case_key = "FIRST"),
    qualification_batch_request(case_key = "SECOND")
  )
  output <- tempfile("qualification-batch-")
  dir.create(file.path(output, "SECOND"), recursive = TRUE)
  collision <- file.path(output, "SECOND", "source_context_completeness.csv")
  writeBin(charToRaw("existing"), collision)

  testthat::expect_error(
    validate_gps_qualification_batch_destinations(requests, output),
    "Refusing to overwrite"
  )
  testthat::expect_false(dir.exists(file.path(output, "FIRST")))
  testthat::expect_identical(readBin(collision, "raw", 8L), charToRaw("existing"))
})

testthat::test_that("Batch 1 runner preflights before connection and remains read-only", {
  script <- paste(readLines(
    batch_test_path("scripts", "audits", "extract_gps_qualification_batch1.R"),
    warn = FALSE
  ), collapse = "\n")
  preflight <- regexpr("validate_gps_qualification_batch_destinations", script)[[1L]]
  connection <- regexpr("get_connection", script)[[1L]]

  testthat::expect_gt(preflight, 0L)
  testthat::expect_gt(connection, preflight)
  testthat::expect_false(grepl("INSERT|UPDATE|DELETE|REPLACE|TRUNCATE", script))
})

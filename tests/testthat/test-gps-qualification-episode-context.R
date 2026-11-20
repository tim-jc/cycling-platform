episode_test_path <- function(...) {
  path <- file.path(...)
  if (!file.exists(path)) path <- file.path("..", "..", path)
  path
}

source(episode_test_path("R", "quality", "profile_activity_track_integrity.R"))
source(episode_test_path("R", "quality", "profile_geographic_calibration_evidence.R"))
source(episode_test_path("R", "quality", "fetch_gps_investigation_evidence.R"))
source(episode_test_path("R", "quality", "extract_duplicate_timestamp_evidence.R"))
source(episode_test_path("R", "quality", "extract_governed_gps_reference_window.R"))
source(episode_test_path("R", "quality", "extract_gps_qualification_batch.R"))
source(episode_test_path("R", "quality", "extract_gps_episode_context.R"))

episode_fixture <- function(count = 160L, activity_id = "48062184") {
  time <- cumsum(c(0, rep(1, count - 1L)))
  latitude <- 51 + seq_len(count) / 100000
  longitude <- -0.3 - seq_len(count) / 100000
  distance <- cumsum(c(0, rep(5, count - 1L)))
  raw <- data.frame(
    activity_id = activity_id, stream_type = c("time", "latlng", "distance"),
    original_size = count,
    stream_payload = c(
      jsonlite::toJSON(as.list(time), auto_unbox = TRUE),
      jsonlite::toJSON(Map(c, latitude, longitude), auto_unbox = TRUE, digits = NA),
      jsonlite::toJSON(as.list(distance), auto_unbox = TRUE)
    ), stringsAsFactors = FALSE
  )
  parsed_latlng <- jsonlite::fromJSON(
    raw$stream_payload[raw$stream_type == "latlng"], simplifyVector = FALSE
  )
  silver <- data.frame(
    activity_id = activity_id, sample_index = seq_len(count), time_seconds = time,
    latitude = vapply(parsed_latlng, \(value) as.numeric(value[[1L]]), numeric(1)),
    longitude = vapply(parsed_latlng, \(value) as.numeric(value[[2L]]), numeric(1)),
    distance_metres = distance,
    stringsAsFactors = FALSE
  )
  list(raw_streams = raw, silver_samples = silver)
}

episode_request <- function(type = "STANDARD_CONTEXT", from = 40L, to = 101L,
                            focus_from = 70L, focus_to = 71L) {
  data.frame(
    request_id = "STANDARD_CASE", request_type = type, case_key = "SOURCE_CASE",
    episode_id = "EPISODE", activity_id = "48062184",
    window_from_sample_index = from, window_to_sample_index = to,
    focus_from_sample_index = focus_from, focus_to_sample_index = focus_to,
    focus_segment_from_sample_index = focus_from,
    focus_segment_to_sample_index = focus_to,
    original_focus_observation_indices = paste(focus_from, focus_to, sep = ";"),
    original_focus_segment_pairs = paste0(focus_from, "-", focus_to),
    context_before_observations = if (type == "STANDARD_CONTEXT") 30L else NA_integer_,
    context_after_observations = if (type == "STANDARD_CONTEXT") 30L else NA_integer_,
    selection_rationale = "synthetic episode", calibration_partition = "CALIBRATION",
    overlap_group = "SYNTHETIC", source_evidence_path = tempfile(),
    source_evidence_sha256 = paste(rep("a", 64), collapse = ""),
    repository_revision = "fixture", extraction_version = GPS_STAGE2C_EXTRACTION_VERSION,
    recorded_sample_count = 160L,
    requested_start_is_actual_boundary = from == 1L,
    requested_end_is_actual_boundary = to == 160L,
    stringsAsFactors = FALSE
  )
}

testthat::test_that("descriptive episode evidence preserves samples and missingness", {
  source <- episode_fixture()
  source$silver_samples$distance_metres[[75L]] <- NA_real_
  raw_distance <- jsonlite::fromJSON(source$raw_streams$stream_payload[[3L]])
  raw_distance[[75L]] <- NA_real_
  source$raw_streams$stream_payload[[3L]] <- jsonlite::toJSON(
    as.list(raw_distance), auto_unbox = TRUE, na = "null"
  )
  result <- build_gps_stage2c_result(source, episode_request())
  testthat::expect_equal(result$descriptive_observations$sample_index, 40:101)
  testthat::expect_equal(result$descriptive_segments$from_sample_index, 40:100)
  testthat::expect_true(is.na(
    result$descriptive_segments$cumulative_device_distance_change_metres[[35L]]
  ))
  testthat::expect_true(all(result$observation_review_worksheet$manual_label == "UNREVIEWED"))
  testthat::expect_true(all(result$segment_review_worksheet$manual_label == "UNREVIEWED"))
})

testthat::test_that("request registry enforces durable provenance, bounds, and partition", {
  source_path <- tempfile(fileext = ".csv")
  writeLines("source evidence", source_path)
  request <- episode_request()
  request$source_evidence_path <- source_path
  request$source_evidence_sha256 <- digest::digest(
    source_path, algo = "sha256", file = TRUE
  )
  manifest <- data.frame(activity_id = "48062184", gps_sample_count = 160L)
  validated <- validate_gps_stage2c_request_registry(request, manifest)
  testthat::expect_equal(validated$window_from_sample_index, 40L)
  testthat::expect_equal(validated$window_to_sample_index, 101L)
  request$window_from_sample_index <- 39L
  testthat::expect_error(
    validate_gps_stage2c_request_registry(request, manifest),
    "30-observation rule"
  )
  request <- episode_request()
  request$source_evidence_path <- source_path
  request$source_evidence_sha256 <- digest::digest(
    source_path, algo = "sha256", file = TRUE
  )
  request$activity_id <- "31709557"
  manifest <- data.frame(activity_id = "31709557", gps_sample_count = 160L)
  testthat::expect_error(
    validate_gps_stage2c_request_registry(request, manifest),
    "non-CALIBRATION"
  )
})

testthat::test_that("irregular sampling and stationary observations stay explicit", {
  source <- episode_fixture()
  source$silver_samples$time_seconds[72:74] <- source$silver_samples$time_seconds[[71L]]
  source$silver_samples$latitude[72:74] <- source$silver_samples$latitude[[71L]]
  source$silver_samples$longitude[72:74] <- source$silver_samples$longitude[[71L]]
  source$silver_samples$distance_metres[72:74] <- source$silver_samples$distance_metres[[71L]]
  for (type in c("time", "distance")) {
    row <- which(source$raw_streams$stream_type == type)
    values <- if (type == "time") source$silver_samples$time_seconds else source$silver_samples$distance_metres
    source$raw_streams$stream_payload[[row]] <- jsonlite::toJSON(as.list(values), auto_unbox = TRUE)
  }
  row <- which(source$raw_streams$stream_type == "latlng")
  source$raw_streams$stream_payload[[row]] <- jsonlite::toJSON(
    Map(c, source$silver_samples$latitude, source$silver_samples$longitude),
    auto_unbox = TRUE, digits = NA
  )
  result <- build_gps_stage2c_result(source, episode_request())
  testthat::expect_true(any(result$descriptive_segments$repeated_coordinate))
  testthat::expect_true(any(result$descriptive_segments$repeated_timestamp))
  testthat::expect_equal(
    sort(unique(result$multi_scale_observation_context$context_window_segments)),
    GPS_STAGE2C_CONTEXT_SCALES
  )
})

testthat::test_that("overlapping review evidence collapses to unique keys", {
  source <- episode_fixture()
  first <- build_gps_stage2c_result(source, episode_request())
  second_request <- episode_request(from = 1L, to = 139L, focus_from = 7L, focus_to = 8L)
  second_request$request_id <- "EPISODE_CASE"
  second_request$request_type <- "COMPLETE_EPISODE"
  second <- build_gps_stage2c_result(source, second_request)
  collapsed <- collapse_gps_stage2c_review(
    list(first = first, second = second), "observation_review_worksheet"
  )
  testthat::expect_equal(
    anyDuplicated(gps_stage2c_evidence_key(collapsed, "OBSERVATION")), 0L
  )
  overlap <- collapsed$sample_index == 70L
  testthat::expect_match(collapsed$request_id[overlap], "EPISODE_CASE;STANDARD_CASE")
})

testthat::test_that("review worksheets reference prior decisions without assigning labels", {
  source <- episode_fixture()
  prior <- data.frame(
    entity_type = "OBSERVATION", activity_id = "48062184", sample_index = 70L,
    from_sample_index = NA_integer_, to_sample_index = NA_integer_,
    confirmed_research_label = "ACCEPTED",
    decision_status = "OWNER_CONFIRMED_CONDITIONAL_RESEARCH_DECISION",
    conditional_acceptance = "TRUE", review_provenance = "CONFIRMED_FIXTURE",
    stringsAsFactors = FALSE
  )
  result <- build_gps_stage2c_result(source, episode_request(), prior)
  row <- result$observation_review_worksheet$sample_index == 70L
  testthat::expect_equal(result$observation_review_worksheet$manual_label[row], "UNREVIEWED")
  testthat::expect_equal(result$observation_review_worksheet$prior_research_label[row], "ACCEPTED")
  testthat::expect_true(result$observation_review_worksheet$prior_conditional_acceptance[row])
})

testthat::test_that("plot rendering produces non-empty episode review images", {
  result <- build_gps_stage2c_result(
    episode_fixture(), episode_request("COMPLETE_EPISODE", 1L, 139L, 7L, 8L)
  )
  plot_directory <- tempfile("gps-stage2c-plots-")
  dir.create(plot_directory)
  track <- file.path(plot_directory, "track.png")
  measurements <- file.path(plot_directory, "measurements.png")
  previous_directory <- setwd(plot_directory)
  on.exit(setwd(previous_directory), add = TRUE)
  device_before <- grDevices::dev.cur()
  render_gps_stage2c_episode_plots(result, track, measurements)
  testthat::expect_gt(file.info(track)$size, 0)
  testthat::expect_gt(file.info(measurements)$size, 0)
  testthat::expect_equal(grDevices::dev.cur(), device_before)
  testthat::expect_false(file.exists(file.path(plot_directory, "Rplots.pdf")))
})

testthat::test_that("plot device closes when episode rendering fails", {
  plot_directory <- tempfile("gps-stage2c-plot-error-")
  dir.create(plot_directory)
  output <- file.path(plot_directory, "failed.png")
  previous_directory <- setwd(plot_directory)
  on.exit(setwd(previous_directory), add = TRUE)
  device_before <- grDevices::dev.cur()
  testthat::expect_error(
    with_gps_stage2c_png(output, 100, 100, 72, function() stop("draw failed")),
    "draw failed"
  )
  testthat::expect_equal(grDevices::dev.cur(), device_before)
  testthat::expect_false(file.exists(file.path(plot_directory, "Rplots.pdf")))
})

testthat::test_that("Stage 2C connection lifecycle disconnects reliably", {
  state <- new.env(parent = emptyenv())
  state$disconnects <- 0L
  connect <- function(database_name) {
    testthat::expect_equal(database_name, "cycling_platform_admin")
    structure(list(valid = TRUE), class = "stage2c_test_connection")
  }
  is_valid <- function(connection) connection$valid
  disconnect <- function(connection) {
    state$disconnects <- state$disconnects + 1L
    TRUE
  }
  result <- with_gps_stage2c_read_connection(
    function(connection) "complete", connect, is_valid, disconnect
  )
  testthat::expect_equal(result, "complete")
  testthat::expect_equal(state$disconnects, 1L)

  testthat::expect_error(
    with_gps_stage2c_read_connection(
      function(connection) stop("extraction failed"), connect, is_valid, disconnect
    ),
    "extraction failed"
  )
  testthat::expect_equal(state$disconnects, 2L)

  testthat::expect_warning(
    testthat::expect_error(
      with_gps_stage2c_read_connection(
        function(connection) stop("primary failure"), connect, is_valid,
        function(connection) stop("cleanup failure")
      ),
      "primary failure"
    ),
    "cleanup failure"
  )
})

testthat::test_that("writer publishes complete hashed outputs and refuses replacement", {
  source <- episode_fixture()
  standard_request <- episode_request()
  episode_request_row <- episode_request(
    "COMPLETE_EPISODE", 1L, 139L, 7L, 8L
  )
  episode_request_row$request_id <- "EPISODE_CASE"
  requests <- rbind(standard_request, episode_request_row)
  results <- list(
    STANDARD_CASE = build_gps_stage2c_result(source, standard_request),
    EPISODE_CASE = build_gps_stage2c_result(source, episode_request_row)
  )
  inputs <- vapply(seq_len(4L), function(index) {
    path <- tempfile(fileext = ".csv")
    writeLines(paste("input", index), path)
    path
  }, character(1))
  output <- tempfile("gps-stage2c-output-")
  written <- write_gps_stage2c_results(
    results, requests, output, inputs, "fixture-revision"
  )
  testthat::expect_equal(nrow(written$extraction_manifest), 2L)
  testthat::expect_true(all(written$extraction_manifest$raw_silver_mismatch_count == 0L))
  testthat::expect_true(all(written$extraction_manifest$automated_qualification_decision_count == 0L))
  testthat::expect_equal(
    anyDuplicated(gps_stage2c_evidence_key(
      written$consolidated_observations, "OBSERVATION"
    )), 0L
  )
  testthat::expect_true(all(file.exists(written$file_manifest$path)))
  testthat::expect_true(all(vapply(seq_len(nrow(written$file_manifest)), function(index) {
    gps_sha256_file(written$file_manifest$path[[index]]) ==
      written$file_manifest$sha256[[index]]
  }, logical(1))))
  testthat::expect_error(
    write_gps_stage2c_results(
      results, requests, output, inputs, "fixture-revision"
    ),
    "Refusing to overwrite"
  )
})

testthat::test_that("Stage 2C runner requires explicit read-only execution", {
  script <- paste(readLines(
    episode_test_path("scripts", "audits", "extract_gps_qualification_stage2c.R"),
    warn = FALSE
  ), collapse = "\n")
  gate <- regexpr("--execute-authorised-read-only", script, fixed = TRUE)[[1L]]
  connection <- regexpr("with_gps_stage2c_read_connection", script, fixed = TRUE)[[1L]]
  preflight <- regexpr("validate_gps_stage2c_destinations", script, fixed = TRUE)[[1L]]
  testthat::expect_gt(gate, 0L)
  testthat::expect_gt(preflight, gate)
  testthat::expect_gt(connection, preflight)
  testthat::expect_match(script, "with_gps_stage2c_read_connection")
  testthat::expect_false(grepl("on.exit\\(", script))
  testthat::expect_false(grepl("INSERT|UPDATE|DELETE|REPLACE|TRUNCATE", script))
})

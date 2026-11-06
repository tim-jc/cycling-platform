evidence_path <- function(...) {
  path <- file.path(...)
  if (!file.exists(path)) path <- file.path("..", "..", path)
  path
}

source(evidence_path("R", "quality", "profile_activity_track_integrity.R"))
source(evidence_path("R", "quality", "fetch_gps_investigation_evidence.R"))
source(evidence_path("R", "quality", "extract_duplicate_timestamp_evidence.R"))

duplicate_timestamp_fixture <- function() {
  time <- c(0:5, rep(6, 4), 7:12)
  latitude <- 51 + seq_along(time) / 1000
  longitude <- -0.2 - seq_along(time) / 1000
  distance <- cumsum(c(0, rep(2, length(time) - 1L)))
  raw <- data.frame(
    activity_id = 31709557,
    stream_type = c("time", "latlng", "distance"),
    original_size = length(time),
    stream_payload = c(
      jsonlite::toJSON(as.list(time), auto_unbox = TRUE),
      jsonlite::toJSON(Map(c, latitude, longitude), auto_unbox = TRUE, digits = NA),
      jsonlite::toJSON(as.list(distance), auto_unbox = TRUE)
    ),
    stringsAsFactors = FALSE
  )
  silver <- data.frame(
    activity_id = 31709557,
    sample_index = seq_along(time),
    time_seconds = time,
    latitude = latitude,
    longitude = longitude,
    distance_metres = distance
  )
  list(raw = raw, silver = silver)
}

testthat::test_that("all timestamp anomalies, runs, and review context are extracted", {
  fixture <- duplicate_timestamp_fixture()
  evidence <- build_duplicate_timestamp_evidence(fixture$raw, fixture$silver, 5L)

  testthat::expect_equal(evidence$summary$equal_interval_count, 3)
  testthat::expect_equal(evidence$summary$decreasing_interval_count, 0)
  testthat::expect_equal(evidence$equal_timestamp_runs$start_sample_index, 7)
  testthat::expect_equal(evidence$equal_timestamp_runs$end_sample_index, 10)
  testthat::expect_equal(evidence$equal_timestamp_runs$observation_count, 4)
  testthat::expect_equal(evidence$reference_window$sample_index, 2:15)
  testthat::expect_equal(sum(evidence$reference_window$selected_duplicate_run), 4)
  testthat::expect_equal(evidence$summary$reference_window_status, "READY")
})

testthat::test_that("MariaDB 64-bit activity IDs expand across metadata rows", {
  testthat::skip_if_not_installed("bit64")
  fixture <- duplicate_timestamp_fixture()
  fixture$raw$activity_id <- bit64::as.integer64(fixture$raw$activity_id)
  fixture$silver$activity_id <- bit64::as.integer64(fixture$silver$activity_id)

  evidence <- build_duplicate_timestamp_evidence(fixture$raw, fixture$silver, 5L)

  testthat::expect_equal(nrow(evidence$raw_stream_metadata), 3L)
  testthat::expect_equal(
    as.character(evidence$raw_stream_metadata$activity_id),
    rep("31709557", 3L)
  )
})

testthat::test_that("decreasing timestamps and positional mismatches remain visible", {
  fixture <- duplicate_timestamp_fixture()
  fixture$raw$stream_payload[fixture$raw$stream_type == "time"] <-
    jsonlite::toJSON(as.list(c(0:5, rep(6, 4), 5, 8:12)), auto_unbox = TRUE)
  fixture$silver$latitude[[8L]] <- fixture$silver$latitude[[8L]] + 0.01
  evidence <- build_duplicate_timestamp_evidence(fixture$raw, fixture$silver, 5L)

  testthat::expect_equal(evidence$summary$decreasing_interval_count, 1)
  testthat::expect_true(evidence$positional_comparison$any_mismatch[[8L]])
  testthat::expect_equal(sum(!evidence$positional_comparison$latitude_matches), 1)
  testthat::expect_gt(evidence$summary$positional_mismatch_count, 1)
})

testthat::test_that("missing Raw values are preserved and compared positionally", {
  fixture <- duplicate_timestamp_fixture()
  distance_values <- cumsum(c(0, rep(2, 14)))
  # Encode an explicit JSON null without allowing R list deletion to change positions.
  fixture$raw$stream_payload[fixture$raw$stream_type == "distance"] <-
    paste0(
      "[", paste(c(distance_values[1:7], "null", distance_values[9:15]), collapse = ","), "]"
    )
  fixture$silver$distance_metres[[8L]] <- NA_real_
  evidence <- build_duplicate_timestamp_evidence(fixture$raw, fixture$silver, 5L)

  testthat::expect_true(is.na(evidence$positional_comparison$raw_distance_metres[[8L]]))
  testthat::expect_true(evidence$positional_comparison$distance_matches[[8L]])
})

testthat::test_that("evidence writer refuses repository paths and overwrites", {
  fixture <- duplicate_timestamp_fixture()
  evidence <- build_duplicate_timestamp_evidence(fixture$raw, fixture$silver, 5L)
  repository <- normalizePath(".")
  testthat::expect_error(
    write_duplicate_timestamp_evidence(evidence, file.path(repository, "tmp-evidence"), repository),
    "outside the repository"
  )

  output <- tempfile("gps-evidence-")
  write_duplicate_timestamp_evidence(evidence, output, repository)
  testthat::expect_true(all(file.exists(file.path(output, c(
    "extraction_summary.csv", "raw_stream_metadata.csv", "raw_silver_positional_comparison.csv",
    "non_increasing_timestamp_intervals.csv", "equal_timestamp_runs.csv", "reference_window.csv"
  )))))
  testthat::expect_error(write_duplicate_timestamp_evidence(evidence, output, repository), "Refusing to overwrite")
})

testthat::test_that("generic runner accepts an activity argument and remains read-only", {
  script <- paste(readLines(
    evidence_path("scripts", "audits", "extract_gps_duplicate_timestamps.R"), warn = FALSE
  ), collapse = "\n")
  testthat::expect_match(script, "validate_gps_investigation_activity_id", fixed = TRUE)
  testthat::expect_false(grepl("activity_id <- 31709557", script, fixed = TRUE))
  testthat::expect_false(grepl("INSERT|UPDATE|DELETE|REPLACE|TRUNCATE", script))
})

testthat::test_that("activity validation and shared Raw/Silver fetch are parameterised", {
  testthat::expect_identical(validate_gps_investigation_activity_id("31709557"), "31709557")
  testthat::expect_error(validate_gps_investigation_activity_id("31x"), "digits only")
  calls <- list()
  query <- function(connection, statement, params) {
    calls[[length(calls) + 1L]] <<- list(statement = statement, params = params)
    if (grepl("cycling_platform_raw", statement, fixed = TRUE)) {
      duplicate_timestamp_fixture()$raw
    } else {
      duplicate_timestamp_fixture()$silver
    }
  }
  result <- fetch_gps_raw_silver_evidence(NULL, "31709557", get_query = query)

  testthat::expect_equal(length(calls), 2L)
  testthat::expect_true(all(vapply(calls, \(call) identical(call$params, list("31709557")), logical(1))))
  testthat::expect_match(calls[[1L]]$statement, "cycling_platform_raw.activity_streams", fixed = TRUE)
  testthat::expect_match(calls[[2L]]$statement, "ORDER BY sample_index", fixed = TRUE)
  testthat::expect_equal(result$raw_streams, duplicate_timestamp_fixture()$raw)
})

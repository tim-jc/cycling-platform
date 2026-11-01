calibration_path <- function(...) {
  path <- file.path(...)
  if (!file.exists(path)) path <- file.path("..", "..", path)
  path
}

source(calibration_path("R", "quality", "profile_activity_track_integrity.R"))
source(calibration_path("R", "quality", "calibrate_activity_track_integrity.R"))

calibration_candidates_fixture <- function(n = 90L) {
  references <- track_calibration_references()$activity_id
  ids <- c(references, as.character(9000000000 + seq_len(max(0L, n - length(references)))))
  sequence <- seq_along(ids)
  data.frame(
    activity_id = ids,
    activity_name = paste("Outdoor activity", sequence),
    sport_type = rep(c("Ride", "Run", "Hike", "Walk", "Kayaking"), length.out = n),
    is_manual = 0L,
    start_datetime_utc = as.POSIXct("2017-01-01", tz = "UTC") + sequence * 86400,
    start_datetime_local = as.POSIXct("2017-01-01", tz = "UTC") + sequence * 86400,
    start_date_local = as.Date("2017-01-01") + sequence,
    distance_metres = (((sequence - 1L) * 31L) %% n + 1L) * 1000,
    moving_time_seconds = 1200 + sequence,
    elapsed_time_seconds = 1500 + sequence * 2,
    gps_sample_count = 100L + sequence * 10L,
    time_sample_count = 100L + sequence * 10L,
    distance_sample_count = 100L + sequence * 10L,
    gps_retrieved_at = as.POSIXct("2026-01-01", tz = "UTC"),
    source_trainer = "false",
    provenance_text = paste("outdoor activity", sequence),
    deterministic_rank = sprintf("%064d", rev(sequence)),
    stringsAsFactors = FALSE
  )
}

calibration_samples_fixture <- function(activity_id, n = 4L) {
  data.frame(
    activity_id = rep(as.character(activity_id), n), sample_index = seq_len(n),
    latitude = 53 + seq_len(n) / 1000, longitude = rep(-2, n),
    time_seconds = seq(0, by = 2, length.out = n),
    distance_metres = seq(0, by = 100, length.out = n),
    stringsAsFactors = FALSE
  )
}

calibration_manifest_samples_fixture <- function(activity_id) {
  references <- track_calibration_reference_segments()
  required <- references$to_sample_index[references$activity_id == activity_id]
  calibration_samples_fixture(activity_id, if (length(required)) max(required) else 4L)
}

testthat::test_that("candidate SQL uses indexed Raw metadata and a fixed cutoff", {
  sql <- track_calibration_candidate_sql()
  testthat::expect_match(sql, "latlng.original_size AS gps_sample_count", fixed = TRUE)
  testthat::expect_match(sql, "latlng.stream_type = 'latlng'", fixed = TRUE)
  testthat::expect_match(sql, "a.start_datetime_utc <= ?", fixed = TRUE)
  testthat::expect_false(grepl("stream_payload", sql, fixed = TRUE))
})

testthat::test_that("eligibility conservatively excludes non-genuine provenance", {
  candidates <- calibration_candidates_fixture(8)
  candidates$is_manual[1] <- 1
  candidates$sport_type[2] <- "VirtualRide"
  candidates$source_trainer[3] <- "true"
  candidates$provenance_text[4] <- "Zwift synthetic route"
  candidates$sport_type[5] <- NA
  candidates$gps_sample_count[6] <- 0
  classified <- classify_track_calibration_eligibility(candidates)

  testthat::expect_identical(classified$eligibility_status[1:6], c(
    "INELIGIBLE_MANUAL", "INELIGIBLE_VIRTUAL_SPORT", "INELIGIBLE_SOURCE_TRAINER",
    "INELIGIBLE_SYNTHETIC_CONTEXT", "UNKNOWN_PROVENANCE", "INELIGIBLE_NO_GPS"
  ))
  testthat::expect_true(all(classified$eligibility_status[7:8] == "ELIGIBLE"))
})

testthat::test_that("selection is deterministic, unique, fixed-size and reference-preserving", {
  candidates <- calibration_candidates_fixture()
  first <- select_track_calibration_manifest(candidates, selected_at_utc = "2026-10-29 12:00:00")
  second <- select_track_calibration_manifest(candidates, selected_at_utc = "2026-10-29 12:00:00")

  testthat::expect_equal(nrow(first), 45L)
  testthat::expect_equal(length(unique(first$activity_id)), 45L)
  testthat::expect_identical(first$activity_id, second$activity_id)
  testthat::expect_true(all(track_calibration_references()$activity_id %in% first$activity_id))
  testthat::expect_equal(sum(first$cohort == "B_CHRONOLOGY_DISTANCE"), 30L)
  testthat::expect_true(all(first$cutoff_utc == TRACK_CALIBRATION_CUTOFF_UTC))
})

testthat::test_that("short eligible populations are explicit and retain references", {
  manifest <- select_track_calibration_manifest(calibration_candidates_fixture(20))
  testthat::expect_equal(nrow(manifest), 20L)
  testthat::expect_true(all(manifest$eligible_population_count == 20L))
  testthat::expect_silent(validate_track_calibration_manifest(manifest))
})

testthat::test_that("ineligible reference activity stops manifest generation", {
  candidates <- calibration_candidates_fixture()
  candidates$is_manual[candidates$activity_id == "20445541114"] <- 1L
  testthat::expect_error(
    select_track_calibration_manifest(candidates),
    "Reference activities are missing or ineligible"
  )
})

testthat::test_that("authoritative manifest is not silently overwritten", {
  manifest <- select_track_calibration_manifest(calibration_candidates_fixture(10))
  path <- tempfile(fileext = ".csv")
  write_track_calibration_manifest(manifest, path)
  testthat::expect_error(write_track_calibration_manifest(manifest, path), "Refusing to overwrite")
  read_back <- read_track_calibration_manifest(path)
  testthat::expect_identical(read_back$activity_id, manifest$activity_id)
})

testthat::test_that("single-activity retrieval uses the Silver primary-key path", {
  observed <- NULL
  fake_query <- function(connection, statement, params) {
    observed <<- list(statement = statement, params = params)
    calibration_samples_fixture(params[[1]])
  }
  rows <- fetch_one_activity_track_samples(NULL, "12345", get_query = fake_query)
  testthat::expect_equal(nrow(rows), 4L)
  testthat::expect_match(observed$statement, "WHERE activity_id = ? ORDER BY sample_index", fixed = TRUE)
  testthat::expect_identical(observed$params, list("12345"))
})

testthat::test_that("population profiling reads and releases one activity at a time", {
  manifest <- select_track_calibration_manifest(calibration_candidates_fixture(6))
  active <- 0L
  maximum_active <- 0L
  requested <- character()
  fetch <- function(connection, activity_id) {
    active <<- active + 1L
    maximum_active <<- max(maximum_active, active)
    requested <<- c(requested, activity_id)
    rows <- calibration_manifest_samples_fixture(activity_id)
    active <<- active - 1L
    rows
  }
  result <- run_track_calibration(NULL, manifest, get_samples = fetch)

  testthat::expect_true(result$complete)
  testthat::expect_identical(requested, manifest$activity_id)
  testthat::expect_equal(maximum_active, 1L)
  testthat::expect_equal(nrow(result$segment_distribution_summary), nrow(manifest) * 7L)
  testthat::expect_true(all(result$activity_summary$processing_status == "SUCCESS"))
  testthat::expect_equal(
    result$total_sample_rows_processed,
    sum(vapply(manifest$activity_id, function(id) nrow(calibration_manifest_samples_fixture(id)), integer(1)))
  )
})

testthat::test_that("cohort shortages use a deterministic final fill", {
  candidates <- calibration_candidates_fixture()
  candidates$distance_metres <- seq_len(nrow(candidates)) * 1000
  manifest <- select_track_calibration_manifest(candidates)
  testthat::expect_equal(nrow(manifest), 45L)
  testthat::expect_equal(length(unique(manifest$activity_id)), 45L)
  testthat::expect_true(any(manifest$cohort == "F_DETERMINISTIC_FILL"))
})

testthat::test_that("failed activities make output explicitly incomplete", {
  manifest <- select_track_calibration_manifest(calibration_candidates_fixture(6))
  failed_id <- manifest$activity_id[[4]]
  fetch <- function(connection, activity_id) {
    if (activity_id == failed_id) stop("fixture query failed")
    calibration_manifest_samples_fixture(activity_id)
  }
  result <- run_track_calibration(NULL, manifest, get_samples = fetch)
  testthat::expect_false(result$complete)
  testthat::expect_identical(result$failed_activity_ids, failed_id)
  failed <- result$activity_summary[result$activity_summary$activity_id == failed_id, ]
  testthat::expect_identical(failed$processing_status, "FAILED")
  testthat::expect_match(failed$error_message, "fixture query failed")
})

testthat::test_that("distribution rows contain governed percentile columns", {
  result <- profile_activity_track_integrity(
    calibration_samples_fixture("123"), include_segments = TRUE
  )
  distributions <- track_calibration_distributions(result, 3L)
  testthat::expect_identical(names(distributions), c(
    "activity_id", "metric", "valid_count", "missing_count", "minimum", "mean",
    "p50", "p90", "p95", "p99", "maximum"
  ))
  testthat::expect_equal(nrow(distributions), 7L)
  elapsed <- distributions[distributions$metric == "elapsed_time_interval_seconds", ]
  testthat::expect_equal(elapsed$p90, 2)
  testthat::expect_equal(elapsed$missing_count, 0L)
})

testthat::test_that("exploratory diagnostic categories add no universal threshold", {
  samples <- calibration_samples_fixture("123", 6)
  samples$distance_metres <- c(0, 0, 10, 20, 30, 40)
  result <- profile_activity_track_integrity(samples, include_segments = TRUE)
  diagnostics <- calibration_extra_diagnostics(result, limit = 3L)
  testthat::expect_true("ZERO_DEVICE_INCREMENT_WITH_GEOGRAPHIC_MOVEMENT" %in%
    diagnostics$diagnostic_type)
  testthat::expect_true("GPS_DEVICE_DISAGREEMENT_WITHIN_ACTIVITY_P95_SPEED" %in%
    diagnostics$diagnostic_type)
})

testthat::test_that("all known reference segment identities are preserved", {
  reference <- track_calibration_reference_segments()[1, ]
  samples <- calibration_samples_fixture(reference$activity_id, 7252L)
  result <- profile_activity_track_integrity(samples, include_segments = TRUE)
  diagnostics <- calibration_reference_diagnostics(result)
  testthat::expect_true(any(
    diagnostics$from_sample_index == 7251L & diagnostics$to_sample_index == 7252L
  ))

  missing <- profile_activity_track_integrity(
    calibration_samples_fixture("2705450947", 4), include_segments = TRUE
  )
  missing_diagnostic <- calibration_reference_diagnostics(missing)
  testthat::expect_identical(missing_diagnostic$diagnostic_type, "REFERENCE_SEGMENT_MISSING")
  testthat::expect_equal(missing_diagnostic$from_sample_index, 7639L)
})

testthat::test_that("report-wide diagnostic bounds retain reference evidence", {
  diagnostics <- do.call(rbind, lapply(1:40, function(i) {
    row <- empty_track_diagnostics()[rep(NA_integer_, 1), , drop = FALSE]
    row$diagnostic_type <- "LARGEST_TIME_GAP"
    row$activity_id <- as.character(i)
    row$from_sample_index <- i
    row$is_reference_segment <- i == 40
    row$reference_segment <- if (i == 40) "KNOWN" else NA_character_
    row
  }))
  bounded <- bound_track_calibration_diagnostics(diagnostics, per_category_limit = 30L)
  testthat::expect_equal(nrow(bounded), 30L)
  testthat::expect_true(any(bounded$is_reference_segment))
})

testthat::test_that("the pure profiler only returns segments when requested", {
  default <- profile_activity_track_integrity(calibration_samples_fixture("123"))
  calibration <- profile_activity_track_integrity(
    calibration_samples_fixture("123"), include_segments = TRUE
  )
  testthat::expect_false("segments" %in% names(default))
  testthat::expect_equal(nrow(calibration$segments), 3L)
})

testthat::test_that("writer produces exactly the four governed local CSVs", {
  manifest <- select_track_calibration_manifest(calibration_candidates_fixture(6))
  fetch <- function(connection, activity_id) calibration_manifest_samples_fixture(activity_id)
  result <- run_track_calibration(NULL, manifest, get_samples = fetch)
  directory <- tempfile("gps-calibration-output-")
  write_track_calibration_outputs(result, manifest, directory)
  testthat::expect_setequal(list.files(directory), c(
    "gps_track_calibration_v1_manifest.csv", "activity_summary.csv",
    "segment_distribution_summary.csv", "diagnostic_segments.csv"
  ))
})

testthat::test_that("calibration scripts remain read-only", {
  scripts <- c(
    calibration_path("scripts", "audits", "generate_gps_track_calibration_manifest.R"),
    calibration_path("scripts", "audits", "run_gps_track_calibration.R")
  )
  text <- paste(unlist(lapply(scripts, readLines, warn = FALSE)), collapse = "\n")
  testthat::expect_false(grepl("dbExecute|dbWriteTable|INSERT|UPDATE|DELETE", text))
})

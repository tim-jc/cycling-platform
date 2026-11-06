extreme_evidence_path <- function(...) {
  path <- file.path(...)
  if (!file.exists(path)) path <- file.path("..", "..", path)
  path
}

source(extreme_evidence_path("R", "quality", "profile_activity_track_integrity.R"))
source(extreme_evidence_path("R", "quality", "extract_duplicate_timestamp_evidence.R"))
source(extreme_evidence_path("R", "quality", "extract_gps_extreme_segment_evidence.R"))

gps_extreme_fixture <- function() {
  count <- 20L
  time <- seq.int(0, count - 1L)
  latitude <- rep(51, count)
  longitude <- seq(0, by = 0.00001, length.out = count)
  distance <- seq(0, by = 1, length.out = count)
  # Largest displacement at 6 -> 7, with enough context on both sides.
  longitude[[7L]] <- longitude[[6L]] + 0.01
  time[7:count] <- time[7:count] + 131L
  # Return gradually, then make the highest one-second speed at 13 -> 14.
  longitude[8:13] <- seq(longitude[[7L]] - 0.001, 0.00012, length.out = 6)
  longitude[[14L]] <- longitude[[13L]] + 0.005

  raw <- data.frame(
    activity_id = 15562928333,
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
    activity_id = 15562928333,
    sample_index = seq_len(count),
    time_seconds = time,
    latitude = vapply(parsed_latlng, \(value) as.numeric(value[[1L]]), numeric(1)),
    longitude = vapply(parsed_latlng, \(value) as.numeric(value[[2L]]), numeric(1)),
    distance_metres = distance
  )
  list(raw = raw, silver = silver)
}

testthat::test_that("governed extrema locate exact segments without approximate matching", {
  fixture <- gps_extreme_fixture()
  result <- build_gps_extreme_segment_evidence(fixture$raw, fixture$silver, 2L)

  testthat::expect_equal(result$anomaly_candidates$case_key, c(
    "READING_LARGEST_DISPLACEMENT", "KINGSTON_HIGHEST_IMPLIED_SPEED"
  ))
  testthat::expect_equal(result$anomaly_candidates$selection_rule, c(
    "MAX_GEOGRAPHIC_DISPLACEMENT", "MAX_IMPLIED_GEOGRAPHIC_SPEED"
  ))
  testthat::expect_true(all(result$extraction_status$extraction_status == "SUCCESS"))
  testthat::expect_equal(result$extraction_summary$raw_silver_mismatch_count, 0)
  testthat::expect_true(all(result$candidate_window_observations$sample_index >= 4L))
  testthat::expect_true(all(result$candidate_window_observations$sample_index <= 16L))
})

testthat::test_that("missing positions remain missing and are never interpolated", {
  fixture <- gps_extreme_fixture()
  latlng <- jsonlite::fromJSON(
    fixture$raw$stream_payload[fixture$raw$stream_type == "latlng"],
    simplifyVector = FALSE
  )
  latlng[[5L]] <- list(NULL, NULL)
  fixture$raw$stream_payload[fixture$raw$stream_type == "latlng"] <-
    jsonlite::toJSON(latlng, auto_unbox = TRUE, null = "null", digits = NA)
  fixture$silver$latitude[[5L]] <- NA_real_
  fixture$silver$longitude[[5L]] <- NA_real_

  result <- build_gps_extreme_segment_evidence(fixture$raw, fixture$silver, 2L)
  row <- result$candidate_window_observations$sample_index == 5L &
    result$candidate_window_observations$case_key == "READING_LARGEST_DISPLACEMENT"
  testthat::expect_true(is.na(result$candidate_window_observations$raw_latitude[row]))
  testthat::expect_true(is.na(result$candidate_window_observations$silver_latitude[row]))
  testthat::expect_true(result$candidate_window_observations$latitude_matches[row])
})

testthat::test_that("runner is fixed to one activity and uses read-only source tables", {
  script <- paste(readLines(
    extreme_evidence_path("scripts", "audits", "extract_activity_15562928333_gps_anomalies.R"),
    warn = FALSE
  ), collapse = "\n")
  testthat::expect_match(script, "activity_id <- 15562928333", fixed = TRUE)
  testthat::expect_match(script, "cycling_platform_raw.activity_streams", fixed = TRUE)
  testthat::expect_match(script, "cycling_platform_silver.activity_streams", fixed = TRUE)
  testthat::expect_false(grepl("INSERT|UPDATE|DELETE|REPLACE|TRUNCATE", script))
})

testthat::test_that("writer refuses repository outputs and existing evidence", {
  fixture <- gps_extreme_fixture()
  result <- build_gps_extreme_segment_evidence(fixture$raw, fixture$silver, 2L)
  repository <- normalizePath(".")
  testthat::expect_error(
    write_gps_extreme_segment_evidence(result, file.path(repository, "tmp-extreme-evidence"), repository),
    "outside the repository"
  )
  output <- tempfile("gps-extreme-evidence-")
  write_gps_extreme_segment_evidence(result, output, repository)
  testthat::expect_equal(length(list.files(output)), 6L)
  testthat::expect_error(
    write_gps_extreme_segment_evidence(result, output, repository),
    "Refusing to overwrite"
  )
})

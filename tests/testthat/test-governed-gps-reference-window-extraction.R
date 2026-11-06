governed_window_path <- function(...) {
  path <- file.path(...)
  if (!file.exists(path)) path <- file.path("..", "..", path)
  path
}

source(governed_window_path("R", "quality", "profile_activity_track_integrity.R"))
source(governed_window_path("R", "quality", "profile_geographic_calibration_evidence.R"))
source(governed_window_path("R", "quality", "extract_duplicate_timestamp_evidence.R"))
source(governed_window_path("R", "quality", "extract_governed_gps_reference_window.R"))

governed_window_fixture <- function() {
  count <- 40L
  time <- seq.int(0L, count - 1L)
  latitude <- 51 + seq_len(count) / 100000
  longitude <- -0.3 - seq_len(count) / 100000
  distance <- seq(0, by = 5, length.out = count)
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

build_governed_window_fixture <- function(fixture = governed_window_fixture()) {
  build_governed_gps_reference_window(
    raw_streams = fixture$raw,
    silver_samples = fixture$silver,
    window_from_sample_index = 6L,
    window_to_sample_index = 35L,
    focus_from_sample_index = 11L,
    focus_to_sample_index = 30L,
    focus_segment_from_sample_index = 29L,
    focus_segment_to_sample_index = 30L,
    case_key = "KINGSTON_TUNNEL_GPS_DRIFT",
    evidence_note = "synthetic fixture"
  )
}

testthat::test_that("governed reference window contains contiguous source-faithful evidence", {
  result <- build_governed_window_fixture()

  testthat::expect_equal(result$reference_window_observations$sample_index, 6:35)
  testthat::expect_equal(result$reference_window_segments$from_sample_index, 6:34)
  testthat::expect_equal(result$reference_window_segments$to_sample_index, 7:35)
  testthat::expect_equal(nrow(result$reference_window_observations), 30L)
  testthat::expect_equal(nrow(result$reference_window_segments), 29L)
  testthat::expect_equal(nrow(result$raw_silver_positional_comparison), 30L)
  testthat::expect_false(any(result$raw_silver_positional_comparison$any_mismatch))
  testthat::expect_equal(sum(result$reference_window_observations$is_focus_observation), 20L)
  testthat::expect_equal(sum(result$reference_window_segments$is_focus_segment), 1L)
})

testthat::test_that("manual template is unique and entirely unreviewed", {
  result <- build_governed_window_fixture()
  labels <- result$manual_label_template
  keys <- ifelse(
    labels$entity_type == "OBSERVATION",
    paste(labels$entity_type, labels$activity_id, labels$sample_index, sep = "|"),
    paste(
      labels$entity_type, labels$activity_id,
      labels$from_sample_index, labels$to_sample_index,
      sep = "|"
    )
  )

  testthat::expect_equal(nrow(labels), 59L)
  testthat::expect_equal(anyDuplicated(keys), 0L)
  testthat::expect_true(all(labels$manual_label == "UNREVIEWED"))
  testthat::expect_true(any(keys == "OBSERVATION|15562928333|11"))
  testthat::expect_true(any(keys == "SEGMENT|15562928333|29|30"))
})

testthat::test_that("Raw/Silver disagreement prevents publication", {
  fixture <- governed_window_fixture()
  fixture$silver$longitude[[20L]] <- fixture$silver$longitude[[20L]] + 0.01
  testthat::expect_error(
    build_governed_window_fixture(fixture),
    "Raw/Silver positional mismatch.*20"
  )
})

testthat::test_that("missing sample indexes prevent publication", {
  fixture <- governed_window_fixture()
  fixture$silver <- fixture$silver[fixture$silver$sample_index != 20L, , drop = FALSE]
  testthat::expect_error(
    build_governed_window_fixture(fixture),
    "missing or out of order"
  )
})

testthat::test_that("writer refuses repository paths and existing output files", {
  result <- build_governed_window_fixture()
  repository <- normalizePath(".")
  testthat::expect_error(
    write_governed_gps_reference_window(result, file.path(repository, "tmp-governed-window"), repository),
    "outside the repository"
  )
  output <- tempfile("governed-window-")
  write_governed_gps_reference_window(result, output, repository)
  testthat::expect_equal(length(list.files(output)), 7L)
  testthat::expect_error(
    write_governed_gps_reference_window(result, output, repository),
    "Refusing to overwrite"
  )
})

testthat::test_that("Kingston runner is fixed, read-only, and requests exact governed ranges", {
  script <- paste(readLines(
    governed_window_path(
      "scripts", "audits", "extract_activity_15562928333_kingston_reference_window.R"
    ),
    warn = FALSE
  ), collapse = "\n")

  testthat::expect_match(script, "activity_id <- 15562928333", fixed = TRUE)
  testthat::expect_match(script, "window_from_sample_index = 1448L", fixed = TRUE)
  testthat::expect_match(script, "window_to_sample_index = 1477L", fixed = TRUE)
  testthat::expect_match(script, "focus_from_sample_index = 1453L", fixed = TRUE)
  testthat::expect_match(script, "focus_to_sample_index = 1472L", fixed = TRUE)
  testthat::expect_match(script, "cycling_platform_raw.activity_streams", fixed = TRUE)
  testthat::expect_match(script, "cycling_platform_silver.activity_streams", fixed = TRUE)
  testthat::expect_false(grepl("INSERT|UPDATE|DELETE|REPLACE|TRUNCATE", script))
})

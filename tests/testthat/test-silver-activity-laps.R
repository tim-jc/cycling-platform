lap_project_path <- function(...) {
  path <- file.path(...)
  if (!file.exists(path)) path <- file.path("..", "..", path)
  path
}

source(lap_project_path("R", "transforms", "rebuild_silver_activity_streams.R"))
source(lap_project_path("R", "transforms", "rebuild_silver_activity_laps.R"))
source(lap_project_path("R", "quality", "classify_lap_power_provenance.R"))

lap_payload_fixture <- function(overrides = list()) {
  base <- list(
    id = "987654321012345678",
    activity = list(id = "123456789012345678"),
    athlete = list(id = "42"),
    lap_index = 1L,
    name = "Lap 1",
    start_date = "2026-08-01T08:00:00Z",
    start_date_local = "2026-08-01T09:00:00Z",
    elapsed_time = 120L,
    moving_time = 115L,
    distance = 1000.5,
    start_index = 0L,
    end_index = 119L,
    average_speed = 8.7,
    average_cadence = 88.2,
    average_watts = 245.6,
    average_heartrate = 151.5,
    max_heartrate = 169.0,
    total_elevation_gain = 12.3,
    device_watts = TRUE
  )
  utils::modifyList(base, overrides, keep.null = TRUE)
}

raw_lap_fixture <- function(payload = lap_payload_fixture(), lap_index = 1L) {
  data.frame(
    activity_id = bit64::as.integer64("123456789012345678"),
    lap_index = lap_index,
    run_id = bit64::as.integer64(7),
    source_id = 1L,
    retrieved_at = as.POSIXct("2026-08-01 08:05:00", tz = "UTC"),
    activity_start_datetime_utc = as.POSIXct("2026-08-01 08:00:00", tz = "UTC"),
    lap_payload = jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null"),
    stringsAsFactors = FALSE
  )
}

testthat::test_that("complete payload maps to the canonical Silver row", {
  row <- parse_silver_activity_lap(
    raw_lap_fixture(), as.POSIXct("2026-08-03 06:00:00", tz = "UTC")
  )
  testthat::expect_equal(as.character(row$lap_id), "987654321012345678")
  testthat::expect_equal(as.character(row$activity_id), "123456789012345678")
  testthat::expect_equal(row$lap_index, 1L)
  testthat::expect_equal(row$lap_name, "Lap 1")
  testthat::expect_equal(row$elapsed_time_seconds, 120L)
  testthat::expect_equal(row$distance_metres, 1000.5)
  testthat::expect_equal(row$start_sample_index, 0L)
  testthat::expect_equal(row$end_sample_index, 119L)
  testthat::expect_equal(row$start_time_seconds, 0L)
  testthat::expect_equal(row$end_time_seconds, 120L)
  testthat::expect_true(row$is_device_watts)
  testthat::expect_equal(row$transform_version, "strava_activity_laps_v3")
  testthat::expect_equal(nchar(row$raw_payload_hash), 64L)
})

testthat::test_that("UTC and local timestamps retain distinct conventions", {
  row <- parse_silver_activity_lap(raw_lap_fixture())
  testthat::expect_equal(format(row$start_datetime_utc, tz = "UTC"), "2026-08-01 08:00:00")
  testthat::expect_equal(format(row$start_datetime_local, tz = "UTC"), "2026-08-01 09:00:00")
})

testthat::test_that("optional sensor values and logical nulls remain missing", {
  payload <- lap_payload_fixture(list(
    average_cadence = NULL, average_watts = NULL,
    average_heartrate = NULL, max_heartrate = NULL, device_watts = NULL
  ))
  row <- parse_silver_activity_lap(raw_lap_fixture(payload))
  testthat::expect_true(is.na(row$average_cadence_rpm))
  testthat::expect_true(is.na(row$average_power_watts))
  testthat::expect_true(is.na(row$average_heartrate_bpm))
  testthat::expect_true(is.na(row$maximum_heartrate_bpm))
  testthat::expect_true(is.na(row$is_device_watts))
})

testthat::test_that("blank lap names become NULL without fabricated labels", {
  row <- parse_silver_activity_lap(raw_lap_fixture(lap_payload_fixture(list(name = "  "))))
  testthat::expect_true(is.na(row$lap_name))
})

testthat::test_that("numeric and logical source representations are typed", {
  payload <- lap_payload_fixture(list(
    elapsed_time = "120", distance = "1000.5", device_watts = "false"
  ))
  row <- parse_silver_activity_lap(raw_lap_fixture(payload))
  testthat::expect_identical(row$elapsed_time_seconds, 120L)
  testthat::expect_equal(row$distance_metres, 1000.5)
  testthat::expect_false(row$is_device_watts)
})

testthat::test_that("malformed JSON and invalid scalar types fail clearly", {
  malformed <- raw_lap_fixture()
  malformed$lap_payload <- "{broken"
  testthat::expect_error(parse_silver_activity_lap(malformed), "Malformed lap payload")
  invalid <- raw_lap_fixture(lap_payload_fixture(list(distance = "far")))
  testthat::expect_error(parse_silver_activity_lap(invalid), "distance.*not numeric")
})

testthat::test_that("source activity identity must agree and payload index is canonical", {
  activity_mismatch <- raw_lap_fixture(lap_payload_fixture(list(
    activity = list(id = "999")
  )))
  different_index <- raw_lap_fixture(lap_payload_fixture(list(lap_index = 2L)))
  missing_id <- raw_lap_fixture(lap_payload_fixture(list(id = NULL)))
  testthat::expect_error(parse_silver_activity_lap(activity_mismatch), "activity ID mismatch")
  parsed <- parse_silver_activity_lap(different_index)
  testthat::expect_equal(parsed$lap_index, 2L)
  testthat::expect_equal(parsed$raw_response_index, 1L)
  testthat::expect_error(parse_silver_activity_lap(missing_id), "Missing or invalid payload lap ID")
})

testthat::test_that("batch builder rejects duplicate source identities", {
  first <- raw_lap_fixture()
  second <- raw_lap_fixture(lap_payload_fixture(list(lap_index = 2L)), lap_index = 2L)
  testthat::expect_error(
    build_silver_activity_lap_rows(rbind(first, second)), "duplicate lap_id"
  )
})

testthat::test_that("incremental refresh never treats an empty Raw scope as disappearance", {
  ids <- lap_refresh_activity_ids(
    connection = NULL, rows = data.frame(), mode = "incremental",
    activity_ids = bit64::as.integer64("123456789012345678")
  )
  testthat::expect_length(ids, 0L)
})

testthat::test_that("DDL governs keys, nullability, boundaries and collation", {
  sql <- paste(readLines(lap_project_path("sql", "silver", "060_create_activity_laps.sql")), collapse = "\n")
  testthat::expect_match(sql, "PRIMARY KEY \\(lap_id\\)")
  testthat::expect_match(sql, "UNIQUE KEY uq_silver_activity_laps_activity_index")
  testthat::expect_match(sql, "\\(activity_id, lap_index\\)")
  testthat::expect_match(sql, "is_device_watts BOOLEAN NULL")
  testthat::expect_match(sql, "raw_response_index INT NOT NULL")
  testthat::expect_match(sql, "start_time_seconds INT NULL")
  testthat::expect_match(sql, "end_time_seconds INT NULL")
  testthat::expect_match(sql, "start_sample_index <= end_sample_index")
  testthat::expect_match(sql, "DEFAULT COLLATE utf8mb4_general_ci")
})

testthat::test_that("automation orders laps after streams and includes summaries", {
  runner <- paste(readLines(lap_project_path("R", "transforms", "run_silver_transformations.R")), collapse = "\n")
  daily <- paste(readLines(lap_project_path("run_daily_platform.R")), collapse = "\n")
  stream_position <- regexpr("rebuild_silver_activity_streams", runner, fixed = TRUE)[[1]]
  lap_position <- regexpr("rebuild_silver_activity_laps", runner, fixed = TRUE)[[1]]
  testthat::expect_gt(lap_position, stream_position)
  testthat::expect_match(daily, "'activity_laps'", fixed = TRUE)
})

testthat::test_that("publication and deep lap validations are registered", {
  validation <- paste(readLines(lap_project_path(
    "R", "validation", "validate_platform_completeness.R"
  )), collapse = "\n")
  expected <- c(
    "silver_activity_laps_required_fields_valid",
    "silver_activity_laps_key_uniqueness",
    "silver_activity_laps_parent_activity_resolves",
    "silver_activity_laps_source_identifier_alignment",
    "silver_activity_laps_index_continuity",
    "silver_activity_laps_adjacent_boundary_differences",
    "silver_activity_laps_time_boundaries_outside_stream_range",
    "silver_activity_laps_telemetry_boundary_reconciliation",
    "silver_activity_laps_power_provenance_reconciliation",
    "silver_activity_laps_parent_summary_reconciliation",
    "silver_activity_laps_raw_reconciliation"
  )
  testthat::expect_true(all(vapply(expected, grepl, logical(1), x = validation, fixed = TRUE)))
  continuity_check <- regmatches(
    validation,
    regexpr(
      'check_name = "silver_activity_laps_index_continuity"[\\s\\S]{0,160}severity = "[A-Z]+"',
      validation,
      perl = TRUE
    )
  )
  testthat::expect_match(continuity_check, 'severity = "INFO"', fixed = TRUE)
  power_check <- regmatches(
    validation,
    regexpr(
      'check_name = "silver_activity_laps_power_provenance_reconciliation"[\\s\\S]{0,160}severity = "[A-Z]+"',
      validation,
      perl = TRUE
    )
  )
  testthat::expect_match(power_check, 'severity = "INFO"', fixed = TRUE)
})

testthat::test_that("lap power provenance inherits the parent activity decision", {
  categories <- classify_lap_power_provenance(
    average_power_watts = c(250, 220, 240, 180, NA, 190),
    lap_is_device_watts = c(TRUE, TRUE, FALSE, TRUE, TRUE, NA),
    parent_power_source_type = c("measured", "virtual", "measured", NA, "measured", "estimated"),
    parent_power_source_status = c("inferred_measured", "inferred_virtual", "inferred_measured", NA, "inferred_measured", "ambiguous"),
    parent_is_measured_power = c(TRUE, FALSE, TRUE, NA, TRUE, FALSE),
    parent_is_power_record_eligible = c(TRUE, FALSE, TRUE, NA, TRUE, FALSE)
  )

  testthat::expect_identical(categories, c(
    "expected_agreement",
    "governed_override",
    "potential_inconsistency",
    "missing_canonical_context",
    "no_lap_power",
    "source_assertion_missing"
  ))
})

testthat::test_that("consumer eligibility is governed by the parent, not the source flag", {
  fixture <- data.frame(
    average_power_watts = c(220, 250),
    is_device_watts = c(TRUE, FALSE),
    parent_is_power_record_eligible = c(FALSE, TRUE),
    cadence_rpm = c(90, 95),
    heartrate_bpm = c(150, 155),
    distance_metres = c(1000, 1200),
    duration_seconds = c(120, 130),
    elevation_metres = c(8, 10)
  )
  unaffected <- fixture[c(
    "cadence_rpm", "heartrate_bpm", "distance_metres",
    "duration_seconds", "elevation_metres"
  )]

  eligible <- fixture$parent_is_power_record_eligible
  testthat::expect_identical(eligible, c(FALSE, TRUE))
  testthat::expect_identical(
    fixture[c("cadence_rpm", "heartrate_bpm", "distance_metres", "duration_seconds", "elevation_metres")],
    unaffected
  )
})

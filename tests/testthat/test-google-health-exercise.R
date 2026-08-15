find_google_health_exercise_root <- function() {
  candidates <- c(".", "../..")
  root <- candidates[file.exists(file.path(
    candidates,
    "R",
    "api",
    "get_google_health_exercise.R"
  ))][1]
  normalizePath(root, mustWork = TRUE)
}

exercise_root <- find_google_health_exercise_root()
source(file.path(exercise_root, "R", "api", "get_google_health_data_points.R"))
source(file.path(exercise_root, "R", "api", "get_google_health_daily_summaries.R"))
source(file.path(exercise_root, "R", "api", "get_google_health_exercise.R"))
source(file.path(exercise_root, "R", "database", "split_existing_rows.R"))
source(file.path(exercise_root, "R", "database", "upsert_google_health_exercise.R"))

exercise_fixture <- function(
  name = "users/me/dataTypes/exercise/dataPoints/strength-1",
  exercise_type = "STRENGTH_TRAINING"
) {
  list(
    name = name,
    dataSource = list(
      name = "Fitbit",
      platform = "FITBIT",
      recordingMethod = "AUTOMATICALLY_RECORDED",
      device = list(manufacturer = "Google", model = "Pixel Watch")
    ),
    exercise = list(
      updateTime = "2026-08-14T19:15:00Z",
      displayName = "Strength training",
      exerciseType = exercise_type,
      interval = list(
        startTime = list(
          physicalTime = "2026-08-14T18:00:00Z",
          utcOffset = "+01:00"
        ),
        endTime = list(
          physicalTime = "2026-08-14T18:45:00Z",
          utcOffset = "+01:00"
        )
      ),
      exerciseMetadata = list(manuallyRecorded = FALSE),
      metricsSummary = list(activeCalories = 210)
    )
  )
}

exercise_response <- function(body, status = 200L) {
  httr2::response(
    status_code = status,
    headers = list(`content-type` = "application/json"),
    body = charToRaw(jsonlite::toJSON(body, auto_unbox = TRUE))
  )
}

exercise_config <- function(page_size = 100L) {
  list(
    sources = list(google_health = list(user_id = "me")),
    ingestion = list(google_health_page_size = page_size)
  )
}

testthat::test_that("Exercise payload is shaped with identity interval and provenance", {
  shaped <- google_health_shape_exercise(
    list(exercise_fixture()),
    google_health_user_id = "me",
    run_id = bit64::as.integer64(12),
    source_id = 2L,
    retrieved_at = as.POSIXct("2026-08-15 05:00:00", tz = "UTC")
  )

  testthat::expect_equal(nrow(shaped), 1L)
  testthat::expect_equal(
    shaped$source_data_point_id,
    "users/me/dataTypes/exercise/dataPoints/strength-1"
  )
  testthat::expect_equal(shaped$exercise_type, "STRENGTH_TRAINING")
  testthat::expect_equal(shaped$display_name, "Strength training")
  testthat::expect_equal(
    format(shaped$interval_start_time, tz = "UTC"),
    "2026-08-14 18:00:00"
  )
  testthat::expect_equal(
    format(shaped$interval_end_time, tz = "UTC"),
    "2026-08-14 18:45:00"
  )
  testthat::expect_equal(shaped$start_utc_offset, "+01:00")
  testthat::expect_equal(shaped$end_utc_offset, "+01:00")
  testthat::expect_equal(
    format(shaped$source_update_time, tz = "UTC"),
    "2026-08-14 19:15:00"
  )
  testthat::expect_equal(shaped$source_platform, "FITBIT")
  testthat::expect_match(shaped$exercise_payload, "metricsSummary", fixed = TRUE)
})

testthat::test_that("optional metrics and unknown exercise types remain source aligned", {
  fixture <- exercise_fixture(exercise_type = "NEW_FUTURE_EXERCISE_TYPE")
  fixture$exercise$metricsSummary <- NULL
  shaped <- google_health_shape_exercise(
    list(fixture), "me", bit64::as.integer64(1), 2L, Sys.time()
  )
  testthat::expect_equal(shaped$exercise_type, "NEW_FUTURE_EXERCISE_TYPE")
  testthat::expect_false(grepl("metricsSummary", shaped$exercise_payload, fixed = TRUE))
})

testthat::test_that("Exercise source identity is required and malformed payloads fail", {
  no_name <- exercise_fixture(name = NULL)
  testthat::expect_error(
    google_health_shape_exercise(
      list(no_name), "me", bit64::as.integer64(1), 2L, Sys.time()
    ),
    "source name/id"
  )
  testthat::expect_error(
    google_health_shape_exercise(
      list(list(name = "x")), "me", bit64::as.integer64(1), 2L, Sys.time()
    ),
    "exercise payload is missing"
  )
})

testthat::test_that("Exercise observation key is stable and preserves revisions", {
  first <- exercise_fixture()
  repeated <- exercise_fixture()
  changed <- exercise_fixture()
  changed$exercise$displayName <- "Updated strength training"
  shape <- function(x) google_health_shape_exercise(
    list(x), "me", bit64::as.integer64(1), 2L, Sys.time()
  )$exercise_observation_key
  testthat::expect_identical(shape(first), shape(repeated))
  testthat::expect_false(identical(shape(first), shape(changed)))
})

testthat::test_that("Exercise accepts nested source update timestamps", {
  fixture <- exercise_fixture()
  fixture$exercise$updateTime <- list(physicalTime = "2026-08-14T19:15:00Z")
  shaped <- google_health_shape_exercise(
    list(fixture), "me", bit64::as.integer64(1), 2L, Sys.time()
  )
  testthat::expect_equal(
    format(shaped$source_update_time, tz = "UTC"),
    "2026-08-14 19:15:00"
  )
})

testthat::test_that("Exercise request paginates and retains every source record", {
  calls <- list()
  performer <- function(path, config, query, token) {
    calls[[length(calls) + 1L]] <<- list(path = path, query = query, token = token)
    if (length(calls) == 1L) {
      return(exercise_response(list(
        dataPoints = list(exercise_fixture(name = "exercise/1")),
        nextPageToken = "next"
      )))
    }
    exercise_response(list(dataPoints = list(exercise_fixture(name = "exercise/2"))))
  }
  result <- get_google_health_exercise(
    run_id = bit64::as.integer64(2),
    source_id = 2L,
    start_datetime = as.POSIXct("2026-08-01", tz = "UTC"),
    end_datetime = as.POSIXct("2026-08-02", tz = "UTC"),
    config = exercise_config(),
    token = "opaque-token",
    request_performer = performer,
    retrieved_at = as.POSIXct("2026-08-03", tz = "UTC")
  )
  testthat::expect_equal(nrow(result), 2L)
  testthat::expect_equal(attr(result, "page_count"), 2L)
  testthat::expect_equal(attr(result, "request_count"), 2L)
  testthat::expect_equal(calls[[2]]$query$pageToken, "next")
  testthat::expect_match(calls[[1]]$query$filter, "exercise.interval.start_time", fixed = TRUE)
  testthat::expect_false(grepl("sample_time", calls[[1]]$query$filter, fixed = TRUE))
})

testthat::test_that("Exercise request handles successful empty response and errors", {
  empty <- get_google_health_exercise(
    bit64::as.integer64(2), 2L,
    as.POSIXct("2026-08-01", tz = "UTC"),
    as.POSIXct("2026-08-02", tz = "UTC"),
    exercise_config(),
    token = "opaque",
    request_performer = function(...) exercise_response(list(dataPoints = list()))
  )
  testthat::expect_equal(nrow(empty), 0L)
  testthat::expect_equal(attr(empty, "page_count"), 1L)

  testthat::expect_error(
    get_google_health_exercise(
      bit64::as.integer64(2), 2L,
      as.POSIXct("2026-08-01", tz = "UTC"),
      as.POSIXct("2026-08-02", tz = "UTC"),
      exercise_config(),
      token = "opaque",
      request_performer = function(...) stop("endpoint denied")
    ),
    "endpoint denied"
  )
})

testthat::test_that("Exercise repeat observations are planned as unchanged", {
  exercise <- tibble::tibble(
    exercise_observation_key = c("a", "b"),
    value = c(1L, 2L)
  )
  plan <- plan_google_health_exercise_upsert(
    exercise,
    tibble::tibble(exercise_observation_key = "a")
  )
  testthat::expect_equal(plan$to_insert$exercise_observation_key, "b")
  testthat::expect_equal(plan$unchanged$exercise_observation_key, "a")
})

testthat::test_that("duplicate observations within a response are deduplicated", {
  exercise <- tibble::tibble(
    exercise_observation_key = c("a", "a"),
    value = c(1L, 1L)
  )
  plan <- plan_google_health_exercise_upsert(
    exercise,
    tibble::tibble(exercise_observation_key = character())
  )
  testthat::expect_equal(nrow(plan$to_insert), 1L)
  testthat::expect_equal(plan$duplicate_count, 1L)
})

testthat::test_that("Exercise ingestion records canonical operational entity", {
  source_text <- paste(readLines(
    file.path(exercise_root, "R", "ingestion", "ingest_google_health_exercise.R"),
    warn = FALSE
  ), collapse = "\n")
  testthat::expect_match(source_text, 'entity_name = "google_health_exercise"', fixed = TRUE)
  testthat::expect_match(source_text, "record_etl_request_log", fixed = TRUE)
  testthat::expect_match(source_text, "rows_unchanged", fixed = TRUE)
  testthat::expect_match(source_text, "page_count", fixed = TRUE)
  testthat::expect_match(source_text, "elapsed_seconds", fixed = TRUE)
})

testthat::test_that("Exercise DDL and orchestration remain Raw-only and additive", {
  ddl <- paste(readLines(
    file.path(exercise_root, "sql", "raw", "150_create_google_health_exercise.sql"),
    warn = FALSE
  ), collapse = "\n")
  orchestration <- paste(readLines(
    file.path(exercise_root, "run_raw_ingestion.R"),
    warn = FALSE
  ), collapse = "\n")
  config <- paste(readLines(
    file.path(exercise_root, "config", "platform.yml"),
    warn = FALSE
  ), collapse = "\n")

  testthat::expect_match(
    ddl,
    "CREATE TABLE IF NOT EXISTS cycling_platform_raw.google_health_exercise",
    fixed = TRUE
  )
  testthat::expect_match(ddl, "PRIMARY KEY (exercise_observation_key)", fixed = TRUE)
  testthat::expect_match(ddl, "exercise_payload JSON NOT NULL", fixed = TRUE)
  testthat::expect_match(ddl, "DEFAULT COLLATE utf8mb4_general_ci", fixed = TRUE)
  testthat::expect_match(orchestration, '"exercise" %in% google_health_data_types', fixed = TRUE)
  testthat::expect_match(orchestration, "ingest_google_health_exercise", fixed = TRUE)
  testthat::expect_match(config, "google_health_exercise_refresh_days", fixed = TRUE)
  testthat::expect_match(config, "google_health_exercise_backfill_days", fixed = TRUE)
  testthat::expect_false(grepl("cycling_platform_silver", ddl, fixed = TRUE))
  testthat::expect_false(grepl("cycling_platform_gold", ddl, fixed = TRUE))
})

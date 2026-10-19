project_file <- function(...) {
  path <- file.path(...)
  if (!file.exists(path)) {
    path <- file.path("..", "..", ...)
  }
  path
}

source(project_file(
  "R", "database",
  "plan_google_health_daily_resting_heart_rate_upsert.R"
))
source(project_file(
  "R", "database",
  "upsert_google_health_daily_resting_heart_rate.R"
))

rhr_row <- function(
  key = paste(rep("a", 64L), collapse = ""),
  payload = '{"dailyRestingHeartRate":{"beatsPerMinute":"48"}}',
  run_id = 10L,
  source_id = 2L
) {
  tibble::tibble(
    daily_resting_heart_rate_key = key,
    source_id = source_id,
    google_health_user_id = "me",
    source_data_point_id = NA_character_,
    activity_date = as.Date("2026-10-05"),
    resting_heart_rate_bpm = 48,
    calculation_method = "WITH_SLEEP",
    source_name = "fixture",
    source_ecosystem = "FITBIT",
    source_platform = "FITBIT",
    source_recording_method = "DERIVED",
    source_device_manufacturer = NA_character_,
    source_device_model = NA_character_,
    run_id = run_id,
    retrieved_at = as.POSIXct("2026-10-19 06:00:00", tz = "UTC"),
    daily_resting_heart_rate_payload = payload
  )
}

empty_existing_rhr <- function() {
  tibble::tibble(
    daily_resting_heart_rate_key = character(),
    payload_hash = character()
  )
}

testthat::test_that("new daily RHR records are inserted once", {
  inserted <- list()
  result <- upsert_google_health_daily_resting_heart_rate(
    connection = NULL,
    daily_resting_heart_rate = rhr_row(),
    get_existing = function(connection, daily_resting_heart_rate_keys) {
      empty_existing_rhr()
    },
    insert_rows = function(connection, daily_resting_heart_rate) {
      inserted[[1L]] <<- daily_resting_heart_rate
      nrow(daily_resting_heart_rate)
    },
    update_rows = function(...) stop("unexpected update")
  )

  testthat::expect_equal(result$rows_inserted, 1L)
  testthat::expect_equal(result$rows_updated, 0L)
  testthat::expect_equal(result$rows_unchanged, 0L)
  testthat::expect_equal(nrow(inserted[[1L]]), 1L)
})

testthat::test_that("identical source repeats within one response are idempotent", {
  incoming <- dplyr::bind_rows(rhr_row(), rhr_row())
  inserted <- list()

  result <- upsert_google_health_daily_resting_heart_rate(
    connection = NULL,
    daily_resting_heart_rate = incoming,
    get_existing = function(...) empty_existing_rhr(),
    insert_rows = function(connection, daily_resting_heart_rate) {
      inserted[[1L]] <<- daily_resting_heart_rate
      nrow(daily_resting_heart_rate)
    },
    update_rows = function(...) stop("unexpected update")
  )

  testthat::expect_equal(nrow(inserted[[1L]]), 1L)
  testthat::expect_equal(result$rows_inserted, 1L)
  testthat::expect_equal(result$rows_unchanged, 1L)
})

testthat::test_that("overlapping-window re-ingestion is reported unchanged", {
  incoming <- rhr_row(run_id = 11L)
  existing <- tibble::tibble(
    daily_resting_heart_rate_key = incoming$daily_resting_heart_rate_key,
    payload_hash = google_health_rhr_payload_hash(
      incoming$daily_resting_heart_rate_payload
    )
  )

  result <- upsert_google_health_daily_resting_heart_rate(
    connection = NULL,
    daily_resting_heart_rate = incoming,
    get_existing = function(...) existing,
    insert_rows = function(...) stop("unexpected insert"),
    update_rows = function(...) stop("unexpected update")
  )

  testthat::expect_equal(result$rows_inserted, 0L)
  testthat::expect_equal(result$rows_updated, 0L)
  testthat::expect_equal(result$rows_unchanged, 1L)
})

testthat::test_that("changed payload for a stable source identity is updated", {
  incoming <- rhr_row(
    payload = '{"dailyRestingHeartRate":{"beatsPerMinute":"49"}}',
    run_id = 12L
  )
  existing <- tibble::tibble(
    daily_resting_heart_rate_key = incoming$daily_resting_heart_rate_key,
    payload_hash = google_health_rhr_payload_hash(
      '{"dailyRestingHeartRate":{"beatsPerMinute":"48"}}'
    )
  )
  updated <- list()

  result <- upsert_google_health_daily_resting_heart_rate(
    connection = NULL,
    daily_resting_heart_rate = incoming,
    get_existing = function(...) existing,
    insert_rows = function(...) stop("unexpected insert"),
    update_rows = function(connection, daily_resting_heart_rate) {
      updated[[1L]] <<- daily_resting_heart_rate
      nrow(daily_resting_heart_rate)
    }
  )

  testthat::expect_equal(result$rows_inserted, 0L)
  testthat::expect_equal(result$rows_updated, 1L)
  testthat::expect_equal(result$rows_unchanged, 0L)
  testthat::expect_equal(updated[[1L]]$run_id, 12L)
  testthat::expect_equal(updated[[1L]]$source_id, 2L)
})

testthat::test_that("conflicting duplicates remain visible integrity errors", {
  incoming <- dplyr::bind_rows(
    rhr_row(payload = '{"value":48}'),
    rhr_row(payload = '{"value":49}')
  )

  testthat::expect_error(
    plan_google_health_daily_resting_heart_rate_upsert(
      incoming,
      empty_existing_rhr()
    ),
    "Conflicting Google Health daily RHR payloads"
  )
})

testthat::test_that("failed writes remain visible and a retry can succeed", {
  attempts <- 0L
  write_once <- function(connection, daily_resting_heart_rate) {
    attempts <<- attempts + 1L
    if (attempts == 1L) {
      stop("fixture database write failed")
    }
    nrow(daily_resting_heart_rate)
  }

  run_upsert <- function() {
    upsert_google_health_daily_resting_heart_rate(
      connection = NULL,
      daily_resting_heart_rate = rhr_row(),
      get_existing = function(...) empty_existing_rhr(),
      insert_rows = write_once,
      update_rows = function(...) stop("unexpected update")
    )
  }

  testthat::expect_error(run_upsert(), "fixture database write failed")
  testthat::expect_equal(run_upsert()$rows_inserted, 1L)
})

testthat::test_that("unrelated existing Raw identities are not selected", {
  incoming <- rhr_row()
  unrelated <- tibble::tibble(
    daily_resting_heart_rate_key = paste(rep("b", 64L), collapse = ""),
    payload_hash = google_health_rhr_payload_hash('{"value":47}')
  )

  plan <- plan_google_health_daily_resting_heart_rate_upsert(
    incoming,
    unrelated
  )

  testthat::expect_equal(nrow(plan$to_insert), 1L)
  testthat::expect_equal(nrow(plan$to_update), 0L)
  testthat::expect_equal(nrow(plan$unchanged), 0L)
})

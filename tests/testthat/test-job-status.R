job_status_test_sources <- function() {
  root <- if (dir.exists("R")) "." else file.path("..", "..")
  source(file.path(root, "R", "utils", "execution_context.R"))
  source(file.path(root, "R", "utils", "format_notification_helpers.R"))
  source(file.path(root, "R", "utils", "job_status.R"))
  source(file.path(root, "R", "utils", "platform_run_lock.R"))
  source(file.path(root, "R", "database", "get_connection.R"))
  source(file.path(root, "R", "transforms", "run_silver_transformations.R"))
  source(file.path(root, "R", "jobs", "run_silver_job.R"))
}
job_status_test_sources()

new_test_tracker <- function(directory, now = as.POSIXct("2026-08-01 12:00:00", tz = "UTC")) {
  create_job_status_tracker(
    "silver-full", "full", directory,
    heartbeat_interval_seconds = 60,
    retention_days = 30,
    now = now,
    host = "test-host",
    pid = 123L
  )
}

testthat::test_that("tracker writes STARTING latest and run-specific status atomically", {
  directory <- tempfile("job-status-")
  tracker <- new_test_tracker(directory)
  testthat::expect_true(file.exists(tracker$latest_path))
  testthat::expect_true(file.exists(tracker$run_path))
  status <- jsonlite::read_json(tracker$latest_path, simplifyVector = TRUE)
  testthat::expect_equal(status$status, "STARTING")
  testthat::expect_equal(status$current_phase, "bootstrap")
  testthat::expect_equal(status$host, "test-host")
  testthat::expect_length(list.files(dirname(tracker$latest_path), pattern = "^[.].*[.]json"), 0L)
})

testthat::test_that("heartbeat and progress update durable state", {
  directory <- tempfile("job-status-")
  start <- as.POSIXct("2026-08-01 12:00:00", tz = "UTC")
  tracker <- new_test_tracker(directory, start)
  testthat::expect_false(heartbeat_job_status(tracker, start + 30))
  testthat::expect_true(heartbeat_job_status(tracker, start + 61))
  update_job_status(
    tracker, status = "RUNNING", current_phase = "rebuild",
    current_entity = "activity_streams", progress_completed = 20,
    progress_total = 100, rows_written = 5000, current_batch = 2,
    total_batches = 10, completed_batches = 2, now = start + 62
  )
  status <- read_job_status(tracker$latest_path)$status
  testthat::expect_equal(status$status, "RUNNING")
  testthat::expect_equal(status$progress_completed, 20)
  testthat::expect_equal(status$rows_written, 5000)
  testthat::expect_equal(status$completed_batches, 2)
})

testthat::test_that("success and failure finalisation are durable", {
  directory <- tempfile("job-status-")
  tracker <- new_test_tracker(directory)
  finish_job_status(tracker, "SUCCESS", summary = list(rows_written = 100))
  success <- read_job_status(tracker$latest_path)$status
  testthat::expect_equal(success$status, "SUCCESS")
  testthat::expect_equal(success$current_phase, "complete")
  testthat::expect_false(is.null(success$finished_at))

  failed <- new_test_tracker(tempfile("job-status-"))
  error <- simpleError("password=hunter2 token=abc123")
  finish_job_status(failed, "FAILED", error = error)
  failure <- read_job_status(failed$latest_path)$status
  testthat::expect_equal(failure$status, "FAILED")
  testthat::expect_equal(failure$current_phase, "failed")
  testthat::expect_match(failure$error$message, "[REDACTED]", fixed = TRUE)
  testthat::expect_false(grepl("hunter2|abc123", paste(readLines(failed$latest_path), collapse = "")))
})

testthat::test_that("reader handles missing and malformed status", {
  missing <- read_job_status(tempfile())
  testthat::expect_false(missing$ok)
  path <- tempfile(fileext = ".json")
  writeLines("{not-json", path)
  malformed <- read_job_status(path)
  testthat::expect_false(malformed$ok)
  testthat::expect_match(malformed$error, "Malformed status file", fixed = TRUE)
})

testthat::test_that("run-specific history obeys configured retention", {
  directory <- tempfile("job-status-")
  tracker <- new_test_tracker(directory)
  old <- file.path(dirname(tracker$run_path), "silver-full-20200101T000000Z-1-old.json")
  writeLines("{}", old)
  Sys.setFileTime(old, Sys.time() - 31 * 86400)
  tracker$retention_days <- 30
  testthat::expect_equal(prune_job_status_history(tracker), 1L)
  testthat::expect_false(file.exists(old))
  testthat::expect_true(file.exists(tracker$run_path))
})

testthat::test_that("staleness observes old heartbeat without mutating status", {
  status <- list(
    status = "RUNNING", host = "remote-host", pid_scope = "container", pid = 999999L,
    last_heartbeat_at = "2026-08-01T12:00:00Z"
  )
  result <- job_status_staleness(status, as.POSIXct("2026-08-01 12:03:00", tz = "UTC"), 120)
  testthat::expect_true(result$stale)
  testthat::expect_equal(status$status, "RUNNING")
})

testthat::test_that("missing native PID is reported when the check is meaningful", {
  status <- list(
    status = "RUNNING", host = platform_execution_host(), pid_scope = "host",
    pid = 99999999L, last_heartbeat_at = job_status_timestamp()
  )
  old_scope <- job_status_pid_scope
  assign("job_status_pid_scope", function() "host", envir = globalenv())
  on.exit(assign("job_status_pid_scope", old_scope, envir = globalenv()), add = TRUE)
  result <- job_status_staleness(status, check_pid = TRUE)
  testthat::expect_true(result$pid_check_applicable)
  testthat::expect_true(result$pid_missing)
  testthat::expect_true(result$stale)
})

testthat::test_that("CLI formatter shows running and completed information", {
  directory <- tempfile("job-status-")
  tracker <- new_test_tracker(directory)
  update_job_status(
    tracker, status = "RUNNING", current_phase = "rebuild",
    current_entity = "activity_streams", progress_completed = 2814,
    progress_total = 3886, progress_unit = "activities", rows_written = 38421774,
    current_batch = 29, total_batches = 40, completed_batches = 28
  )
  running <- format_job_status(tracker$state, list(stale = FALSE))
  testthat::expect_match(running, "Status: RUNNING", fixed = TRUE)
  testthat::expect_match(running, "Progress: 2,814 / 3,886 activities", fixed = TRUE)
  testthat::expect_match(running, "Rows written: 38,421,774", fixed = TRUE)
  testthat::expect_match(running, "Stale: no", fixed = TRUE)
  finish_job_status(tracker, "SUCCESS", summary = list(rows_written = 38421774))
  complete <- format_job_status(tracker$state, list(stale = FALSE))
  testthat::expect_match(complete, "Status: SUCCESS", fixed = TRUE)
  testthat::expect_match(complete, "Final metrics:", fixed = TRUE)
})

testthat::test_that("concurrent lock refusal records FAILED status", {
  directory <- tempfile("job-status-")
  active <- new_test_tracker(directory)
  update_job_status(active, status = "RUNNING", current_phase = "rebuild")
  active_run_id <- active$state$run_id
  originals <- mget(c("get_connection", "acquire_platform_run_lock"), globalenv(), inherits = FALSE)
  on.exit(list2env(originals, globalenv()), add = TRUE)
  assign("get_connection", function(...) "mock", globalenv())
  assign("acquire_platform_run_lock", function(...) stop("another run is active", call. = FALSE), globalenv())
  config <- list(logging = list(directory = directory, retention_days = 30, status_heartbeat_seconds = 60))
  testthat::expect_error(run_silver_job("full", config), "another run is active")
  history <- list.files(file.path(directory, "status"), pattern = "^silver-full-[0-9].*[.]json$", full.names = TRUE)
  statuses <- lapply(history, function(path) read_job_status(path)$status)
  status <- statuses[[which(vapply(statuses, function(value) identical(value$status, "FAILED"), logical(1)))]]
  testthat::expect_equal(status$status, "FAILED")
  testthat::expect_match(status$error$message, "another run is active", fixed = TRUE)
  latest <- read_job_status(file.path(directory, "status", "silver-full-latest.json"))$status
  testthat::expect_equal(latest$run_id, active_run_id)
  testthat::expect_equal(latest$status, "RUNNING")
})

testthat::test_that("representative Silver execution updates status through success", {
  directory <- tempfile("job-status-")
  names <- c("get_connection", "acquire_platform_run_lock", "release_platform_run_lock", "run_silver_transformations")
  originals <- mget(names, globalenv(), inherits = FALSE)
  on.exit(list2env(originals, globalenv()), add = TRUE)
  assign("get_connection", function(...) "mock", globalenv())
  assign("acquire_platform_run_lock", function(...) invisible(TRUE), globalenv())
  assign("release_platform_run_lock", function(...) invisible(TRUE), globalenv())
  assign("run_silver_transformations", function(connection, config, stream_rebuild_mode, status_callback) {
    status_callback(list(status = "RUNNING", current_phase = "rebuild", current_entity = "activity_streams", progress_completed = 2, progress_total = 2, progress_unit = "activities", rows_processed = 200, rows_written = 200, rows_deleted = 0, current_batch = 1, total_batches = 1, completed_batches = 1), force = TRUE)
  }, globalenv())
  config <- list(logging = list(directory = directory, retention_days = 30, status_heartbeat_seconds = 60))
  result <- run_silver_job("full", config)
  testthat::expect_equal(result$status, "SUCCESS")
  testthat::expect_equal(result$summary$rows_written, 200)
  testthat::expect_equal(read_job_status(file.path(directory, "status", "silver-full-latest.json"))$status$status, "SUCCESS")
})

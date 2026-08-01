run_silver_job <- function(stream_rebuild_mode = "full", config = load_config()) {
  stream_rebuild_mode <- tolower(stream_rebuild_mode)
  if (identical(stream_rebuild_mode, "resume")) stream_rebuild_mode <- "repair"
  if (!stream_rebuild_mode %in% c("full", "repair")) {
    stop("Unknown silver stream rebuild mode. Use 'full' or 'repair'.", call. = FALSE)
  }

  job_name <- paste0("silver-", stream_rebuild_mode)
  tracker <- NULL
  connection <- NULL
  lock_connection <- NULL
  lock_acquired <- FALSE
  lock_owner <- paste0("manual-", job_name)
  on.exit({
    if (isTRUE(lock_acquired) && !is.null(lock_connection)) {
      tryCatch(release_platform_run_lock(lock_connection, lock_owner), error = function(e) invisible(FALSE))
    }
    if (!is.null(connection)) {
      tryCatch(if (DBI::dbIsValid(connection)) DBI::dbDisconnect(connection), error = function(e) invisible(NULL))
    }
    if (!is.null(lock_connection)) {
      tryCatch(if (DBI::dbIsValid(lock_connection)) DBI::dbDisconnect(lock_connection), error = function(e) invisible(NULL))
    }
  }, add = TRUE)

  make_tracker <- function(publish_latest = TRUE) {
    create_job_status_tracker(
      job_name = job_name,
      run_mode = stream_rebuild_mode,
      log_directory = config$logging$directory %||% "logs",
      heartbeat_interval_seconds = config$logging$status_heartbeat_seconds %||% 60,
      retention_days = config$logging$retention_days %||% 30,
      publish_latest = publish_latest
    )
  }

  connection_error <- tryCatch({
    lock_connection <- get_connection("cycling_platform_admin")
    NULL
  }, error = function(e) e)
  if (!is.null(connection_error)) {
    tracker <- make_tracker(publish_latest = TRUE)
    finish_job_status(tracker, "FAILED", error = connection_error)
    stop(connection_error)
  }

  lock_error <- tryCatch({
    acquire_platform_run_lock(lock_connection, lock_owner)
    lock_acquired <- TRUE
    NULL
  }, error = function(e) e)
  if (!is.null(lock_error)) {
    tracker <- make_tracker(publish_latest = FALSE)
    finish_job_status(
      tracker,
      "FAILED",
      error = lock_error,
      summary = list(refused = TRUE, reason = "platform lock unavailable")
    )
    stop(lock_error)
  }

  tracker <- make_tracker(publish_latest = TRUE)
  connection_error <- tryCatch({
    connection <- get_connection("cycling_platform_admin")
    NULL
  }, error = function(e) e)
  if (!is.null(connection_error)) {
    finish_job_status(tracker, "FAILED", error = connection_error)
    stop(connection_error)
  }

  status_callback <- function(event = list(), force = FALSE) {
    if (length(event) == 0L) return(heartbeat_job_status(tracker))
    do.call(update_job_status, c(list(tracker = tracker), event, list(force = force)))
  }

  run_error <- tryCatch(
    {
      update_job_status(
        tracker,
        status = "RUNNING",
        current_phase = "table_creation",
        current_entity = "silver",
        force = TRUE
      )

      run_silver_transformations(
        connection = connection,
        config = config,
        stream_rebuild_mode = stream_rebuild_mode,
        status_callback = status_callback
      )
      NULL
    },
    error = function(e) e,
    interrupt = function(e) e
  )

  if (!is.null(run_error)) {
    finish_job_status(
      tracker,
      status = "FAILED",
      error = run_error,
      summary = list(
        progress_completed = tracker$state$progress_completed,
        progress_total = tracker$state$progress_total,
        rows_written = tracker$state$rows_written,
        rows_deleted = tracker$state$rows_deleted,
        completed_batches = tracker$state$completed_batches,
        total_batches = tracker$state$total_batches
      )
    )
  } else {
    finish_job_status(
      tracker,
      status = "SUCCESS",
      summary = list(
        activities_processed = tracker$state$progress_completed,
        expected_rows_processed = tracker$state$rows_processed,
        rows_written = tracker$state$rows_written,
        rows_deleted = tracker$state$rows_deleted,
        completed_batches = tracker$state$completed_batches,
        total_batches = tracker$state$total_batches
      )
    )
  }

  if (!is.null(run_error)) stop(run_error)

  message("Silver transformations complete. Status: ", tracker$latest_path)
  invisible(tracker$state)
}

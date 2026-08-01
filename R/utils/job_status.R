job_status_timestamp <- function(value = Sys.time()) {
  format(value, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

sanitize_job_status_error <- function(value) {
  if (is.null(value) || length(value) == 0L) return(NULL)
  value <- substr(as.character(value[[1]]), 1L, 1000L)
  value <- gsub("(?i)(password|token|secret|authorization)([=: ]+)[^ ,;]+", "\\1\\2[REDACTED]", value, perl = TRUE)
  value <- gsub("(https?://[^:/@ ]+):[^@/ ]+@", "\\1:[REDACTED]@", value, perl = TRUE)
  value
}

job_status_pid_scope <- function() {
  if (file.exists("/.dockerenv")) "container" else "host"
}

new_job_status_run_id <- function(job_name, now = Sys.time(), pid = Sys.getpid()) {
  random <- paste(sprintf("%02x", as.integer(openssl::rand_bytes(6L))), collapse = "")
  paste(format(now, "%Y%m%dT%H%M%SZ", tz = "UTC"), pid, random, sep = "-")
}

atomic_write_job_status <- function(path, status) {
  directory <- dirname(path)
  dir.create(directory, recursive = TRUE, showWarnings = FALSE, mode = "0750")
  temporary <- tempfile(pattern = paste0(".", basename(path), "."), tmpdir = directory)
  connection <- file(temporary, open = "wb")
  closed <- FALSE
  on.exit({
    if (!closed) close(connection)
    if (file.exists(temporary)) unlink(temporary)
  }, add = TRUE)
  writeLines(jsonlite::toJSON(status, auto_unbox = TRUE, null = "null", pretty = TRUE), connection, useBytes = TRUE)
  flush(connection)
  close(connection)
  closed <- TRUE
  Sys.chmod(temporary, mode = "0640")
  if (!file.rename(temporary, path)) stop("Unable to atomically replace job status file: ", path, call. = FALSE)
  invisible(path)
}

create_job_status_tracker <- function(
  job_name,
  run_mode,
  log_directory = "logs",
  heartbeat_interval_seconds = 60,
  retention_days = 30,
  publish_latest = TRUE,
  now = Sys.time(),
  host = platform_execution_host(),
  pid = Sys.getpid()
) {
  status_directory <- file.path(log_directory, "status")
  run_id <- new_job_status_run_id(job_name, now, pid)
  tracker <- new.env(parent = emptyenv())
  tracker$heartbeat_interval_seconds <- heartbeat_interval_seconds
  tracker$retention_days <- retention_days
  tracker$publish_latest <- publish_latest
  tracker$latest_path <- file.path(status_directory, paste0(job_name, "-latest.json"))
  tracker$run_path <- file.path(status_directory, paste0(job_name, "-", run_id, ".json"))
  tracker$last_write_time <- as.POSIXct(NA)
  tracker$started_time <- now
  tracker$state <- list(
    schema_version = 1L,
    job_name = job_name,
    run_mode = run_mode,
    run_id = run_id,
    host = host,
    pid = as.integer(pid),
    pid_scope = job_status_pid_scope(),
    started_at = job_status_timestamp(now),
    last_heartbeat_at = job_status_timestamp(now),
    finished_at = NULL,
    elapsed_seconds = 0,
    status = "STARTING",
    current_phase = "bootstrap",
    current_entity = NULL,
    progress_completed = 0,
    progress_total = NULL,
    progress_unit = NULL,
    rows_processed = 0,
    rows_written = 0,
    rows_deleted = 0,
    current_batch = NULL,
    total_batches = NULL,
    completed_batches = 0,
    last_business_key = NULL,
    error = NULL,
    summary = NULL
  )
  write_job_status(tracker, now = now, force = TRUE)
  prune_job_status_history(tracker)
  tracker
}

write_job_status <- function(tracker, now = Sys.time(), force = FALSE) {
  due <- is.na(tracker$last_write_time) ||
    as.numeric(difftime(now, tracker$last_write_time, units = "secs")) >= tracker$heartbeat_interval_seconds
  if (!force && !due) return(invisible(FALSE))
  tracker$state$last_heartbeat_at <- job_status_timestamp(now)
  tracker$state$elapsed_seconds <- max(0, as.numeric(difftime(now, tracker$started_time, units = "secs")))
  atomic_write_job_status(tracker$run_path, tracker$state)
  if (isTRUE(tracker$publish_latest)) atomic_write_job_status(tracker$latest_path, tracker$state)
  tracker$last_write_time <- now
  invisible(TRUE)
}

update_job_status <- function(tracker, ..., now = Sys.time(), force = TRUE) {
  updates <- list(...)
  for (name in names(updates)) {
    if (!is.null(updates[[name]])) tracker$state[[name]] <- updates[[name]]
  }
  write_job_status(tracker, now = now, force = force)
}

heartbeat_job_status <- function(tracker, now = Sys.time()) {
  write_job_status(tracker, now = now, force = FALSE)
}

finish_job_status <- function(tracker, status, error = NULL, summary = NULL, now = Sys.time()) {
  stopifnot(status %in% c("SUCCESS", "FAILED"))
  tracker$state$status <- status
  tracker$state$current_phase <- if (identical(status, "SUCCESS")) "complete" else "failed"
  tracker$state$current_entity <- NULL
  tracker$state$finished_at <- job_status_timestamp(now)
  tracker$state$error <- if (is.null(error)) NULL else list(
    class = class(error)[[1]],
    message = sanitize_job_status_error(conditionMessage(error))
  )
  tracker$state$summary <- summary
  write_job_status(tracker, now = now, force = TRUE)
}

prune_job_status_history <- function(tracker, now = Sys.time()) {
  files <- list.files(dirname(tracker$run_path), pattern = paste0("^", tracker$state$job_name, "-[0-9].*[.]json$"), full.names = TRUE)
  if (length(files) == 0L) return(invisible(0L))
  ages <- as.numeric(difftime(now, file.info(files)$mtime, units = "days"))
  expired <- files[!is.na(ages) & ages > tracker$retention_days & files != tracker$run_path]
  if (length(expired) > 0L) unlink(expired)
  invisible(length(expired))
}

read_job_status <- function(path) {
  if (!file.exists(path)) return(list(ok = FALSE, error = "Status file not found."))
  tryCatch(
    list(ok = TRUE, status = jsonlite::read_json(path, simplifyVector = TRUE)),
    error = function(e) list(ok = FALSE, error = paste0("Malformed status file: ", conditionMessage(e)))
  )
}

job_status_staleness <- function(status, now = Sys.time(), stale_after_seconds = 120, check_pid = TRUE) {
  heartbeat <- as.POSIXct(status$last_heartbeat_at, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  age <- as.numeric(difftime(now, heartbeat, units = "secs"))
  heartbeat_stale <- identical(status$status, "RUNNING") && (is.na(age) || age > stale_after_seconds)
  pid_missing <- FALSE
  pid_check_applicable <- isTRUE(check_pid) &&
    identical(status$status, "RUNNING") &&
    identical(status$host, platform_execution_host()) &&
    identical(status$pid_scope, "host") &&
    identical(job_status_pid_scope(), "host")
  if (pid_check_applicable) {
    pid_missing <- !dir.exists(file.path("/proc", status$pid)) &&
      !identical(system2("kill", c("-0", status$pid), stdout = FALSE, stderr = FALSE), 0L)
  }
  list(stale = heartbeat_stale || pid_missing, heartbeat_age_seconds = age, pid_missing = pid_missing, pid_check_applicable = pid_check_applicable)
}

format_job_status <- function(status, staleness) {
  local_time <- function(value) {
    if (is.null(value) || is.na(value) || !nzchar(value)) return("not recorded")
    format(as.POSIXct(value, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), "%Y-%m-%d %H:%M:%S %Z", tz = "")
  }
  value_or <- function(value, fallback = "unknown") {
    if (is.null(value) || length(value) == 0L || is.na(value)) fallback else as.character(value)
  }
  lines <- c(
    paste0("Job: ", status$job_name),
    paste0("Run ID: ", status$run_id),
    paste0("Status: ", status$status),
    paste0("Host: ", status$host),
    paste0("Phase: ", value_or(status$current_phase)),
    paste0("Entity: ", value_or(status$current_entity)),
    paste0("Progress: ", format(status$progress_completed %||% 0, big.mark = ","), " / ", format(status$progress_total %||% 0, big.mark = ","), " ", value_or(status$progress_unit, "")),
    paste0("Batch: ", value_or(status$current_batch, "not started"), " / ", value_or(status$total_batches)),
    paste0("Completed batches: ", value_or(status$completed_batches, "0")),
    paste0("Rows processed: ", format(status$rows_processed %||% 0, big.mark = ",")),
    paste0("Rows written: ", format(status$rows_written %||% 0, big.mark = ",")),
    paste0("Rows deleted: ", format(status$rows_deleted %||% 0, big.mark = ",")),
    paste0("Last business key: ", value_or(status$last_business_key, "not available")),
    paste0("Started: ", local_time(status$started_at)),
    paste0("Last heartbeat: ", local_time(status$last_heartbeat_at)),
    paste0("Elapsed: ", format_platform_duration(status$elapsed_seconds)),
    paste0("Stale: ", if (staleness$stale) "yes" else "no")
  )
  if (!is.null(status$finished_at)) lines <- c(lines, paste0("Finished: ", local_time(status$finished_at)))
  if (!is.null(status$error)) lines <- c(lines, paste0("Error: ", status$error$class, ": ", status$error$message))
  if (!is.null(status$summary)) {
    metrics <- paste(names(status$summary), unlist(status$summary), sep = "=", collapse = ", ")
    lines <- c(lines, paste0("Final metrics: ", metrics))
  }
  paste(lines, collapse = "\n")
}

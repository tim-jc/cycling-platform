sanitize_operational_text <- function(value, max_length = 2000L) {
  if (is.null(value) || length(value) == 0L || is.na(value[[1]])) {
    return(NA_character_)
  }

  text <- as.character(value[[1]])
  patterns <- c(
    "(?i)(authorization\\s*[:=]\\s*)(bearer\\s+)?[^[:space:],;]+" = "\\1[REDACTED]",
    "(?i)((?:password|access[_ -]?token|refresh[_ -]?token|client[_ -]?secret|ntfy[_ -]?topic|secret)\\s*[:=]\\s*)[^[:space:],;]+" = "\\1[REDACTED]",
    "(https?://[^:/@[:space:]]+):[^@/[:space:]]+@" = "\\1:[REDACTED]@"
  )
  for (pattern in names(patterns)) {
    text <- gsub(pattern, patterns[[pattern]], text, perl = TRUE)
  }
  substr(text, 1L, as.integer(max_length))
}

operational_failure_class <- function(error) {
  if (is.null(error)) return(NA_character_)
  sanitize_operational_text(paste(class(error), collapse = "/"), 255L)
}

pipeline_phase_contract <- function() {
  data.frame(
    phase_name = c(
      "raw_ingestion", "silver_transforms", "silver_publication_checks",
      "gold_transforms", "gold_publication_checks",
      "achievement_notifications", "deep_validation"
    ),
    phase_ordinal = seq_len(7L),
    stringsAsFactors = FALSE
  )
}

create_pipeline_run <- function(
  connection,
  pipeline_name,
  execution_mode,
  trigger_type,
  execution_host,
  requested_window_start = NULL,
  requested_window_end = NULL
) {
  DBI::dbExecute(
    connection,
    "INSERT INTO cycling_platform_admin.pipeline_run (
       pipeline_name, execution_mode, trigger_type, execution_host,
       requested_window_start, requested_window_end, run_status, started_at
     ) VALUES (?, ?, ?, ?, ?, ?, 'RUNNING', UTC_TIMESTAMP())",
    params = list(
      pipeline_name,
      toupper(execution_mode),
      toupper(trigger_type),
      execution_host,
      if (is.null(requested_window_start)) as.Date(NA) else as.Date(requested_window_start),
      if (is.null(requested_window_end)) as.Date(NA) else as.Date(requested_window_end)
    )
  )
  pipeline_run_id <- DBI::dbGetQuery(
    connection,
    "SELECT LAST_INSERT_ID() AS pipeline_run_id"
  )$pipeline_run_id[[1]]

  phases <- pipeline_phase_contract()
  for (index in seq_len(nrow(phases))) {
    DBI::dbExecute(
      connection,
      "INSERT INTO cycling_platform_admin.pipeline_phase_run (
         pipeline_run_id, phase_name, phase_ordinal, phase_status
       ) VALUES (?, ?, ?, 'NOT_RUN')",
      params = list(
        pipeline_run_id,
        phases$phase_name[[index]],
        phases$phase_ordinal[[index]]
      )
    )
  }
  pipeline_run_id
}

start_pipeline_phase <- function(connection, pipeline_run_id, phase_name) {
  changed <- DBI::dbExecute(
    connection,
    "UPDATE cycling_platform_admin.pipeline_phase_run
        SET phase_status = 'RUNNING', started_at = UTC_TIMESTAMP(),
            completed_at = NULL, duration_seconds = NULL,
            failure_class = NULL, failure_summary = NULL
      WHERE pipeline_run_id = ? AND phase_name = ? AND phase_status = 'NOT_RUN'",
    params = list(pipeline_run_id, phase_name)
  )
  if (!identical(as.integer(changed), 1L)) {
    stop("Unable to start durable pipeline phase: ", phase_name, call. = FALSE)
  }
  invisible(NULL)
}

finish_pipeline_phase <- function(
  connection,
  pipeline_run_id,
  phase_name,
  phase_status,
  error = NULL,
  failure_summary = NULL
) {
  stopifnot(phase_status %in% c("SUCCESS", "FAILED", "SKIPPED"))
  summary <- if (!is.null(error)) conditionMessage(error) else failure_summary
  changed <- DBI::dbExecute(
    connection,
    "UPDATE cycling_platform_admin.pipeline_phase_run
        SET phase_status = ?, completed_at = UTC_TIMESTAMP(),
            duration_seconds = TIMESTAMPDIFF(MICROSECOND, started_at, UTC_TIMESTAMP()) / 1000000,
            failure_class = ?, failure_summary = ?
      WHERE pipeline_run_id = ? AND phase_name = ? AND phase_status = 'RUNNING'",
    params = list(
      phase_status,
      if (is.null(error)) NA_character_ else operational_failure_class(error),
      sanitize_operational_text(summary),
      pipeline_run_id,
      phase_name
    )
  )
  if (!identical(as.integer(changed), 1L)) {
    stop("Unable to finish durable pipeline phase: ", phase_name, call. = FALSE)
  }
  invisible(NULL)
}

annotate_not_run_pipeline_phase <- function(
  connection,
  pipeline_run_id,
  phase_name,
  reason
) {
  DBI::dbExecute(
    connection,
    "UPDATE cycling_platform_admin.pipeline_phase_run
        SET failure_summary = ?
      WHERE pipeline_run_id = ? AND phase_name = ? AND phase_status = 'NOT_RUN'",
    params = list(sanitize_operational_text(reason), pipeline_run_id, phase_name)
  )
  invisible(NULL)
}

annotate_remaining_not_run_pipeline_phases <- function(
  connection,
  pipeline_run_id,
  reason
) {
  DBI::dbExecute(
    connection,
    "UPDATE cycling_platform_admin.pipeline_phase_run
        SET failure_summary = ?
      WHERE pipeline_run_id = ? AND phase_status = 'NOT_RUN'
        AND failure_summary IS NULL",
    params = list(sanitize_operational_text(reason), pipeline_run_id)
  )
  invisible(NULL)
}

finish_pipeline_run <- function(connection, pipeline_run_id, run_status, error = NULL) {
  stopifnot(run_status %in% c("SUCCESS", "FAILED"))
  changed <- DBI::dbExecute(
    connection,
    "UPDATE cycling_platform_admin.pipeline_run
        SET run_status = ?, completed_at = UTC_TIMESTAMP(),
            duration_seconds = TIMESTAMPDIFF(MICROSECOND, started_at, UTC_TIMESTAMP()) / 1000000,
            failure_class = ?, failure_summary = ?
      WHERE pipeline_run_id = ? AND run_status = 'RUNNING'",
    params = list(
      run_status,
      if (is.null(error)) NA_character_ else operational_failure_class(error),
      if (is.null(error)) NA_character_ else sanitize_operational_text(conditionMessage(error)),
      pipeline_run_id
    )
  )
  if (!identical(as.integer(changed), 1L)) {
    stop("Unable to finalise durable pipeline run ", pipeline_run_id, call. = FALSE)
  }
  invisible(NULL)
}

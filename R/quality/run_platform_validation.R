#' Run Platform Validation
#'
#' Compatibility wrapper around validate_platform_completeness().
#'
#' @param connection DBI connection.
#' @param config Platform configuration.
#' @param include_gold Whether to include Gold completeness checks.
#' @param validation_scope Validation scope: publication or deep.
#' @param run_mode Run mode recorded in admin metadata.
#' @param per_check_timeout_seconds Optional per-check timeout in seconds.
#' @param overall_timeout_seconds Optional overall timeout in seconds.
#' @param record_admin Whether to write validation status metadata.
#' @param notify Whether to send validation outcome notifications.
#'
#' @return Completeness validation result tibble.
validation_connection_is_valid <- function(connection) {
  tryCatch(
    DBI::dbIsValid(connection),
    error = function(e) {
      FALSE
    }
  )
}

with_validation_admin_connection <- function(
  connection,
  callback
) {
  admin_connection <- connection
  disconnect_admin_connection <- FALSE

  if (!validation_connection_is_valid(connection)) {
    message(
      "Validation admin metadata connection is no longer valid; ",
      "opening a fresh MariaDB connection."
    )

    admin_connection <- get_connection("cycling_platform_admin")
    disconnect_admin_connection <- TRUE
  }

  on.exit(
    {
      if (
        isTRUE(disconnect_admin_connection) &&
          validation_connection_is_valid(admin_connection)
      ) {
        DBI::dbDisconnect(admin_connection)
      }
    },
    add = TRUE
  )

  callback(admin_connection)
}

try_validation_admin_write <- function(
  connection,
  description,
  callback
) {
  tryCatch(
    {
      with_validation_admin_connection(
        connection = connection,
        callback = callback
      )
    },
    error = function(e) {
      message(
        "Unable to ",
        description,
        ": ",
        conditionMessage(e)
      )
    }
  )

  invisible(NULL)
}

run_platform_validation <- function(
  connection,
  config = list(),
  include_gold = TRUE,
  validation_scope = c(
    "deep",
    "publication"
  ),
  run_mode = "manual",
  per_check_timeout_seconds = NULL,
  overall_timeout_seconds = NULL,
  record_admin = TRUE,
  notify = FALSE
) {
  validation_scope <- match.arg(validation_scope)

  validation_started_at <- Sys.time()
  validation_run_id <- NULL
  validation_results <- empty_platform_validation_results()

  if (isTRUE(record_admin)) {
    ensure_validation_logging_tables(connection)

    validation_run_id <- create_validation_run(
      connection = connection,
      validation_scope = validation_scope,
      run_mode = run_mode,
      per_check_timeout_seconds = per_check_timeout_seconds,
      overall_timeout_seconds = overall_timeout_seconds
    )
  }

  validation_error <- NULL

  tryCatch(
    {
      validation_results <- validate_platform_completeness(
        connection = connection,
        config = config,
        include_gold = include_gold,
        validation_scope = validation_scope,
        per_check_timeout_seconds = per_check_timeout_seconds,
        overall_timeout_seconds = overall_timeout_seconds
      )
    },
    error = function(e) {
      validation_error <<- e
    }
  )

  if (
    isTRUE(record_admin) &&
      !is.null(validation_run_id) &&
      nrow(validation_results) > 0
  ) {
    try_validation_admin_write(
      connection = connection,
      description = "insert validation check metadata",
      callback = function(admin_connection) {
        insert_validation_run_checks(
          connection = admin_connection,
          validation_run_id = validation_run_id,
          validation_results = validation_results
        )
      }
    )
  }

  validation_results <- normalise_platform_validation_results(
    validation_results
  )

  checks_planned <- nrow(validation_results)
  checks_completed <- nrow(validation_results)
  checks_failed <- if (nrow(validation_results) == 0) {
    0L
  } else {
    sum(!validation_results$passed)
  }

  if (!is.null(validation_error)) {
    error_message <- conditionMessage(validation_error)
    run_status <- if (grepl(
      "timeout|max_statement_time|overall timeout",
      error_message,
      ignore.case = TRUE
    )) {
      "TIMED_OUT"
    } else {
      "FAILED"
    }

    validation_summary <- summarize_platform_validation_results(
      validation_results = validation_results,
      validation_outcome = if (identical(run_status, "TIMED_OUT")) {
        "TIMED_OUT"
      } else {
        "FAILED"
      }
    )

    if (
      isTRUE(record_admin) &&
        !is.null(validation_run_id)
    ) {
      try_validation_admin_write(
        connection = connection,
        description = "update failed validation run metadata",
        callback = function(admin_connection) {
          update_validation_run(
            connection = admin_connection,
            validation_run_id = validation_run_id,
            run_status = run_status,
            checks_planned = checks_planned,
            checks_completed = checks_completed,
            checks_failed = checks_failed,
            validation_summary = validation_summary,
            error_message = error_message
          )
        }
      )
    }

    if (isTRUE(notify)) {
      send_platform_validation_notification(
        config = config,
        job_name = "platform_validation",
        execution_status = run_status,
        validation_outcome = validation_summary$validation_outcome[[1]],
        completed_at = Sys.time(),
        elapsed_seconds = as.numeric(
          difftime(
            Sys.time(),
            validation_started_at,
            units = "secs"
          )
        ),
        validation_summary = validation_summary,
        validation_results = validation_results,
        validation_run_id = validation_run_id,
        error_message = error_message
      )
    }

    stop(validation_error)
  }

  validation_failed <- platform_validation_has_critical_failures(
    validation_results
  )

  validation_summary <- summarize_platform_validation_results(
    validation_results = validation_results,
    validation_outcome = if (validation_failed) {
      "FAILED"
    } else {
      NULL
    }
  )

  if (
    isTRUE(record_admin) &&
      !is.null(validation_run_id)
  ) {
    try_validation_admin_write(
      connection = connection,
      description = "update validation run metadata",
      callback = function(admin_connection) {
        update_validation_run(
          connection = admin_connection,
          validation_run_id = validation_run_id,
          run_status = if (validation_failed) {
            "FAILED"
          } else {
            "SUCCESS"
          },
          checks_planned = checks_planned,
          checks_completed = checks_completed,
          checks_failed = checks_failed,
          validation_summary = validation_summary
        )
      }
    )
  }

  if (isTRUE(notify)) {
    send_platform_validation_notification(
      config = config,
      job_name = "platform_validation",
      execution_status = if (validation_failed) {
        "FAILED"
      } else {
        "SUCCESS"
      },
      validation_outcome = validation_summary$validation_outcome[[1]],
      completed_at = Sys.time(),
      elapsed_seconds = as.numeric(
        difftime(
          Sys.time(),
          validation_started_at,
          units = "secs"
        )
      ),
      validation_summary = validation_summary,
      validation_results = validation_results,
      validation_run_id = validation_run_id
    )
  }

  if (validation_failed) {
    failed_critical <- validation_results[
      validation_results$severity == "CRITICAL" &
        !validation_results$passed,
      ,
      drop = FALSE
    ]

    stop(
      "Platform validation failed: ",
      paste(
        paste0(
          failed_critical$check_name,
          "=",
          failed_critical$issue_count
        ),
        collapse = "; "
      ),
      call. = FALSE
    )
  }

  attr(validation_results, "validation_run_id") <- validation_run_id
  attr(validation_results, "validation_outcome") <-
    validation_summary$validation_outcome[[1]]
  attr(validation_results, "validation_summary") <- validation_summary

  validation_results
}

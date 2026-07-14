platform_validation_warning_rows <- function(validation_results) {
  if (nrow(validation_results) == 0) {
    return(validation_results)
  }

  validation_results[
    validation_results$severity == "WARNING" &
      !validation_results$passed,
    ,
    drop = FALSE
  ]
}

platform_validation_error_rows <- function(validation_results) {
  if (nrow(validation_results) == 0) {
    return(validation_results)
  }

  validation_results[
    validation_results$severity %in% c("CRITICAL", "ERROR") &
      !validation_results$passed,
    ,
    drop = FALSE
  ]
}

summarize_platform_validation_results <- function(
  validation_results,
  validation_outcome = NULL,
  skipped_check_count = 0L
) {
  if (is.null(validation_outcome)) {
    warning_rows <- platform_validation_warning_rows(validation_results)
    error_rows <- platform_validation_error_rows(validation_results)

    validation_outcome <- if (nrow(error_rows) > 0) {
      "FAILED"
    } else if (nrow(warning_rows) > 0) {
      "PASSED_WITH_WARNINGS"
    } else {
      "PASSED"
    }
  }

  warning_rows <- platform_validation_warning_rows(validation_results)
  error_rows <- platform_validation_error_rows(validation_results)

  tibble::tibble(
    validation_outcome = validation_outcome,
    total_check_count = nrow(validation_results),
    warning_check_count = nrow(warning_rows),
    warning_issue_count = sum(
      warning_rows$issue_count,
      na.rm = TRUE
    ),
    error_check_count = nrow(error_rows),
    error_issue_count = sum(
      error_rows$issue_count,
      na.rm = TRUE
    ),
    skipped_check_count = as.integer(skipped_check_count)
  )
}

platform_validation_outcome <- function(
  validation_results,
  error_message = NULL
) {
  if (!is.null(error_message) && nzchar(error_message)) {
    if (grepl(
      "timeout|max_statement_time|overall timeout",
      error_message,
      ignore.case = TRUE
    )) {
      return("TIMED_OUT")
    }

    return("FAILED")
  }

  summarize_platform_validation_results(
    validation_results = validation_results
  )$validation_outcome[[1]]
}

platform_validation_should_notify <- function(
  validation_outcome,
  config
) {
  if (validation_outcome %in% c("FAILED", "TIMED_OUT")) {
    return(TRUE)
  }

  notify_on_warning <- config$notifications$validation_notify_on_warning

  if (is.null(notify_on_warning)) {
    notify_on_warning <- TRUE
  }

  identical(validation_outcome, "PASSED_WITH_WARNINGS") &&
    isTRUE(notify_on_warning)
}

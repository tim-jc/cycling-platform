validation_issue_sample_lines <- function(
  details,
  max_rows = 5L,
  max_chars = 180L
) {
  if (is.null(details) || nrow(details) == 0) {
    return(character())
  }

  sample_rows <- utils::head(
    details,
    max_rows
  )

  purrr::map_chr(
    seq_len(nrow(sample_rows)),
    \(row_index) {
      row <- sample_rows[row_index, , drop = FALSE]
      values <- purrr::imap_chr(
        row,
        \(value, name) {
          value <- as.character(value[[1]])

          if (is.na(value)) {
            value <- "NA"
          }

          paste0(
            name,
            "=",
            value
          )
        }
      )

      line <- paste(
        values,
        collapse = ", "
      )

      if (nchar(line) > max_chars) {
        line <- paste0(
          substr(
            line,
            1,
            max_chars - 3L
          ),
          "..."
        )
      }

      paste0(
        "  - ",
        line
      )
    }
  )
}

format_platform_validation_notification_body <- function(
  job_name,
  execution_status,
  validation_outcome,
  completed_at,
  elapsed_seconds,
  validation_summary,
  validation_results,
  validation_run_id = NULL,
  log_location = NULL,
  max_sample_rows = 5L
) {
  warning_rows <- platform_validation_warning_rows(validation_results)
  error_rows <- platform_validation_error_rows(validation_results)

  issue_rows <- dplyr::bind_rows(
    warning_rows,
    error_rows
  )

  body_lines <- c(
    paste0(
      "Job: ",
      job_name
    ),
    paste0(
      "Execution status: ",
      execution_status
    ),
    paste0(
      "Validation outcome: ",
      validation_outcome
    ),
    paste0(
      "Completed: ",
      format(
        completed_at,
        "%Y-%m-%d %H:%M:%S %Z"
      )
    ),
    paste0(
      "Elapsed: ",
      format_platform_duration(elapsed_seconds)
    ),
    "",
    paste0(
      "Warnings: ",
      validation_summary$warning_check_count[[1]],
      " checks · ",
      validation_summary$warning_issue_count[[1]],
      " issues"
    ),
    paste0(
      "Errors: ",
      validation_summary$error_check_count[[1]],
      " checks · ",
      validation_summary$error_issue_count[[1]],
      " issues"
    ),
    paste0(
      "Skipped: ",
      validation_summary$skipped_check_count[[1]],
      " checks"
    )
  )

  if (nrow(issue_rows) > 0) {
    body_lines <- c(
      body_lines,
      "",
      "Checks:"
    )

    for (row_index in seq_len(nrow(issue_rows))) {
      result <- issue_rows[row_index, , drop = FALSE]
      body_lines <- c(
        body_lines,
        paste0(
          result$severity[[1]],
          " ",
          result$check_name[[1]],
          ": ",
          result$issue_count[[1]],
          " issues"
        )
      )

      sample_lines <- validation_issue_sample_lines(
        details = result$details[[1]],
        max_rows = max_sample_rows
      )

      body_lines <- c(
        body_lines,
        sample_lines
      )
    }
  }

  reference_lines <- character()

  if (!is.null(validation_run_id) && !is.na(validation_run_id)) {
    reference_lines <- c(
      reference_lines,
      paste0(
        "Validation run: ",
        validation_run_id
      )
    )
  }

  if (!is.null(log_location) && nzchar(log_location)) {
    reference_lines <- c(
      reference_lines,
      paste0(
        "Log: ",
        log_location
      )
    )
  }

  if (length(reference_lines) > 0) {
    body_lines <- c(
      body_lines,
      "",
      reference_lines
    )
  }

  paste(
    body_lines,
    collapse = "\n"
  )
}

send_platform_validation_notification <- function(
  config,
  job_name,
  execution_status,
  validation_outcome,
  completed_at,
  elapsed_seconds,
  validation_summary,
  validation_results,
  validation_run_id = NULL,
  error_message = NULL
) {
  notifications <- config$notifications

  if (is.null(notifications$enabled) || !isTRUE(notifications$enabled)) {
    return(invisible(FALSE))
  }

  if (!platform_validation_should_notify(
    validation_outcome = validation_outcome,
    config = config
  )) {
    return(invisible(FALSE))
  }

  if (!identical(notifications$provider, "ntfy")) {
    message(
      "Notification provider is not supported: ",
      notifications$provider
    )

    return(invisible(FALSE))
  }

  topic <- notifications$topic

  if (is.null(topic) || !nzchar(topic)) {
    message("Notification topic is not configured.")

    return(invisible(FALSE))
  }

  base_url <- notifications$base_url

  if (is.null(base_url) || !nzchar(base_url)) {
    base_url <- "https://ntfy.sh"
  }

  body <- format_platform_validation_notification_body(
    job_name = job_name,
    execution_status = execution_status,
    validation_outcome = validation_outcome,
    completed_at = completed_at,
    elapsed_seconds = elapsed_seconds,
    validation_summary = validation_summary,
    validation_results = validation_results,
    validation_run_id = validation_run_id,
    log_location = notifications$validation_log_location
  )

  if (!is.null(error_message) && nzchar(error_message)) {
    body <- paste(
      body,
      "",
      paste0(
        "Error: ",
        substr(
          error_message,
          1,
          500
        )
      ),
      sep = "\n"
    )
  }

  priority <- if (validation_outcome %in% c("FAILED", "TIMED_OUT")) {
    "high"
  } else {
    "default"
  }

  tags <- if (validation_outcome %in% c("FAILED", "TIMED_OUT")) {
    "warning"
  } else {
    "warning"
  }

  notification_result <- tryCatch(
    {
      httr2::request(
        paste0(
          sub(
            "/$",
            "",
            base_url
          ),
          "/",
          topic
        )
      ) |>
        httr2::req_headers(
          Title = format_platform_notification_title(
            component = "validation",
            status = validation_outcome
          ),
          Priority = priority,
          Tags = tags
        ) |>
        httr2::req_body_raw(
          body = charToRaw(body),
          type = "text/plain"
        ) |>
        httr2::req_perform()

      TRUE
    },
    error = function(e) {
      message(
        "Validation notification failed: ",
        conditionMessage(e)
      )

      FALSE
    }
  )

  invisible(notification_result)
}

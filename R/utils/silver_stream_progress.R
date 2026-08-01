#' Format a Silver stream rebuild duration
format_silver_stream_duration <- function(seconds) {
  if (length(seconds) == 0L || is.na(seconds) || !is.finite(seconds)) {
    return("unknown")
  }

  seconds <- max(0L, as.integer(round(seconds)))
  hours <- seconds %/% 3600L
  minutes <- (seconds %% 3600L) %/% 60L
  remaining_seconds <- seconds %% 60L

  if (hours > 0L) {
    return(sprintf("%dh %02dm %02ds", hours, minutes, remaining_seconds))
  }
  if (minutes > 0L) {
    return(sprintf("%dm %02ds", minutes, remaining_seconds))
  }
  sprintf("%ds", remaining_seconds)
}

silver_stream_debug_enabled <- function(log_level = "INFO") {
  identical(toupper(log_level %||% "INFO"), "DEBUG")
}

silver_stream_debug <- function(..., log_level = "INFO") {
  if (silver_stream_debug_enabled(log_level)) message(...)
  invisible(NULL)
}

silver_stream_progress_basis <- function(
  expected_rows_processed,
  total_expected_rows,
  activities_processed,
  total_activities,
  completed_batches,
  total_batches
) {
  candidates <- list(
    expected_rows = c(expected_rows_processed, total_expected_rows),
    activities = c(activities_processed, total_activities),
    batches = c(completed_batches, total_batches)
  )
  for (basis in names(candidates)) {
    values <- candidates[[basis]]
    if (length(values) == 2L && all(is.finite(values)) && values[[2]] > 0) {
      return(list(
        basis = basis,
        completed = values[[1]],
        total = values[[2]],
        fraction = min(1, max(0, values[[1]] / values[[2]]))
      ))
    }
  }
  list(basis = "unavailable", completed = 0, total = 0, fraction = NA_real_)
}

calculate_silver_stream_eta <- function(
  elapsed_seconds,
  progress,
  batch_history,
  minimum_rolling_batches = 5L,
  rolling_batches = 10L
) {
  if (is.finite(progress$fraction) && progress$fraction >= 1) {
    return(list(seconds = 0, method = "complete", warmed_up = TRUE))
  }

  overall <- if (is.finite(progress$fraction) && progress$fraction > 0) {
    elapsed_seconds * (1 - progress$fraction) / progress$fraction
  } else {
    NA_real_
  }

  rolling <- NA_real_
  if (nrow(batch_history) >= minimum_rolling_batches && progress$total > progress$completed) {
    recent <- utils::tail(batch_history, rolling_batches)
    units <- switch(
      progress$basis,
      expected_rows = recent$expected_rows,
      activities = recent$activities,
      batches = rep(1, nrow(recent)),
      numeric()
    )
    if (length(units) > 0L && sum(units, na.rm = TRUE) > 0) {
      rolling <- sum(recent$duration_seconds, na.rm = TRUE) /
        sum(units, na.rm = TRUE) * (progress$total - progress$completed)
    }
  }

  list(
    seconds = if (is.finite(rolling)) rolling else overall,
    method = if (is.finite(rolling)) "rolling" else if (is.finite(overall)) "overall" else "calculating",
    warmed_up = is.finite(rolling)
  )
}

silver_stream_throughput_trend <- function(batch_history, window = 10L, tolerance = 0.1) {
  recent <- utils::tail(batch_history, window)
  if (nrow(recent) < 4L) return("calculating")
  halves <- split(seq_len(nrow(recent)), seq_len(nrow(recent)) > floor(nrow(recent) / 2))
  rates <- vapply(halves, function(index) {
    sum(recent$rows_inserted[index]) / sum(recent$duration_seconds[index])
  }, numeric(1))
  if (any(!is.finite(rates)) || rates[[1]] <= 0) return("calculating")
  change <- rates[[2]] / rates[[1]] - 1
  if (change > tolerance) "improving" else if (change < -tolerance) "degrading" else "stable"
}

is_slow_silver_stream_batch <- function(duration_seconds, prior_durations) {
  threshold <- if (length(prior_durations) >= 5L) {
    max(60, 3 * stats::median(prior_durations))
  } else {
    60
  }
  isTRUE(duration_seconds > threshold)
}

format_silver_stream_progress <- function(
  batch_index,
  total_batches,
  activities_processed,
  total_activities,
  expected_rows_processed,
  total_expected_rows,
  rows_inserted,
  rows_deleted,
  elapsed_seconds,
  eta,
  batch_history,
  now = Sys.time()
) {
  progress <- silver_stream_progress_basis(
    expected_rows_processed, total_expected_rows,
    activities_processed, total_activities,
    batch_index, total_batches
  )
  projected <- if (isTRUE(eta$warmed_up) && is.finite(eta$seconds)) {
    format(now + eta$seconds, "%H:%M %Z")
  } else {
    "calculating..."
  }
  eta_text <- if (identical(eta$method, "complete")) {
    "0s"
  } else if (isTRUE(eta$warmed_up)) {
    paste0(format_silver_stream_duration(eta$seconds), " (rolling)")
  } else {
    "calculating..."
  }
  average_rows_per_second <- if (elapsed_seconds > 0) rows_inserted / elapsed_seconds else 0

  expected_rows_line <- if (is.finite(total_expected_rows) && total_expected_rows > 0) {
    sprintf("Expected rows: %s / %s", format(expected_rows_processed, big.mark = ","), format(total_expected_rows, big.mark = ","))
  } else {
    paste0("Expected rows: unavailable (using ", progress$basis, ")")
  }

  paste(c(
    "Silver streams progress",
    sprintf("Batch: %s / %s", format(batch_index, big.mark = ","), format(total_batches, big.mark = ",")),
    sprintf("Progress: %.1f%% (%s)", 100 * progress$fraction, progress$basis),
    sprintf("Activities: %s / %s", format(activities_processed, big.mark = ","), format(total_activities, big.mark = ",")),
    expected_rows_line,
    sprintf("Rows inserted/deleted: %s / %s", format(rows_inserted, big.mark = ","), format(rows_deleted, big.mark = ",")),
    paste0("Elapsed: ", format_silver_stream_duration(elapsed_seconds)),
    paste0("ETA: ", eta_text),
    paste0("Projected finish: ", projected, " (estimate)"),
    sprintf("Throughput: %.1f rows/sec (%s)", average_rows_per_second, silver_stream_throughput_trend(batch_history))
  ), collapse = "\n")
}

format_silver_stream_completion_summary <- function(
  status,
  activities_processed,
  rows_inserted,
  rows_deleted,
  elapsed_seconds,
  batch_history,
  completed_batches = nrow(batch_history),
  total_batches = completed_batches,
  expected_rows_processed = sum(batch_history$expected_rows),
  total_expected_rows = expected_rows_processed,
  failed_batches = 0L,
  error_message = NULL
) {
  average_rows_per_second <- if (elapsed_seconds > 0) rows_inserted / elapsed_seconds else 0
  average_batch <- if (nrow(batch_history) > 0L) mean(batch_history$duration_seconds) else 0
  slow <- if (nrow(batch_history) > 0L) batch_history[order(batch_history$duration_seconds, decreasing = TRUE), , drop = FALSE] else NULL
  slow_lines <- if (!is.null(slow)) {
    head(sprintf(
      "  %s: %s, %s rows",
      slow$batch_index,
      vapply(slow$duration_seconds, format_silver_stream_duration, character(1)),
      format(slow$rows_inserted, big.mark = ",")
    ), 5L)
  } else {
    "  none"
  }
  lines <- c(
    paste("Silver stream rebuild", tolower(status)),
    paste0("Batches completed: ", format(completed_batches, big.mark = ","), " / ", format(total_batches, big.mark = ",")),
    paste0("Activities processed: ", format(activities_processed, big.mark = ",")),
    paste0("Expected rows processed: ", format(expected_rows_processed, big.mark = ","), " / ", format(total_expected_rows, big.mark = ",")),
    paste0("Rows inserted: ", format(rows_inserted, big.mark = ",")),
    paste0("Rows deleted: ", format(rows_deleted, big.mark = ",")),
    paste0("Elapsed: ", format_silver_stream_duration(elapsed_seconds)),
    sprintf("Average throughput: %.1f rows/sec", average_rows_per_second),
    paste0("Average batch: ", format_silver_stream_duration(average_batch)),
    "Slowest batches:",
    slow_lines,
    paste0("Failed batches: ", failed_batches)
  )
  if (!is.null(error_message) && nzchar(error_message)) lines <- c(lines, paste0("Error: ", error_message))
  paste(lines, collapse = "\n")
}

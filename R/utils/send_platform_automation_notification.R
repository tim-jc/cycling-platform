#' Send Platform Automation Notification
#'
#' Send a best-effort ntfy notification for the end-to-end automation wrapper.
#'
#' @param config Platform configuration.
#' @param run_status Overall automation status.
#' @param phase_results Data frame of phase timings and statuses.
#' @param raw_ingestion_summary Optional raw ingestion summary lines.
#' @param silver_transform_summary Optional Silver transform summary lines.
#' @param gold_transform_summary Optional Gold transform summary lines.
#' @param achievement_notification_summary Optional achievement notification
#'   summary lines.
#' @param backup_health_summary Optional off-host backup health lines.
#' @param error_message Optional error message.
#'
#' @return Invisibly returns TRUE when a notification was sent, otherwise FALSE.
notification_count <- function(value, default = 0) {
  if (is.null(value) || length(value) == 0L || is.na(value[[1]])) default else as.numeric(value[[1]])
}

raw_notification_is_quiet <- function(summary) {
  if (is.null(summary$entity_summary) || is.null(summary$reconciliation_totals) ||
      is.null(summary$repair_totals) || is.null(summary$pending_counts)) return(FALSE)

  entities_ok <- nrow(summary$entity_summary) == 0L ||
    all(summary$entity_summary$entity_status == "SUCCESS")
  gear_rows <- summary$entity_summary$entity_name == "gear"
  gear_changed <- any(summary$entity_summary$rows_inserted[gear_rows] > 0) ||
    any(summary$entity_summary$rows_updated[gear_rows] > 0)
  meaningful_reconciliation <- sum(summary$reconciliation_totals[c("NEW", "CHANGED", "MISSING")])

  identical(summary$run_status, "SUCCESS") && entities_ok && !gear_changed &&
    meaningful_reconciliation == 0 && sum(summary$repair_totals) == 0 &&
    sum(summary$pending_counts) == 0
}

silver_notification_is_quiet <- function(summary) {
  runs <- summary$runs
  if (is.null(runs) || nrow(runs) == 0L || any(runs$run_status != "SUCCESS")) return(FALSE)

  non_gear <- runs$entity_name != "gear"
  no_activity_work <- all(runs$activities_planned[non_gear] == 0) &&
    all(runs$activities_completed[non_gear] == 0)
  no_material_rows <- all(runs$rows_inserted[non_gear] == 0) &&
    all(runs$rows_updated[non_gear] == 0) &&
    all(runs$rows_deleted[non_gear] == 0)

  gear <- !non_gear
  no_material_gear_change <- all(runs$rows_updated[gear] == 0) &&
    all(runs$rows_deleted[gear] == 0)

  no_activity_work && no_material_rows && no_material_gear_change
}

gold_notification_is_quiet <- function(summary) {
  runs <- summary$runs
  if (is.null(runs) || nrow(runs) == 0L || any(runs$run_status != "SUCCESS")) return(FALSE)

  timings <- summary$transform_timings
  best <- if (is.null(timings)) NULL else timings$activity_best_efforts
  achievements <- if (is.null(timings)) NULL else timings$activity_achievements

  all(runs$activities_planned == 0) && all(runs$activities_completed == 0) &&
    all(runs$rows_inserted == 0) && all(runs$rows_updated == 0) &&
    all(runs$rows_deleted == 0) &&
    notification_count(best$output_changed_activity_count) == 0 &&
    notification_count(achievements$evaluation_debt_count) == 0 &&
    notification_count(achievements$remaining_invalidated_count) == 0 &&
    (is.null(achievements$invalidation_action) ||
       achievements$invalidation_action %in% c("none", "no_change"))
}

achievement_notifications_are_quiet <- function(summary) {
  queue <- summary$queue_result
  delivery <- summary$delivery_result
  if (is.null(queue) || is.null(delivery)) return(FALSE)

  sum(vapply(queue[c("queued", "already_sent", "already_queued")], notification_count, numeric(1))) == 0 &&
    sum(vapply(delivery[c("attempted", "sent", "failed", "retry")], notification_count, numeric(1))) == 0
}

compact_backup_health_lines <- function(summary) {
  lines <- summary$lines
  if (!identical(summary$freshness_status, "HEALTHY") || length(lines) == 0L) return(lines)

  lines[[1]] <- sub(
    "^Off-host backup: .* — ([^—]+ ✓)$",
    "Off-host backup: \\1",
    lines[[1]]
  )
  lines
}

format_compact_phase_line <- function(phase_results) {
  expected_not_run <- phase_results$phase_name == "deep_validation" &
    phase_results$phase_status == "NOT_RUN"
  ordinary <- phase_results$phase_status == "SUCCESS" | expected_not_run
  if (!all(ordinary)) return(NULL)

  duration_for <- function(names) {
    sum(phase_results$duration_seconds[phase_results$phase_name %in% names], na.rm = TRUE)
  }
  paste0(
    "raw ", format_platform_duration(duration_for("raw_ingestion")),
    " · silver ", format_platform_duration(duration_for("silver_transforms")),
    " · gold ", format_platform_duration(duration_for("gold_transforms")),
    " · checks ", format_platform_duration(duration_for(c("silver_publication_checks", "gold_publication_checks")))
  )
}

format_platform_automation_notification_body <- function(
  run_status,
  phase_results,
  raw_ingestion_summary = NULL,
  silver_transform_summary = NULL,
  gold_transform_summary = NULL,
  achievement_notification_summary = NULL,
  backup_health_summary = NULL,
  error_message = NULL,
  pipeline = "daily-platform",
  window_label = NULL,
  host = platform_execution_host()
) {
  phase_lines <- purrr::pmap_chr(
    phase_results[c("phase_name", "phase_status", "duration_seconds")],
    \(phase_name, phase_status, duration_seconds) format_platform_notification_status_line(
      name = phase_name, status = phase_status, duration_seconds = duration_seconds
    )
  )
  body_lines <- format_platform_execution_context(platform_execution_context(
    pipeline = pipeline,
    status = run_status,
    duration_seconds = sum(phase_results$duration_seconds, na.rm = TRUE),
    host = host
  ))
  if (!is.null(window_label) && nzchar(window_label)) body_lines <- c(body_lines, paste0("Window: ", window_label))

  if (!is.null(raw_ingestion_summary)) {
    raw_lines <- if (identical(run_status, "SUCCESS") && raw_notification_is_quiet(raw_ingestion_summary)) {
      c(
        paste0("SUCCESS · ", format_platform_duration(raw_ingestion_summary$duration_seconds)),
        "No Strava changes · Google Health refresh completed"
      )
    } else {
      c(raw_ingestion_summary$run_line, raw_ingestion_summary$entity_lines,
        raw_ingestion_summary$reconciliation_lines, "", raw_ingestion_summary$pending_line)
    }
    body_lines <- c(body_lines, "", "Raw ingestion:", raw_lines)
  }

  if (!is.null(silver_transform_summary)) {
    silver_lines <- if (identical(run_status, "SUCCESS") && silver_notification_is_quiet(silver_transform_summary)) {
      "SUCCESS · no affected activities"
    } else silver_transform_summary$lines
    body_lines <- c(body_lines, "", "Silver:", silver_lines)
  }

  if (!is.null(gold_transform_summary)) {
    gold_lines <- if (identical(run_status, "SUCCESS") && gold_notification_is_quiet(gold_transform_summary)) {
      "SUCCESS · no candidates · no evaluation debt"
    } else c(gold_transform_summary$lines, gold_transform_summary$orchestration_lines)
    body_lines <- c(body_lines, "", "Gold:", gold_lines)
  }

  if (!is.null(achievement_notification_summary)) {
    if (identical(run_status, "SUCCESS") && achievement_notifications_are_quiet(achievement_notification_summary)) {
      body_lines <- c(body_lines, "", "Achievement notifications: none")
    } else {
      body_lines <- c(body_lines, "", "Achievement notifications:", achievement_notification_summary$lines)
    }
  }

  if (!is.null(backup_health_summary)) {
    body_lines <- c(body_lines, "", "Backup health:", compact_backup_health_lines(backup_health_summary))
  }

  compact_phase <- format_compact_phase_line(phase_results)
  body_lines <- c(body_lines, "", "Phases:", if (is.null(compact_phase)) phase_lines else compact_phase)

  if (!is.null(error_message) && nzchar(error_message)) {
    error_lines <- unlist(strsplit(error_message, "\n", fixed = TRUE), use.names = FALSE)
    error_lines <- error_lines[nzchar(trimws(error_lines))]
    error_summary <- if (length(error_lines) > 8) c(error_lines[[1]], "...", utils::tail(error_lines, 6)) else error_lines
    body_lines <- c(body_lines, "", "Error:", substr(error_summary, 1, 500))
  }

  body_lines
}

send_platform_automation_notification <- function(
  config,
  run_status,
  phase_results,
  raw_ingestion_summary = NULL,
  silver_transform_summary = NULL,
  gold_transform_summary = NULL,
  achievement_notification_summary = NULL,
  backup_health_summary = NULL,
  error_message = NULL,
  pipeline = "daily-platform",
  component = "automation",
  window_label = NULL
) {
  notifications <- config$notifications

  if (is.null(notifications$enabled) || !isTRUE(notifications$enabled)) {
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

  body_lines <- format_platform_automation_notification_body(
    run_status = run_status,
    phase_results = phase_results,
    raw_ingestion_summary = raw_ingestion_summary,
    silver_transform_summary = silver_transform_summary,
    gold_transform_summary = gold_transform_summary,
    achievement_notification_summary = achievement_notification_summary,
    backup_health_summary = backup_health_summary,
    error_message = error_message,
    pipeline = pipeline,
    window_label = window_label
  )

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
            component = component,
            status = run_status
          ),
          Priority = if (identical(run_status, "FAILED")) "high" else "default",
          Tags = if (identical(run_status, "FAILED")) "warning" else "white_check_mark"
        ) |>
        httr2::req_body_raw(
          body = charToRaw(
            paste(
              body_lines,
              collapse = "\n"
            )
          ),
          type = "text/plain"
        ) |>
        httr2::req_perform()

      TRUE
    },
    error = function(e) {
      message(
        "Automation notification failed: ",
        conditionMessage(e)
      )

      FALSE
    }
  )

  invisible(notification_result)
}

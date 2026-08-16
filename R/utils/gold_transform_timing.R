# Lightweight wall-clock timing helpers for Gold transforms.

gold_timing_now <- function() {
  unname(proc.time()[["elapsed"]])
}

gold_elapsed_seconds <- function(started_at, completed_at = gold_timing_now()) {
  max(0, as.numeric(completed_at) - as.numeric(started_at))
}

gold_transform_timing <- function(
  entity_name,
  setup_seconds = NULL,
  candidate_discovery_seconds = NULL,
  source_preparation_seconds = NULL,
  processing_seconds = NULL,
  finalisation_seconds = NULL,
  total_seconds = NULL
) {
  list(
    entity_name = entity_name,
    setup_seconds = setup_seconds,
    candidate_discovery_seconds = candidate_discovery_seconds,
    source_preparation_seconds = source_preparation_seconds,
    processing_seconds = processing_seconds,
    finalisation_seconds = finalisation_seconds,
    total_seconds = total_seconds
  )
}

gold_timing_value <- function(value) {
  if (is.null(value) || length(value) == 0L || is.na(value[[1]])) {
    return(NULL)
  }

  as.numeric(value[[1]])
}

gold_transform_timing_accounted_seconds <- function(timing) {
  values <- c(
    gold_timing_value(timing$setup_seconds),
    gold_timing_value(timing$candidate_discovery_seconds),
    gold_timing_value(timing$source_preparation_seconds),
    gold_timing_value(timing$processing_seconds),
    gold_timing_value(timing$finalisation_seconds)
  )

  sum(values, na.rm = TRUE)
}

format_gold_transform_timing <- function(timing) {
  if (is.null(timing)) {
    return(character())
  }

  labels <- c(
    setup_seconds = "setup",
    candidate_discovery_seconds = "discovery",
    source_preparation_seconds = "source preparation",
    processing_seconds = "processing",
    finalisation_seconds = "finalisation",
    total_seconds = "total"
  )

  parts <- character()

  for (field in names(labels)) {
    value <- gold_timing_value(timing[[field]])

    if (!is.null(value)) {
      parts <- c(
        parts,
        paste0(labels[[field]], " ", format_platform_duration(value))
      )
    }
  }

  paste(parts, collapse = " · ")
}

log_gold_transform_timing <- function(timing) {
  message(
    "Gold timing ",
    timing$entity_name,
    ": ",
    format_gold_transform_timing(timing)
  )

  invisible(timing)
}

attach_gold_transform_timing <- function(result, timing) {
  attr(result, "gold_transform_timing") <- timing
  result
}

format_gold_transform_summary_line <- function(
  entity_name,
  run_status,
  run_mode,
  activities_completed,
  activities_planned,
  rows_inserted,
  rows_deleted,
  failed_batch_count = 0L,
  timing = NULL,
  recorded_duration_seconds = NULL
) {
  activity_label <- if (identical(entity_name, "activity_achievements")) {
    paste0(
      "candidates evaluated ",
      activities_completed,
      "/",
      activities_planned
    )
  } else {
    paste0("candidates ", activities_completed, "/", activities_planned)
  }

  timing_text <- format_gold_transform_timing(timing)

  if (
    length(timing_text) == 0L &&
      !is.null(recorded_duration_seconds)
  ) {
    timing_text <- paste0(
      "recorded processing/finalisation ",
      format_platform_duration(recorded_duration_seconds)
    )
  }

  parts <- c(
    paste0(entity_name, ": ", run_status, " · ", toupper(run_mode)),
    activity_label,
    paste0("rows changed +", rows_inserted, " / -", rows_deleted),
    paste0("failed batches ", failed_batch_count)
  )

  if (identical(entity_name, "activity_best_efforts") && !is.null(timing)) {
    discovery_mode <- timing$discovery_mode
    affected_count <- timing$upstream_affected_count
    output_changed_count <- timing$output_changed_activity_count
    if (!is.null(affected_count) && !is.na(affected_count)) {
      parts <- append(parts, paste0("affected ", affected_count), after = 1L)
    }
    if (!is.null(discovery_mode) && nzchar(discovery_mode)) {
      discovery_label <- if (identical(discovery_mode, "skipped")) {
        "discovery skipped ✓"
      } else {
        paste0("discovery ", discovery_mode)
      }
      parts <- append(parts, discovery_label, after = min(2L, length(parts)))
    }
    if (!is.null(output_changed_count) && !is.na(output_changed_count)) {
      parts <- c(parts, paste0("outputs changed ", output_changed_count))
    }
  }

  if (identical(entity_name, "activity_achievements") && !is.null(timing)) {
    if (!is.null(timing$evaluation_debt_count) && !is.na(timing$evaluation_debt_count)) {
      parts <- append(
        parts,
        paste0("evaluation debt ", timing$evaluation_debt_count),
        after = 1L
      )
    }
    if (!is.null(timing$candidate_mode) && nzchar(timing$candidate_mode)) {
      parts <- c(parts, paste0("candidate mode ", timing$candidate_mode))
    }
    if (!is.null(timing$zero_achievement_evaluations) &&
        timing$zero_achievement_evaluations > 0L) {
      parts <- c(
        parts,
        paste0("zero-achievement evaluations ", timing$zero_achievement_evaluations)
      )
    }
    if (!is.null(timing$evaluation_state_rows_written) &&
        timing$evaluation_state_rows_written > 0L) {
      parts <- c(
        parts,
        paste0("state CURRENT ", timing$evaluation_state_rows_written)
      )
    }
  }

  if (length(timing_text) > 0L && nzchar(timing_text)) {
    return(paste0(
      paste(parts, collapse = " · "),
      "\n  timing: ",
      timing_text
    ))
  }

  paste(parts, collapse = " · ")
}

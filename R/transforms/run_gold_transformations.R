#' Run Gold Transformations
#'
#' Execute production Gold transformations that are safe for daily automation.
#' Historical backfills remain explicit manual operations.
#'
#' @param connection Database connection.
#' @param config Platform configuration.
#' @param mode Gold run mode. `daily` is the normal automation mode.
#'
#' @return Invisibly returns a list containing per-transform wall-clock timings.
run_gold_transformations <- function(
  connection,
  config = list(),
  gold_change_context = NULL,
  mode = c(
    "daily",
    "repair"
  )
) {
  mode <- match.arg(mode)

  context_validation <- validate_gold_change_context(gold_change_context)
  best_effort_activity_ids <- NULL
  if (identical(mode, "daily") && isTRUE(context_validation$trusted)) {
    best_effort_activity_ids <- gold_best_effort_affected_ids(
      context_validation$context
    )
  }
  message(
    "Gold change context: status=", context_validation$status,
    "; trusted=", isTRUE(context_validation$trusted),
    "; best-effort affected=",
    if (is.null(best_effort_activity_ids)) "fallback" else length(best_effort_activity_ids),
    if (!is.null(context_validation$reason) && !is.na(context_validation$reason)) {
      paste0("; reason=", context_validation$reason)
    } else ""
  )

  best_effort_result <- rebuild_gold_activity_best_efforts(
    connection = connection,
    config = config,
    mode = mode,
    activity_ids = best_effort_activity_ids
  )

  best_effort_metadata <- attr(best_effort_result, "gold_best_effort_result")

  achievement_result <- rebuild_gold_activity_achievements(
    connection = connection,
    config = config,
    gold_change_context = gold_change_context,
    best_effort_changed_activity_ids =
      best_effort_metadata$output_changed_activity_ids,
    mode = mode
  )

  best_effort_timing <- attr(
      best_effort_result,
      "gold_transform_timing"
  )
  best_effort_timing$discovery_mode <- best_effort_metadata$discovery_mode
  best_effort_timing$upstream_affected_count <- best_effort_metadata$upstream_affected_count
  best_effort_timing$output_changed_activity_count <- length(
    best_effort_metadata$output_changed_activity_ids
  )

  invisible(list(
    activity_best_efforts = best_effort_timing,
    activity_achievements = attr(
      achievement_result,
      "gold_transform_timing"
    )
  ))
}

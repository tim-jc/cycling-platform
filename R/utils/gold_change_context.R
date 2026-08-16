# In-memory Silver-to-Gold change context used by the daily pipeline.

gold_change_context_columns <- function() {
  c(
    "activity_id",
    "change_type",
    "activity_date_before",
    "activity_date_after",
    "silver_activities_changed",
    "silver_streams_changed",
    "power_classification_changed",
    "dependency_start_date"
  )
}

empty_gold_change_rows <- function() {
  data.frame(
    activity_id = bit64::as.integer64(character()),
    change_type = character(),
    activity_date_before = as.Date(character()),
    activity_date_after = as.Date(character()),
    silver_activities_changed = logical(),
    silver_streams_changed = logical(),
    power_classification_changed = logical(),
    dependency_start_date = as.Date(character())
  )
}

new_gold_change_context <- function(
  status = c("COMPLETE", "UNAVAILABLE", "UNTRUSTED"),
  activities = empty_gold_change_rows(),
  raw_run_id = NA_integer_,
  silver_transform_run_ids = integer(),
  reason = NA_character_
) {
  status <- match.arg(status)

  if (!is.data.frame(activities)) {
    stop("Gold change context activities must be a data frame.", call. = FALSE)
  }

  missing_columns <- setdiff(gold_change_context_columns(), names(activities))
  if (length(missing_columns) > 0L) {
    stop(
      "Gold change context is missing columns: ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }

  activities <- activities[, gold_change_context_columns(), drop = FALSE]
  activities$activity_id <- bit64::as.integer64(as.character(activities$activity_id))
  activities$activity_date_before <- as.Date(activities$activity_date_before)
  activities$activity_date_after <- as.Date(activities$activity_date_after)
  activities$dependency_start_date <- as.Date(activities$dependency_start_date)
  flag_columns <- c(
    "silver_activities_changed",
    "silver_streams_changed",
    "power_classification_changed"
  )
  activities[flag_columns] <- lapply(activities[flag_columns], as.logical)

  if (any(is.na(activities$activity_id))) {
    stop("Gold change context contains a missing activity_id.", call. = FALSE)
  }
  if (anyDuplicated(as.character(activities$activity_id))) {
    stop("Gold change context contains duplicate activity IDs.", call. = FALSE)
  }
  if (anyNA(activities[flag_columns])) {
    stop("Gold change context contains a missing material-change flag.", call. = FALSE)
  }
  if (any(!activities$change_type %in% c("insert", "update", "delete_or_exclude"))) {
    stop("Gold change context contains an invalid change_type.", call. = FALSE)
  }

  expected_dependency_date <- as.Date(vapply(
    seq_len(nrow(activities)),
    function(index) {
      dates <- c(
        activities$activity_date_before[[index]],
        activities$activity_date_after[[index]]
      )
      dates <- dates[!is.na(dates)]
      if (length(dates) == 0L) NA_character_ else as.character(min(dates))
    },
    character(1)
  ))
  inconsistent_dates <- !is.na(expected_dependency_date) &
    activities$dependency_start_date != expected_dependency_date
  inconsistent_dates[is.na(inconsistent_dates)] <- FALSE
  if (any(inconsistent_dates)) {
    stop("Gold change context contains inconsistent dependency dates.", call. = FALSE)
  }

  structure(
    list(
      status = status,
      activities = activities,
      raw_run_id = raw_run_id,
      silver_transform_run_ids = silver_transform_run_ids,
      reason = reason
    ),
    class = "gold_change_context"
  )
}

unavailable_gold_change_context <- function(reason) {
  new_gold_change_context(status = "UNAVAILABLE", reason = reason)
}

validate_gold_change_context <- function(context) {
  if (is.null(context)) {
    return(list(trusted = FALSE, status = "UNAVAILABLE", reason = "context missing"))
  }
  if (!inherits(context, "gold_change_context")) {
    return(list(trusted = FALSE, status = "UNTRUSTED", reason = "context type is invalid"))
  }

  checked <- tryCatch(
    new_gold_change_context(
      status = context$status,
      activities = context$activities,
      raw_run_id = context$raw_run_id,
      silver_transform_run_ids = context$silver_transform_run_ids,
      reason = context$reason
    ),
    error = identity
  )
  if (inherits(checked, "error")) {
    return(list(
      trusted = FALSE,
      status = "UNTRUSTED",
      reason = conditionMessage(checked)
    ))
  }

  list(
    trusted = identical(checked$status, "COMPLETE"),
    status = checked$status,
    reason = checked$reason,
    context = checked
  )
}

gold_best_effort_affected_ids <- function(context) {
  validation <- validate_gold_change_context(context)
  if (!isTRUE(validation$trusted)) return(NULL)

  rows <- validation$context$activities
  affected <- rows$change_type %in% c("insert", "delete_or_exclude") |
    rows$silver_streams_changed |
    rows$power_classification_changed

  unique(rows$activity_id[affected])
}

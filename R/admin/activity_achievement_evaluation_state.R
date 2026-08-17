ensure_activity_achievement_evaluation_state <- function(
  connection,
  sql_file = file.path("sql", "admin", "090_create_activity_achievement_evaluation_state.sql")
) {
  execute_sql_file(sql_file = sql_file, connection = connection)
}

fetch_achievement_activity_base <- function(connection) {
  DBI::dbGetQuery(
    connection,
    "SELECT activity_id, start_date_local AS activity_date_local
       FROM cycling_platform_silver.activities
      ORDER BY start_date_local, activity_id"
  )
}

achievement_input_signature <- function(
  activity_id,
  activity_date_local,
  source_rows,
  calculation_version,
  best_effort_calculation_version
) {
  activity_id <- as.character(activity_id)
  rows <- source_rows[
    as.character(source_rows$activity_id) == activity_id,
    c(
      "activity_date",
      "achievement_type",
      "metric_name",
      "duration_seconds",
      "metric_value"
    ),
    drop = FALSE
  ]
  if (nrow(rows) > 0L) {
    rows <- rows[order(
      rows$activity_date,
      rows$achievement_type,
      rows$metric_name,
      rows$duration_seconds,
      rows$metric_value
    ), , drop = FALSE]
    rows[] <- lapply(rows, function(value) {
      value <- as.character(value)
      value[is.na(value)] <- "<NA>"
      value
    })
    rownames(rows) <- NULL
  }

  digest::digest(
    list(
      activity_id = activity_id,
      activity_date_local = if (is.na(activity_date_local)) "<NA>" else as.character(activity_date_local),
      calculation_version = calculation_version,
      best_effort_calculation_version = best_effort_calculation_version,
      achievement_inputs = rows
    ),
    algo = "sha256"
  )
}

build_achievement_evaluation_inputs <- function(
  activity_base,
  source_rows,
  calculation_version,
  best_effort_calculation_version
) {
  if (nrow(activity_base) == 0L) {
    return(data.frame(
      activity_id = bit64::as.integer64(character()),
      activity_date_local = as.Date(character()),
      input_signature = character()
    ))
  }

  data.frame(
    activity_id = bit64::as.integer64(as.character(activity_base$activity_id)),
    activity_date_local = as.Date(activity_base$activity_date_local),
    input_signature = vapply(seq_len(nrow(activity_base)), function(index) {
      achievement_input_signature(
        activity_id = activity_base$activity_id[[index]],
        activity_date_local = activity_base$activity_date_local[[index]],
        source_rows = source_rows,
        calculation_version = calculation_version,
        best_effort_calculation_version = best_effort_calculation_version
      )
    }, character(1))
  )
}

achievement_evaluation_state_summary <- function(connection, calculation_version) {
  DBI::dbGetQuery(
    connection,
    "SELECT
         (SELECT COUNT(*) FROM cycling_platform_silver.activities) AS silver_count,
         COUNT(state.activity_id) AS state_count,
         COALESCE(SUM(state.evaluation_status = 'CURRENT'), 0) AS current_count,
         COALESCE(SUM(state.evaluation_status = 'INVALIDATED'), 0) AS invalidated_count,
         (SELECT COUNT(DISTINCT calculation_version)
            FROM cycling_platform_admin.activity_achievement_evaluation_state) AS version_count,
         (SELECT COUNT(*)
            FROM cycling_platform_admin.activity_achievement_evaluation_state
           WHERE calculation_version <> ?) AS other_version_count
       FROM cycling_platform_silver.activities activities
       LEFT JOIN cycling_platform_admin.activity_achievement_evaluation_state state
         ON state.activity_id = activities.activity_id
        AND state.calculation_version = ?",
    params = list(calculation_version, calculation_version)
  )
}

achievement_evaluation_state_initialized <- function(summary) {
  summary$silver_count[[1]] > 0 &&
    summary$state_count[[1]] == summary$silver_count[[1]] &&
    summary$current_count[[1]] == summary$silver_count[[1]] &&
    summary$invalidated_count[[1]] == 0
}

achievement_evaluation_version_requires_rebuild <- function(summary) {
  summary$other_version_count[[1]] > 0 &&
    summary$state_count[[1]] < summary$silver_count[[1]]
}

achievement_fact_version_requires_rebuild <- function(connection, calculation_version) {
  DBI::dbGetQuery(
    connection,
    "SELECT COUNT(*) AS stale_count
       FROM cycling_platform_gold.activity_achievements
      WHERE calculation_version IS NULL OR calculation_version <> ?",
    params = list(calculation_version)
  )$stale_count[[1]] > 0
}

achievement_candidate_policy <- function(
  mode,
  state_initialized,
  context_trusted,
  context_has_changes,
  explicit_activity_ids = FALSE
) {
  safe_state_daily <- identical(mode, "daily") && isTRUE(state_initialized) &&
    isTRUE(context_trusted) && !isTRUE(context_has_changes) &&
    !isTRUE(explicit_activity_ids)
  list(
    use_state_daily = safe_state_daily,
    candidate_mode = if (safe_state_daily) {
      "evaluation_state"
    } else if (identical(mode, "backfill")) {
      "rebuild"
    } else if (identical(mode, "repair")) {
      "repair"
    } else {
      "conservative_fallback"
    }
  )
}

achievement_history_boundary <- function(connection, calculation_version) {
  result <- DBI::dbGetQuery(
    connection,
    "SELECT activity_date_local, activity_id
       FROM cycling_platform_admin.activity_achievement_evaluation_state
      WHERE calculation_version = ?
        AND evaluation_status = 'CURRENT'
        AND source_present = 1
        AND activity_date_local IS NOT NULL
      ORDER BY activity_date_local DESC, activity_id DESC
      LIMIT 1",
    params = list(calculation_version)
  )
  if (nrow(result) == 0L) {
    return(list(activity_date_local = as.Date(NA), activity_id = NA_character_))
  }
  list(
    activity_date_local = as.Date(result$activity_date_local[[1]]),
    activity_id = as.character(result$activity_id[[1]])
  )
}

plan_achievement_daily_invalidation <- function(
  context_validation,
  best_effort_changed_activity_ids,
  history_boundary
) {
  if (!isTRUE(context_validation$trusted)) {
    context_reason <- if (
      !is.null(context_validation$reason) &&
        !is.na(context_validation$reason) && nzchar(context_validation$reason)
    ) {
      paste0(": ", context_validation$reason)
    } else {
      ""
    }
    return(list(
      action = "fallback",
      direct_activity_ids = character(),
      dependency_start_date = as.Date(NA),
      invalidation_reason = NA_character_,
      reason = paste0(
        "Gold change context is ", context_validation$status, context_reason
      )
    ))
  }

  rows <- context_validation$context$activities
  best_effort_changed_activity_ids <- unique(as.character(best_effort_changed_activity_ids))
  if (nrow(rows) == 0L) {
    if (length(best_effort_changed_activity_ids) > 0L) {
      return(list(
        action = "fallback",
        direct_activity_ids = character(),
        dependency_start_date = as.Date(NA),
        invalidation_reason = NA_character_,
        reason = "Best-effort outputs changed without corresponding Silver change rows."
      ))
    }
    return(list(
      action = "no_change",
      direct_activity_ids = character(),
      dependency_start_date = as.Date(NA),
      invalidation_reason = NA_character_,
      reason = NA_character_
    ))
  }

  ids <- as.character(rows$activity_id)
  deletion <- rows$change_type == "delete_or_exclude"
  if (any(deletion)) {
    return(list(
      action = "fallback",
      direct_activity_ids = ids[deletion],
      dependency_start_date = as.Date(NA),
      invalidation_reason = NA_character_,
      reason = "Canonical deletion/exclusion propagation is not authoritative."
    ))
  }

  relevant <- rows$change_type == "insert" |
    rows$silver_activities_changed |
    rows$power_classification_changed |
    ids %in% best_effort_changed_activity_ids
  rows <- rows[relevant, , drop = FALSE]
  ids <- as.character(rows$activity_id)
  if (nrow(rows) == 0L) {
    return(list(
      action = "no_change",
      direct_activity_ids = character(),
      dependency_start_date = as.Date(NA),
      invalidation_reason = NA_character_,
      reason = NA_character_
    ))
  }

  dependency_dates <- as.Date(rows$dependency_start_date)
  if (any(is.na(dependency_dates))) {
    return(list(
      action = "fallback",
      direct_activity_ids = ids,
      dependency_start_date = as.Date(NA),
      invalidation_reason = NA_character_,
      reason = "Achievement-relevant change has no dependency start date."
    ))
  }

  after_dates <- as.Date(rows$activity_date_after)
  is_insert <- rows$change_type == "insert"
  boundary_date <- as.Date(history_boundary$activity_date_local)
  boundary_id <- history_boundary$activity_id
  after_boundary <- if (is.na(boundary_date)) {
    rep(TRUE, nrow(rows))
  } else {
    after_dates > boundary_date |
      (after_dates == boundary_date &
        bit64::as.integer64(ids) > bit64::as.integer64(boundary_id))
  }
  pure_latest_append <- all(is_insert & !is.na(after_dates) & after_boundary)
  if (pure_latest_append) {
    ordered <- order(after_dates, bit64::as.integer64(ids))
    return(list(
      action = "latest_append",
      direct_activity_ids = ids[ordered],
      dependency_start_date = min(dependency_dates),
      invalidation_reason = NA_character_,
      reason = NA_character_
    ))
  }

  dates_changed <- !is.na(rows$activity_date_before) & !is.na(rows$activity_date_after) &
    as.Date(rows$activity_date_before) != as.Date(rows$activity_date_after)
  reason <- if (any(dates_changed)) {
    "DATE_CHANGE"
  } else if (any(is_insert)) {
    "HISTORICAL_INSERT"
  } else if (any(rows$power_classification_changed)) {
    "POWER_ELIGIBILITY_CHANGE"
  } else if (any(ids %in% best_effort_changed_activity_ids)) {
    "BEST_EFFORT_CHANGE"
  } else {
    "HISTORICAL_ACTIVITY_CHANGE"
  }
  list(
    action = "historical_closure",
    direct_activity_ids = ids,
    dependency_start_date = min(dependency_dates),
    invalidation_reason = reason,
    reason = NA_character_
  )
}

achievement_unexpected_debt_ids <- function(daily_plan, debt_ids) {
  debt_ids <- unique(as.character(debt_ids))
  if (identical(daily_plan$action, "latest_append")) {
    return(setdiff(debt_ids, as.character(daily_plan$direct_activity_ids)))
  }
  debt_ids
}

get_achievement_closure_activity_ids <- function(connection, dependency_start_date) {
  result <- DBI::dbGetQuery(
    connection,
    "SELECT activity_id, start_date_local AS activity_date_local
       FROM cycling_platform_silver.activities
      WHERE start_date_local >= ?
      ORDER BY start_date_local, activity_id",
    params = list(as.Date(dependency_start_date))
  )
  achievement_closure_ids_from_activity_base(result, dependency_start_date)
}

achievement_closure_ids_from_activity_base <- function(
  activity_base,
  dependency_start_date
) {
  if (nrow(activity_base) == 0L) return(character())
  activity_base$activity_date_local <- as.Date(activity_base$activity_date_local)
  activity_base <- activity_base[
    !is.na(activity_base$activity_date_local) &
      activity_base$activity_date_local >= as.Date(dependency_start_date),
    ,
    drop = FALSE
  ]
  activity_base <- activity_base[
    order(
      activity_base$activity_date_local,
      bit64::as.integer64(as.character(activity_base$activity_id))
    ),
    ,
    drop = FALSE
  ]
  as.character(activity_base$activity_id)
}

achievement_activity_dates <- function(connection, activity_ids) {
  activity_ids <- unique(as.character(activity_ids))
  if (length(activity_ids) == 0L) return(as.Date(character()))
  result <- DBI::dbGetQuery(
    connection,
    paste0(
      "SELECT activity_id, start_date_local FROM cycling_platform_silver.activities ",
      "WHERE activity_id IN (", format_activity_id_filter(activity_ids), ")"
    )
  )
  stats::setNames(as.Date(result$start_date_local), as.character(result$activity_id))
}

mark_achievement_evaluation_closure_invalidated <- function(
  connection,
  calculation_version,
  dependency_start_date,
  invalidation_reason
) {
  allowed <- c(
    "HISTORICAL_ACTIVITY_CHANGE", "HISTORICAL_INSERT", "BEST_EFFORT_CHANGE",
    "POWER_ELIGIBILITY_CHANGE", "DATE_CHANGE", "REPAIR"
  )
  if (!invalidation_reason %in% allowed) {
    stop("Unknown achievement invalidation reason.", call. = FALSE)
  }
  DBI::dbExecute(
    connection,
    "UPDATE cycling_platform_admin.activity_achievement_evaluation_state
        SET evaluation_status = 'INVALIDATED',
            invalidation_reason = ?,
            invalidated_at = UTC_TIMESTAMP()
      WHERE calculation_version = ?
        AND source_present = 1
        AND activity_date_local >= ?",
    params = list(
      invalidation_reason,
      calculation_version,
      as.Date(dependency_start_date)
    )
  )
}

get_achievement_invalidated_count <- function(connection, calculation_version) {
  as.integer(DBI::dbGetQuery(
    connection,
    "SELECT COUNT(*) AS invalidated_count
       FROM cycling_platform_admin.activity_achievement_evaluation_state
      WHERE calculation_version = ?
        AND evaluation_status = 'INVALIDATED'",
    params = list(calculation_version)
  )$invalidated_count[[1]])
}

get_achievement_evaluation_debt_ids <- function(
  connection,
  calculation_version
) {
  result <- DBI::dbGetQuery(
    connection,
    "WITH fact_count AS (
       SELECT activity_id, COUNT(*) AS achievement_count
         FROM cycling_platform_gold.activity_achievements
        WHERE calculation_version = ?
        GROUP BY activity_id
     )
     SELECT activities.activity_id
       FROM cycling_platform_silver.activities activities
       LEFT JOIN cycling_platform_admin.activity_achievement_evaluation_state state
         ON state.activity_id = activities.activity_id
        AND state.calculation_version = ?
       LEFT JOIN fact_count
         ON fact_count.activity_id = activities.activity_id
      WHERE state.activity_id IS NULL
         OR state.evaluation_status = 'INVALIDATED'
         OR state.evaluated_at IS NULL
         OR state.input_signature IS NULL
         OR state.input_signature = ''
         OR state.achievement_count <> COALESCE(fact_count.achievement_count, 0)
      ORDER BY activities.start_date_local, activities.activity_id",
    params = list(calculation_version, calculation_version)
  )
  as.character(result$activity_id)
}

get_achievement_signature_mismatch_ids <- function(
  connection,
  evaluation_inputs,
  calculation_version,
  best_effort_calculation_version
) {
  if (nrow(evaluation_inputs) == 0L) return(character())
  state <- DBI::dbGetQuery(
    connection,
    "SELECT activity_id, input_signature, evaluation_status,
            source_best_effort_calculation_version
       FROM cycling_platform_admin.activity_achievement_evaluation_state
      WHERE calculation_version = ?",
    params = list(calculation_version)
  )

  achievement_signature_mismatch_ids(
    evaluation_inputs = evaluation_inputs,
    state = state,
    best_effort_calculation_version = best_effort_calculation_version
  )
}

achievement_signature_mismatch_ids <- function(
  evaluation_inputs,
  state,
  best_effort_calculation_version
) {
  if (nrow(evaluation_inputs) == 0L) return(character())
  matched <- match(as.character(evaluation_inputs$activity_id), as.character(state$activity_id))
  missing <- is.na(matched)
  signature_mismatch <- !missing &
    evaluation_inputs$input_signature != state$input_signature[matched]
  status_invalid <- !missing & state$evaluation_status[matched] != "CURRENT"
  source_version_stale <- !missing & (
    is.na(state$source_best_effort_calculation_version[matched]) |
      state$source_best_effort_calculation_version[matched] != best_effort_calculation_version
  )
  as.character(evaluation_inputs$activity_id[
    missing | signature_mismatch | status_invalid | source_version_stale
  ])
}

get_orphan_achievement_fact_ids <- function(connection, calculation_version) {
  result <- DBI::dbGetQuery(
    connection,
    "SELECT DISTINCT facts.activity_id
       FROM cycling_platform_gold.activity_achievements facts
       LEFT JOIN cycling_platform_silver.activities activities
         ON activities.activity_id = facts.activity_id
      WHERE facts.calculation_version = ?
        AND activities.activity_id IS NULL
      ORDER BY facts.activity_id",
    params = list(calculation_version)
  )
  as.character(result$activity_id)
}

achievement_fact_counts <- function(achievements, activity_ids) {
  activity_ids <- as.character(activity_ids)
  counts <- stats::setNames(rep(0L, length(activity_ids)), activity_ids)
  if (nrow(achievements) > 0L) {
    table_counts <- table(as.character(achievements$activity_id))
    counts[names(table_counts)] <- as.integer(table_counts)
  }
  counts
}

upsert_achievement_evaluation_state <- function(
  connection,
  activity_ids,
  evaluation_inputs,
  achievement_counts,
  calculation_version,
  best_effort_calculation_version,
  source_transform_run_id
) {
  activity_ids <- as.character(activity_ids)
  for (activity_id in activity_ids) {
    input <- evaluation_inputs[
      as.character(evaluation_inputs$activity_id) == activity_id,
      ,
      drop = FALSE
    ]
    if (nrow(input) != 1L) {
      stop("Missing achievement evaluation input for activity ", activity_id, call. = FALSE)
    }
    DBI::dbExecute(
      connection,
      "INSERT INTO cycling_platform_admin.activity_achievement_evaluation_state (
         activity_id, calculation_version, activity_date_local, source_present,
         input_signature, evaluation_status, achievement_count,
         source_best_effort_calculation_version, source_transform_run_id,
         invalidation_reason, invalidated_at, evaluated_at
       ) VALUES (?, ?, ?, 1, ?, 'CURRENT', ?, ?, ?, NULL, NULL, UTC_TIMESTAMP())
       ON DUPLICATE KEY UPDATE
         activity_date_local = VALUES(activity_date_local),
         source_present = 1,
         input_signature = VALUES(input_signature),
         evaluation_status = 'CURRENT',
         achievement_count = VALUES(achievement_count),
         source_best_effort_calculation_version = VALUES(source_best_effort_calculation_version),
         source_transform_run_id = VALUES(source_transform_run_id),
         invalidation_reason = NULL,
         invalidated_at = NULL,
         evaluated_at = VALUES(evaluated_at)",
      params = list(
        activity_id,
        calculation_version,
        input$activity_date_local[[1]],
        input$input_signature[[1]],
        as.integer(achievement_counts[[activity_id]]),
        best_effort_calculation_version,
        if (is.na(source_transform_run_id)) NA else as.character(source_transform_run_id)
      )
    )
  }
  length(activity_ids)
}

audit_achievement_evaluation_candidates <- function(
  connection,
  calculation_version
) {
  conservative <- get_activity_achievement_candidate_ids(
    connection = connection,
    mode = "daily",
    calculation_version = calculation_version
  )
  state_driven <- get_achievement_evaluation_debt_ids(
    connection = connection,
    calculation_version = calculation_version
  )
  list(
    conservative_candidate_count = length(conservative),
    state_candidate_count = length(state_driven),
    selected_only_by_conservative = setdiff(conservative, state_driven),
    selected_only_by_state = setdiff(state_driven, conservative)
  )
}

fetch_achievement_fact_semantic_rows <- function(connection) {
  DBI::dbGetQuery(
    connection,
    "SELECT activity_achievement_key, activity_id, achievement_type,
            metric_name, duration_seconds, comparison_scope,
            comparison_period_start, comparison_period_end, achievement_rank,
            metric_value, previous_best_value, previous_best_activity_id,
            previous_best_date, days_since_previous_best, achievement_title,
            achievement_detail, calculation_status, calculation_version
       FROM cycling_platform_gold.activity_achievements
      ORDER BY activity_achievement_key"
  )
}

achievement_fact_semantic_signature <- function(connection) {
  rows <- fetch_achievement_fact_semantic_rows(connection)
  rows[] <- lapply(rows, function(value) {
    value <- as.character(value)
    value[is.na(value)] <- "<NA>"
    value
  })
  rownames(rows) <- NULL
  digest::digest(rows, algo = "sha256")
}

compare_achievement_fact_semantics <- function(before, after) {
  key <- "activity_achievement_key"
  before_keys <- as.character(before[[key]])
  after_keys <- as.character(after[[key]])
  shared <- intersect(before_keys, after_keys)
  semantic_columns <- setdiff(intersect(names(before), names(after)), key)
  normalise <- function(rows) {
    rows[] <- lapply(rows, function(value) {
      value <- as.character(value)
      value[is.na(value)] <- "<NA>"
      value
    })
    rows
  }
  before_shared <- normalise(
    before[match(shared, before_keys), semantic_columns, drop = FALSE]
  )
  after_shared <- normalise(
    after[match(shared, after_keys), semantic_columns, drop = FALSE]
  )
  mismatched <- if (length(shared) == 0L) {
    character()
  } else {
    different <- vapply(seq_along(shared), function(index) {
      !identical(
        as.list(before_shared[index, , drop = FALSE]),
        as.list(after_shared[index, , drop = FALSE])
      )
    }, logical(1))
    shared[different]
  }
  only_before <- setdiff(before_keys, after_keys)
  only_after <- setdiff(after_keys, before_keys)
  list(
    before_count = nrow(before),
    after_count = nrow(after),
    only_before = only_before,
    only_after = only_after,
    mismatched = mismatched,
    equal = length(only_before) == 0L && length(only_after) == 0L &&
      length(mismatched) == 0L
  )
}

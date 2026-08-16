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

achievement_fact_semantic_signature <- function(connection) {
  rows <- DBI::dbGetQuery(
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
  rows[] <- lapply(rows, function(value) {
    value <- as.character(value)
    value[is.na(value)] <- "<NA>"
    value
  })
  rownames(rows) <- NULL
  digest::digest(rows, algo = "sha256")
}

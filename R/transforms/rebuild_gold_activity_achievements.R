gold_activity_achievements_calculation_version <- function(config = list()) {
  calculation_version <- config$transforms$gold_activity_achievement_calculation_version

  if (is.null(calculation_version) || !nzchar(calculation_version)) {
    return("activity_achievements_v1")
  }

  as.character(calculation_version)
}

gold_activity_achievement_recent_notification_days <- function(config = list()) {
  days <- config$notifications$achievement_recent_activity_days

  if (is.null(days)) {
    return(7L)
  }

  as.integer(days)
}

achievement_metric_labels <- function() {
  c(
    power_watts = "power",
    distance_metres = "distance",
    moving_time_seconds = "moving duration",
    elevation_gain_metres = "elevation gain"
  )
}

achievement_metric_units <- function() {
  c(
    power_watts = "W",
    distance_metres = "km",
    moving_time_seconds = "",
    elevation_gain_metres = "m"
  )
}

achievement_type_labels <- function() {
  c(
    power_best_effort = "power best",
    longest_distance = "longest ride",
    longest_moving_duration = "longest moving duration",
    highest_elevation_gain = "highest elevation gain"
  )
}

achievement_duration_label <- function(duration_seconds) {
  duration_seconds <- as.integer(duration_seconds)

  if (is.na(duration_seconds) || duration_seconds <= 0) {
    return("")
  }

  if (duration_seconds < 60) {
    return(paste0(duration_seconds, "-second"))
  }

  if (duration_seconds %% 3600 == 0) {
    hours <- duration_seconds / 3600
    return(
      if (hours == 1) {
        "1-hour"
      } else {
        paste0(hours, "-hour")
      }
    )
  }

  if (duration_seconds %% 60 == 0) {
    return(paste0(duration_seconds / 60, "-minute"))
  }

  paste0(duration_seconds, "-second")
}

format_achievement_value <- function(metric_name, metric_value) {
  if (is.na(metric_value)) {
    return("unknown")
  }

  if (identical(metric_name, "distance_metres")) {
    return(paste0(round(metric_value / 1000, 1), " km"))
  }

  if (identical(metric_name, "moving_time_seconds")) {
    return(format_platform_duration(metric_value))
  }

  if (identical(metric_name, "power_watts")) {
    return(paste0(round(metric_value), " W"))
  }

  if (identical(metric_name, "elevation_gain_metres")) {
    return(paste0(round(metric_value), " m"))
  }

  as.character(round(metric_value, 1))
}

activity_achievement_title <- function(
  achievement_type,
  metric_name,
  duration_seconds,
  comparison_scope
) {
  scope_label <- if (identical(comparison_scope, "all_time")) {
    "all-time"
  } else {
    "this year"
  }

  if (identical(achievement_type, "power_best_effort")) {
    return(glue::glue(
      "New {scope_label} {achievement_duration_label(duration_seconds)} power best"
    ))
  }

  type_labels <- achievement_type_labels()

  glue::glue(
    "New {scope_label} {type_labels[[achievement_type]]}"
  )
}

activity_achievement_detail <- function(
  achievement_type,
  metric_name,
  duration_seconds,
  comparison_scope,
  metric_value,
  days_since_previous_best
) {
  title <- activity_achievement_title(
    achievement_type = achievement_type,
    metric_name = metric_name,
    duration_seconds = duration_seconds,
    comparison_scope = comparison_scope
  )

  detail <- glue::glue(
    "{title}: {format_achievement_value(metric_name, metric_value)}"
  )

  if (
    !identical(comparison_scope, "all_time") &&
      !is.na(days_since_previous_best) &&
      days_since_previous_best > 0
  ) {
    detail <- glue::glue(
      "{detail} -- best for {days_since_previous_best} days"
    )
  }

  as.character(detail)
}

activity_achievement_key <- function(
  activity_id,
  achievement_type,
  metric_name,
  duration_seconds,
  comparison_scope,
  comparison_period_start,
  comparison_period_end
) {
  key_material <- paste(
    activity_id,
    achievement_type,
    metric_name,
    duration_seconds,
    comparison_scope,
    comparison_period_start,
    comparison_period_end,
    sep = "|"
  )

  key <- as.character(
    openssl::sha256(
      charToRaw(key_material)
    )
  )

  attributes(key) <- NULL
  key
}

activity_achievement_empty <- function() {
  data.frame(
    activity_achievement_key = character(),
    activity_id = bit64::integer64(),
    achievement_type = character(),
    metric_name = character(),
    duration_seconds = integer(),
    comparison_scope = character(),
    comparison_period_start = as.Date(character()),
    comparison_period_end = as.Date(character()),
    achievement_rank = integer(),
    metric_value = numeric(),
    previous_best_value = numeric(),
    previous_best_activity_id = bit64::integer64(),
    previous_best_date = as.Date(character()),
    days_since_previous_best = integer(),
    achievement_title = character(),
    achievement_detail = character(),
    calculation_status = character(),
    calculation_version = character(),
    notification_eligible = integer(),
    source_transform_run_id = bit64::integer64(),
    computed_at = as.POSIXct(character(), tz = "UTC")
  )
}

normalise_achievement_source_rows <- function(rows) {
  rows$activity_id <- bit64::as.integer64(
    as.character(rows$activity_id)
  )
  rows$activity_date <- as.Date(rows$activity_date)
  rows$duration_seconds <- as.integer(rows$duration_seconds)
  rows$metric_value <- as.numeric(rows$metric_value)

  rows <- rows[
    !is.na(rows$activity_date) &
      !is.na(rows$metric_value),
    ,
    drop = FALSE
  ]

  rows[
    order(
      rows$activity_date,
      as.character(rows$activity_id),
      rows$achievement_type,
      rows$metric_name,
      rows$duration_seconds
    ),
    ,
    drop = FALSE
  ]
}

period_start_for_scope <- function(activity_date, comparison_scope) {
  if (identical(comparison_scope, "calendar_year")) {
    return(as.Date(sprintf("%s-01-01", format(activity_date, "%Y"))))
  }

  as.Date("1000-01-01")
}

period_end_for_scope <- function(activity_date, comparison_scope) {
  if (identical(comparison_scope, "calendar_year")) {
    return(as.Date(sprintf("%s-12-31", format(activity_date, "%Y"))))
  }

  as.Date("9999-12-31")
}

compute_achievement_for_row <- function(
  source_rows,
  row_index,
  comparison_scope,
  calculation_version,
  notification_eligible = FALSE,
  source_transform_run_id = NA
) {
  source_transform_run_id <- if (is.na(source_transform_run_id)) {
    bit64::as.integer64(NA)
  } else {
    bit64::as.integer64(
      as.character(source_transform_run_id)
    )
  }

  current <- source_rows[row_index, , drop = FALSE]

  prior <- source_rows[seq_len(row_index - 1L), , drop = FALSE]
  prior <- prior[
    prior$achievement_type == current$achievement_type[[1]] &
      prior$metric_name == current$metric_name[[1]] &
      prior$duration_seconds == current$duration_seconds[[1]],
    ,
    drop = FALSE
  ]

  period_start <- period_start_for_scope(
    activity_date = current$activity_date[[1]],
    comparison_scope = comparison_scope
  )

  period_end <- period_end_for_scope(
    activity_date = current$activity_date[[1]],
    comparison_scope = comparison_scope
  )

  comparison_prior <- prior

  if (identical(comparison_scope, "calendar_year")) {
    comparison_prior <- comparison_prior[
      comparison_prior$activity_date >= period_start &
        comparison_prior$activity_date <= period_end,
      ,
      drop = FALSE
    ]
  }

  prior_best <- if (nrow(comparison_prior) > 0) {
    max(comparison_prior$metric_value, na.rm = TRUE)
  } else {
    NA_real_
  }

  # Strictly greater avoids repeated achievements caused by ties or rounding.
  is_achievement <- is.na(prior_best) ||
    current$metric_value[[1]] > prior_best

  if (!is_achievement) {
    return(NULL)
  }

  prior_best_row <- NULL

  if (nrow(comparison_prior) > 0) {
    prior_best_row <- comparison_prior[
      which.max(comparison_prior$metric_value),
      ,
      drop = FALSE
    ]
  }

  recency_row <- NULL

  if (identical(comparison_scope, "calendar_year") && nrow(prior) > 0) {
    equal_or_better_prior <- prior[
      prior$metric_value >= current$metric_value[[1]],
      ,
      drop = FALSE
    ]

    if (nrow(equal_or_better_prior) > 0) {
      recency_row <- equal_or_better_prior[
        which.max(equal_or_better_prior$activity_date),
        ,
        drop = FALSE
      ]
    }
  }

  previous_best_value <- NA_real_
  previous_best_activity_id <- bit64::as.integer64(NA)
  previous_best_date <- as.Date(NA)
  days_since_previous_best <- NA_integer_

  if (identical(comparison_scope, "all_time")) {
    if (!is.null(prior_best_row)) {
      previous_best_value <- prior_best_row$metric_value[[1]]
      previous_best_activity_id <- prior_best_row$activity_id[[1]]
      previous_best_date <- prior_best_row$activity_date[[1]]
    }
  } else if (!is.null(recency_row)) {
    previous_best_value <- recency_row$metric_value[[1]]
    previous_best_activity_id <- recency_row$activity_id[[1]]
    previous_best_date <- recency_row$activity_date[[1]]
    days_since_previous_best <- as.integer(
      current$activity_date[[1]] - previous_best_date
    )
  }

  title <- activity_achievement_title(
    achievement_type = current$achievement_type[[1]],
    metric_name = current$metric_name[[1]],
    duration_seconds = current$duration_seconds[[1]],
    comparison_scope = comparison_scope
  )

  detail <- activity_achievement_detail(
    achievement_type = current$achievement_type[[1]],
    metric_name = current$metric_name[[1]],
    duration_seconds = current$duration_seconds[[1]],
    comparison_scope = comparison_scope,
    metric_value = current$metric_value[[1]],
    days_since_previous_best = days_since_previous_best
  )

  data.frame(
    activity_achievement_key = activity_achievement_key(
      activity_id = current$activity_id[[1]],
      achievement_type = current$achievement_type[[1]],
      metric_name = current$metric_name[[1]],
      duration_seconds = current$duration_seconds[[1]],
      comparison_scope = comparison_scope,
      comparison_period_start = period_start,
      comparison_period_end = period_end
    ),
    activity_id = current$activity_id[[1]],
    achievement_type = current$achievement_type[[1]],
    metric_name = current$metric_name[[1]],
    duration_seconds = current$duration_seconds[[1]],
    comparison_scope = comparison_scope,
    comparison_period_start = period_start,
    comparison_period_end = period_end,
    achievement_rank = 1L,
    metric_value = current$metric_value[[1]],
    previous_best_value = previous_best_value,
    previous_best_activity_id = previous_best_activity_id,
    previous_best_date = previous_best_date,
    days_since_previous_best = days_since_previous_best,
    achievement_title = as.character(title),
    achievement_detail = as.character(detail),
    calculation_status = "SUCCESS",
    calculation_version = calculation_version,
    notification_eligible = as.integer(notification_eligible),
    source_transform_run_id = source_transform_run_id,
    computed_at = as.POSIXct(Sys.time(), tz = "UTC")
  )
}

compute_activity_achievements <- function(
  source_rows,
  candidate_activity_ids = NULL,
  comparison_scopes = c(
    "all_time",
    "calendar_year"
  ),
  calculation_version = "activity_achievements_v1",
  notification_eligible_activity_ids = NULL,
  source_transform_run_id = NA
) {
  if (nrow(source_rows) == 0) {
    return(activity_achievement_empty())
  }

  source_rows <- normalise_achievement_source_rows(source_rows)

  if (is.null(candidate_activity_ids)) {
    candidate_activity_ids <- unique(source_rows$activity_id)
  }

  candidate_activity_ids <- as.character(candidate_activity_ids)

  notification_eligible_activity_ids <- as.character(
    notification_eligible_activity_ids
  )

  results <- list()

  for (row_index in seq_len(nrow(source_rows))) {
    current_activity_id <- as.character(source_rows$activity_id[[row_index]])

    if (!current_activity_id %in% candidate_activity_ids) {
      next
    }

    for (comparison_scope in comparison_scopes) {
      result <- compute_achievement_for_row(
        source_rows = source_rows,
        row_index = row_index,
        comparison_scope = comparison_scope,
        calculation_version = calculation_version,
        notification_eligible = current_activity_id %in%
          notification_eligible_activity_ids,
        source_transform_run_id = source_transform_run_id
      )

      if (!is.null(result)) {
        results[[length(results) + 1L]] <- result
      }
    }
  }

  if (length(results) == 0) {
    return(activity_achievement_empty())
  }

  do.call(rbind, results)
}

gold_achievement_placeholders <- function(values) {
  paste(
    rep("?", length(values)),
    collapse = ", "
  )
}

get_latest_gold_best_effort_transform_run_id <- function(connection) {
  result <- DBI::dbGetQuery(
    conn = connection,
    statement = "
      SELECT transform_run_id
      FROM cycling_platform_admin.transform_run
      WHERE layer_name = 'gold'
        AND entity_name = 'activity_best_efforts'
        AND run_status = 'SUCCESS'
      ORDER BY transform_run_id DESC
      LIMIT 1
    "
  )

  if (nrow(result) == 0) {
    return(NA)
  }

  result$transform_run_id[[1]]
}

fetch_activity_achievement_source_rows <- function(
  connection,
  durations
) {
  durations <- as.integer(durations)

  DBI::dbGetQuery(
    conn = connection,
    statement = paste0(
      "
      SELECT
        activities.activity_id,
        activities.start_date_local AS activity_date,
        'power_best_effort' AS achievement_type,
        'power_watts' AS metric_name,
        best_efforts.duration_seconds,
        best_efforts.peak_value AS metric_value
      FROM cycling_platform_gold.activity_best_efforts best_efforts
      INNER JOIN cycling_platform_silver.activities activities
        ON activities.activity_id = best_efforts.activity_id
      WHERE best_efforts.metric_name = 'watts'
        AND best_efforts.duration_seconds IN (",
      gold_achievement_placeholders(durations),
      ")
        AND best_efforts.peak_value IS NOT NULL
        AND best_efforts.peak_value > 0
        AND best_efforts.is_record_eligible = 1

      UNION ALL

      SELECT
        activity_id,
        start_date_local AS activity_date,
        'longest_distance' AS achievement_type,
        'distance_metres' AS metric_name,
        0 AS duration_seconds,
        distance_metres AS metric_value
      FROM cycling_platform_silver.activities
      WHERE distance_metres IS NOT NULL
        AND distance_metres > 0

      UNION ALL

      SELECT
        activity_id,
        start_date_local AS activity_date,
        'longest_moving_duration' AS achievement_type,
        'moving_time_seconds' AS metric_name,
        0 AS duration_seconds,
        moving_time_seconds AS metric_value
      FROM cycling_platform_silver.activities
      WHERE moving_time_seconds IS NOT NULL
        AND moving_time_seconds > 0

      UNION ALL

      SELECT
        activity_id,
        start_date_local AS activity_date,
        'highest_elevation_gain' AS achievement_type,
        'elevation_gain_metres' AS metric_name,
        0 AS duration_seconds,
        elevation_gain_metres AS metric_value
      FROM cycling_platform_silver.activities
      WHERE elevation_gain_metres IS NOT NULL
        AND elevation_gain_metres > 0
      "
    ),
    params = as.list(durations)
  )
}

get_activity_achievement_candidate_ids <- function(
  connection,
  mode,
  calculation_version,
  activity_ids = NULL
) {
  if (!is.null(activity_ids)) {
    return(as.character(activity_ids))
  }

  if (identical(mode, "backfill")) {
    result <- DBI::dbGetQuery(
      conn = connection,
      statement = "
        SELECT activity_id
        FROM cycling_platform_silver.activities
        ORDER BY start_date_local, activity_id
      "
    )

    return(as.character(result$activity_id))
  }

  result <- DBI::dbGetQuery(
    conn = connection,
    statement = "
      SELECT DISTINCT activities.activity_id
      FROM cycling_platform_silver.activities activities
      LEFT JOIN cycling_platform_gold.activity_achievements achievements
        ON achievements.activity_id = activities.activity_id
       AND achievements.calculation_version = ?
      LEFT JOIN cycling_platform_gold.activity_best_efforts best_efforts
        ON best_efforts.activity_id = activities.activity_id
       AND best_efforts.metric_name = 'watts'
      WHERE achievements.activity_achievement_key IS NULL
         OR best_efforts.computed_at > achievements.computed_at
      ORDER BY activities.start_date_local, activities.activity_id
    ",
    params = list(
      calculation_version
    )
  )

  as.character(result$activity_id)
}

gold_activity_achievements_existing_count <- function(connection) {
  DBI::dbGetQuery(
    conn = connection,
    statement = "
      SELECT COUNT(*) AS achievement_count
      FROM cycling_platform_gold.activity_achievements
    "
  )$achievement_count[[1]]
}

get_recent_activity_ids <- function(
  connection,
  recent_activity_days
) {
  result <- DBI::dbGetQuery(
    conn = connection,
    statement = "
      SELECT activity_id
      FROM cycling_platform_silver.activities
      WHERE start_date_local >= UTC_DATE() - INTERVAL ? DAY
      ORDER BY start_date_local, activity_id
    ",
    params = list(
      as.integer(recent_activity_days)
    )
  )

  as.character(result$activity_id)
}

daily_activity_achievement_candidate_ids <- function(
  candidate_activity_ids,
  recent_activity_ids,
  mode,
  existing_achievement_count
) {
  candidate_activity_ids <- as.character(candidate_activity_ids)

  if (
    identical(mode, "daily") &&
      existing_achievement_count > 0
  ) {
    return(unique(c(
      candidate_activity_ids,
      as.character(recent_activity_ids)
    )))
  }

  candidate_activity_ids
}

delete_gold_activity_achievements <- function(
  connection,
  activity_ids
) {
  if (length(activity_ids) == 0) {
    return(0L)
  }

  DBI::dbExecute(
    conn = connection,
    statement = paste0(
      "
      DELETE FROM cycling_platform_gold.activity_achievements
      WHERE activity_id IN (",
      gold_achievement_placeholders(activity_ids),
      ")
      "
    ),
    params = as.list(as.character(activity_ids))
  )
}

insert_gold_activity_achievements <- function(
  connection,
  achievements
) {
  if (nrow(achievements) == 0) {
    return(0L)
  }

  DBI::dbAppendTable(
    conn = connection,
    name = DBI::Id(
      schema = "cycling_platform_gold",
      table = "activity_achievements"
    ),
    value = achievements
  )
}

validate_gold_activity_achievements <- function(
  connection,
  calculation_version = "activity_achievements_v1"
) {
  checks <- list(
    list(
      check_name = "gold_activity_achievements_metric_value_populated",
      sql = "
        SELECT COUNT(*) AS failure_count
        FROM cycling_platform_gold.activity_achievements
        WHERE metric_value IS NULL
      "
    ),
    list(
      check_name = "gold_activity_achievements_days_non_negative",
      sql = "
        SELECT COUNT(*) AS failure_count
        FROM cycling_platform_gold.activity_achievements
        WHERE days_since_previous_best < 0
      "
    ),
    list(
      check_name = "gold_activity_achievements_calculation_version_current",
      sql = paste0(
        "
        SELECT COUNT(*) AS failure_count
        FROM cycling_platform_gold.activity_achievements
        WHERE calculation_version IS NULL
           OR calculation_version = ''
           OR calculation_version <> ",
        DBI::dbQuoteString(
          connection,
          calculation_version
        ),
        "
      "
      )
    ),
    list(
      check_name = "gold_activity_achievements_power_eligible_only",
      sql = "
        SELECT COUNT(*) AS failure_count
        FROM cycling_platform_gold.activity_achievements achievements
        INNER JOIN cycling_platform_gold.activity_best_efforts best_efforts
          ON best_efforts.activity_id = achievements.activity_id
         AND best_efforts.metric_name = 'watts'
         AND best_efforts.duration_seconds = achievements.duration_seconds
        WHERE achievements.achievement_type = 'power_best_effort'
          AND best_efforts.is_record_eligible <> 1
      "
    )
  )

  validation_results <- lapply(
    checks,
    \(check) {
      failure_count <- DBI::dbGetQuery(
        conn = connection,
        statement = check$sql
      )$failure_count[[1]]

      data.frame(
        check_name = check$check_name,
        failure_count = as.integer(failure_count),
        check_status = if (failure_count == 0) "PASS" else "FAIL"
      )
    }
  )

  validation_results <- do.call(rbind, validation_results)

  failed_checks <- validation_results[
    validation_results$check_status == "FAIL",
    ,
    drop = FALSE
  ]

  if (nrow(failed_checks) > 0) {
    stop(
      "Gold activity achievements validation failed: ",
      paste(
        paste0(
          failed_checks$check_name,
          "=",
          failed_checks$failure_count
        ),
        collapse = "; "
      ),
      call. = FALSE
    )
  }

  validation_results
}

rebuild_gold_activity_achievements <- function(
  connection,
  config = list(),
  activity_ids = NULL,
  durations = NULL,
  batch_size = NULL,
  max_activities = NULL,
  mode = c(
    "daily",
    "repair",
    "backfill"
  ),
  sql_dir = file.path("sql", "gold")
) {
  mode <- match.arg(mode)

  if (is.null(durations)) {
    durations <- config$transforms$gold_best_effort_durations
  }

  if (is.null(durations)) {
    durations <- default_best_effort_durations()
  }

  if (is.null(batch_size)) {
    batch_size <- config$transforms$gold_activity_achievement_activity_batch_size
  }

  if (is.null(batch_size)) {
    batch_size <- 100L
  }

  durations <- as.integer(
    unlist(
      durations,
      use.names = FALSE
    )
  )

  batch_size <- as.integer(batch_size[[1]])

  calculation_version <- gold_activity_achievements_calculation_version(
    config = config
  )

  recent_activity_days <- gold_activity_achievement_recent_notification_days(
    config = config
  )

  message(glue::glue(
    "Gold object: activity_achievements; mode: {mode}; ",
    "calculation version: {calculation_version}."
  ))

  ensure_power_source_classification_schema(connection)

  execute_sql_file(
    sql_file = file.path(
      sql_dir,
      "020_create_activity_achievements.sql"
    ),
    connection = connection
  )

  ensure_transform_logging_tables(
    connection = connection
  )

  existing_achievement_count <- gold_activity_achievements_existing_count(
    connection = connection
  )

  source_transform_run_id <- get_latest_gold_best_effort_transform_run_id(
    connection = connection
  )

  candidate_activity_ids <- get_activity_achievement_candidate_ids(
    connection = connection,
    mode = mode,
    calculation_version = calculation_version,
    activity_ids = activity_ids
  )

  recent_activity_ids <- if (identical(mode, "daily")) {
    get_recent_activity_ids(
      connection = connection,
      recent_activity_days = recent_activity_days
    )
  } else {
    character()
  }

  candidate_activity_ids <- daily_activity_achievement_candidate_ids(
    candidate_activity_ids = candidate_activity_ids,
    recent_activity_ids = recent_activity_ids,
    mode = mode,
    existing_achievement_count = existing_achievement_count
  )

  if (
    identical(mode, "daily") &&
      existing_achievement_count > 0 &&
      length(recent_activity_ids) > 0
  ) {
    message(glue::glue(
      "Gold activity achievements daily mode: reconsidering ",
      "{length(recent_activity_ids)} recent activities to catch partial ",
      "or interrupted prior runs."
    ))
  }

  if (!is.null(max_activities)) {
    candidate_activity_ids <- head(
      candidate_activity_ids,
      as.integer(max_activities)
    )
  }

  candidate_activity_count <- length(candidate_activity_ids)

  source_rows <- fetch_activity_achievement_source_rows(
    connection = connection,
    durations = durations
  )

  activity_batches <- if (candidate_activity_count == 0) {
    list()
  } else {
    split(
      candidate_activity_ids,
      ceiling(seq_along(candidate_activity_ids) / batch_size)
    )
  }

  transform_run_id <- create_transform_run(
    connection = connection,
    layer_name = "gold",
    entity_name = "activity_achievements",
    run_mode = mode,
    total_batches = length(activity_batches),
    activities_planned = candidate_activity_count,
    expected_rows_planned = 0L,
    max_batch_activities = batch_size,
    max_batch_expected_rows = NA_integer_
  )

  completed_batches <- 0L
  activities_completed <- 0L
  total_rows_deleted <- 0L
  total_rows_inserted <- 0L
  activities_without_achievements <- 0L

  if (candidate_activity_count == 0) {
    message("No gold activity achievements require processing.")

    validation_results <- validate_gold_activity_achievements(
      connection = connection,
      calculation_version = calculation_version
    )

    update_transform_run(
      connection = connection,
      transform_run_id = transform_run_id,
      run_status = "SUCCESS",
      completed_batches = completed_batches,
      activities_completed = activities_completed,
      rows_inserted = total_rows_inserted,
      rows_deleted = total_rows_deleted
    )

    return(invisible(validation_results))
  }

  notification_eligible_activity_ids <- if (
    identical(mode, "daily") &&
      existing_achievement_count > 0
  ) {
    intersect(
      candidate_activity_ids,
      recent_activity_ids
    )
  } else {
    if (identical(mode, "daily") && existing_achievement_count == 0) {
      message(
        "Achievement notification eligibility disabled for initial daily ",
        "run because gold.activity_achievements has no existing history. ",
        "Run an explicit backfill first to establish baseline history."
      )
    }

    character()
  }

  run_error <- tryCatch(
    {
      purrr::iwalk(
        activity_batches,
        \(activity_ids_batch, batch_index) {
          message(glue::glue(
            "Processing gold activity achievement batch {batch_index}/",
            "{length(activity_batches)} ({length(activity_ids_batch)} activities)."
          ))

          transform_run_batch_id <- create_transform_run_batch(
            connection = connection,
            transform_run_id = transform_run_id,
            batch_number = batch_index,
            activity_ids = activity_ids_batch,
            expected_rows = 0L
          )

          batch_achievements <- compute_activity_achievements(
            source_rows = source_rows,
            candidate_activity_ids = activity_ids_batch,
            calculation_version = calculation_version,
            notification_eligible_activity_ids =
              notification_eligible_activity_ids,
            source_transform_run_id = source_transform_run_id
          )

          rows_deleted <- 0L
          rows_inserted <- 0L

          batch_error <- tryCatch(
            {
              DBI::dbBegin(connection)

              tryCatch(
                {
                  rows_deleted <- delete_gold_activity_achievements(
                    connection = connection,
                    activity_ids = activity_ids_batch
                  )

                  rows_inserted <- insert_gold_activity_achievements(
                    connection = connection,
                    achievements = batch_achievements
                  )

                  DBI::dbCommit(connection)
                },
                error = function(e) {
                  tryCatch(
                    DBI::dbRollback(connection),
                    error = function(rollback_error) {
                      message(
                        "Gold achievement batch rollback failed: ",
                        conditionMessage(rollback_error)
                      )
                    }
                  )

                  stop(e)
                }
              )

              NULL
            },
            error = function(e) {
              e
            }
          )

          if (!is.null(batch_error)) {
            update_transform_run_batch(
              connection = connection,
              transform_run_batch_id = transform_run_batch_id,
              batch_status = "FAILED",
              rows_inserted = rows_inserted,
              rows_deleted = rows_deleted,
              error_message = conditionMessage(batch_error)
            )

            stop(batch_error)
          }

          completed_batches <<- completed_batches + 1L
          activities_completed <<- activities_completed + length(activity_ids_batch)
          total_rows_deleted <<- total_rows_deleted + rows_deleted
          total_rows_inserted <<- total_rows_inserted + rows_inserted
          activities_without_achievements <<- activities_without_achievements +
            length(setdiff(
              as.character(activity_ids_batch),
              as.character(batch_achievements$activity_id)
            ))

          update_transform_run_batch(
            connection = connection,
            transform_run_batch_id = transform_run_batch_id,
            batch_status = "SUCCESS",
            rows_inserted = rows_inserted,
            rows_deleted = rows_deleted
          )

          update_transform_run(
            connection = connection,
            transform_run_id = transform_run_id,
            run_status = "RUNNING",
            completed_batches = completed_batches,
            activities_completed = activities_completed,
            rows_inserted = total_rows_inserted,
            rows_deleted = total_rows_deleted
          )

          message(glue::glue(
            "Completed gold achievement batch {batch_index}/",
            "{length(activity_batches)}: {rows_deleted} rows deleted, ",
            "{rows_inserted} rows inserted, ",
            "{length(activity_ids_batch)} activities processed."
          ))
        }
      )

      NULL
    },
    error = function(e) {
      e
    }
  )

  if (!is.null(run_error)) {
    update_transform_run(
      connection = connection,
      transform_run_id = transform_run_id,
      run_status = "FAILED",
      completed_batches = completed_batches,
      activities_completed = activities_completed,
      rows_inserted = total_rows_inserted,
      rows_deleted = total_rows_deleted,
      error_message = conditionMessage(run_error)
    )

    stop(run_error)
  }

  validation_results <- validate_gold_activity_achievements(
    connection = connection,
    calculation_version = calculation_version
  )

  update_transform_run(
    connection = connection,
    transform_run_id = transform_run_id,
    run_status = "SUCCESS",
    completed_batches = completed_batches,
    activities_completed = activities_completed,
    rows_inserted = total_rows_inserted,
    rows_deleted = total_rows_deleted
  )

  message(glue::glue(
    "Gold activity achievements rebuild complete: ",
    "{activities_completed} activities processed, ",
    "{total_rows_inserted} achievements inserted, ",
    "{total_rows_deleted} rows deleted, ",
    "{activities_without_achievements} activities without achievements, ",
    "calculation version {calculation_version}."
  ))

  invisible(validation_results)
}

achievement_notification_channel <- function(config = list()) {
  channel <- config$notifications$achievement_notification_channel

  if (is.null(channel) || !nzchar(channel)) {
    return("ntfy")
  }

  as.character(channel)
}

achievement_notification_max_attempts <- function(config = list()) {
  attempts <- config$notifications$achievement_max_attempts

  if (is.null(attempts)) {
    return(3L)
  }

  as.integer(attempts)
}

achievement_notification_retry_delay_minutes <- function(config = list()) {
  minutes <- config$notifications$achievement_retry_delay_minutes

  if (is.null(minutes)) {
    return(60L)
  }

  as.integer(minutes)
}

activity_achievement_notification_source_key <- function(achievement_keys) {
  key_material <- paste(
    sort(as.character(achievement_keys)),
    collapse = "|"
  )

  key <- as.character(
    openssl::sha256(
      charToRaw(key_material)
    )
  )

  attributes(key) <- NULL
  key
}

format_achievement_notification_line <- function(achievement) {
  detail <- achievement$achievement_detail[[1]]

  if (!is.na(detail) && nzchar(detail)) {
    return(paste0("- ", detail))
  }

  paste0(
    "- ",
    achievement$achievement_title[[1]],
    ": ",
    format_achievement_value(
      metric_name = achievement$metric_name[[1]],
      metric_value = achievement$metric_value[[1]]
    )
  )
}

format_activity_achievement_notification_body <- function(
  activity,
  achievements
) {
  achievements <- achievements[
    order(
      achievements$comparison_scope != "all_time",
      achievements$achievement_type,
      achievements$duration_seconds
    ),
    ,
    drop = FALSE
  ]

  activity_date <- as.character(activity$start_date_local[[1]])
  activity_name <- activity$activity_name[[1]]

  if (is.na(activity_name) || !nzchar(activity_name)) {
    activity_name <- paste("Activity", activity$activity_id[[1]])
  }

  distance_line <- if (
    "distance_kilometres" %in% names(activity) &&
      !is.na(activity$distance_kilometres[[1]])
  ) {
    paste0(" -- ", round(activity$distance_kilometres[[1]], 1), " km")
  } else {
    ""
  }

  c(
    glue::glue("{activity_name}{distance_line}"),
    activity_date,
    "",
    purrr::map_chr(
      split(achievements, seq_len(nrow(achievements))),
      format_achievement_notification_line
    )
  )
}

activity_achievement_payload_json <- function(
  activity,
  achievements
) {
  payload <- list(
    activity = list(
      activity_id = as.character(activity$activity_id[[1]]),
      activity_name = activity$activity_name[[1]],
      start_date_local = as.character(activity$start_date_local[[1]]),
      distance_kilometres = activity$distance_kilometres[[1]]
    ),
    achievements = purrr::map(
      split(achievements, seq_len(nrow(achievements))),
      \(achievement) {
        list(
          activity_achievement_key =
            achievement$activity_achievement_key[[1]],
          achievement_type = achievement$achievement_type[[1]],
          metric_name = achievement$metric_name[[1]],
          duration_seconds = achievement$duration_seconds[[1]],
          comparison_scope = achievement$comparison_scope[[1]],
          metric_value = achievement$metric_value[[1]],
          previous_best_value = achievement$previous_best_value[[1]],
          previous_best_activity_id = as.character(
            achievement$previous_best_activity_id[[1]]
          ),
          previous_best_date = as.character(
            achievement$previous_best_date[[1]]
          ),
          days_since_previous_best =
            achievement$days_since_previous_best[[1]],
          achievement_title = achievement$achievement_title[[1]],
          achievement_detail = achievement$achievement_detail[[1]]
        )
      }
    ),
    message_lines = format_activity_achievement_notification_body(
      activity = activity,
      achievements = achievements
    )
  )

  as.character(
    jsonlite::toJSON(
      payload,
      auto_unbox = TRUE,
      null = "null",
      digits = NA
    )
  )
}

queue_activity_achievement_notifications <- function(
  connection,
  config = list(),
  include_historical = FALSE
) {
  notifications <- config$notifications

  if (
    is.null(notifications$achievement_notifications_enabled) ||
      !isTRUE(notifications$achievement_notifications_enabled)
  ) {
    return(
      list(
        queued = 0L,
        skipped = 0L
      )
    )
  }

  channel <- achievement_notification_channel(config)

  eligibility_sql <- if (isTRUE(include_historical)) {
    "1 = 1"
  } else {
    "achievements.notification_eligible = 1"
  }

  achievements <- DBI::dbGetQuery(
    conn = connection,
    statement = glue::glue("
      SELECT
        achievements.*,
        activities.activity_name,
        activities.start_date_local,
        activities.distance_kilometres
      FROM cycling_platform_gold.activity_achievements achievements
      INNER JOIN cycling_platform_silver.activities activities
        ON activities.activity_id = achievements.activity_id
      WHERE {eligibility_sql}
      ORDER BY
        activities.start_date_local,
        achievements.activity_id,
        achievements.comparison_scope,
        achievements.achievement_type,
        achievements.duration_seconds
    ")
  )

  if (nrow(achievements) == 0) {
    return(
      list(
        queued = 0L,
        skipped = 0L
      )
    )
  }

  grouped <- split(
    achievements,
    achievements$activity_id
  )

  queued <- 0L
  skipped <- 0L

  for (activity_id in names(grouped)) {
    activity_achievements <- grouped[[activity_id]]

    source_key <- activity_achievement_notification_source_key(
      activity_achievements$activity_achievement_key
    )

    existing <- DBI::dbGetQuery(
      conn = connection,
      statement = "
        SELECT notification_id
        FROM cycling_platform_admin.notification_outbox
        WHERE event_type = 'activity_achievement'
          AND source_object = 'cycling_platform_gold.activity_achievements'
          AND source_key = ?
          AND channel = ?
        LIMIT 1
      ",
      params = list(
        source_key,
        channel
      )
    )

    if (nrow(existing) > 0) {
      skipped <- skipped + 1L
      next
    }

    activity <- activity_achievements[1, , drop = FALSE]

    payload_json <- activity_achievement_payload_json(
      activity = activity,
      achievements = activity_achievements
    )

    DBI::dbExecute(
      conn = connection,
      statement = "
        INSERT INTO cycling_platform_admin.notification_outbox (
          event_type,
          source_object,
          source_key,
          activity_id,
          channel,
          notification_status,
          payload_json,
          next_attempt_at
        )
        VALUES (
          'activity_achievement',
          'cycling_platform_gold.activity_achievements',
          ?,
          ?,
          ?,
          'PENDING',
          ?,
          UTC_TIMESTAMP()
        )
      ",
      params = list(
        source_key,
        activity_id,
        channel,
        payload_json
      )
    )

    queued <- queued + 1L
  }

  list(
    queued = queued,
    skipped = skipped
  )
}

fetch_due_notifications <- function(
  connection,
  config = list(),
  limit = 20L
) {
  max_attempts <- achievement_notification_max_attempts(config)

  DBI::dbGetQuery(
    conn = connection,
    statement = "
      SELECT
        notification_id,
        event_type,
        source_object,
        source_key,
        activity_id,
        channel,
        notification_status,
        attempt_count,
        payload_json
      FROM cycling_platform_admin.notification_outbox
      WHERE notification_status IN ('PENDING', 'RETRY', 'FAILED')
        AND attempt_count < ?
        AND (
          next_attempt_at IS NULL
          OR next_attempt_at <= UTC_TIMESTAMP()
        )
      ORDER BY created_at
      LIMIT ?
    ",
    params = list(
      max_attempts,
      as.integer(limit)
    )
  )
}

render_outbox_notification <- function(notification) {
  payload <- jsonlite::fromJSON(
    notification$payload_json[[1]],
    simplifyVector = FALSE
  )

  paste(
    unlist(
      payload$message_lines,
      use.names = FALSE
    ),
    collapse = "\n"
  )
}

send_outbox_ntfy_notification <- function(
  notification,
  config
) {
  notifications <- config$notifications

  if (is.null(notifications$enabled) || !isTRUE(notifications$enabled)) {
    stop(
      "Notifications are disabled.",
      call. = FALSE
    )
  }

  if (!identical(notifications$provider, "ntfy")) {
    stop(
      "Unsupported notification provider: ",
      notifications$provider,
      call. = FALSE
    )
  }

  topic <- notifications$topic

  if (is.null(topic) || !nzchar(topic)) {
    stop(
      "Notification topic is not configured.",
      call. = FALSE
    )
  }

  base_url <- notifications$base_url

  if (is.null(base_url) || !nzchar(base_url)) {
    base_url <- "https://ntfy.sh"
  }

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
      Title = "New cycling achievements",
      Priority = "default",
      Tags = "trophy,bike"
    ) |>
    httr2::req_timeout(20) |>
    httr2::req_body_raw(
      body = charToRaw(
        render_outbox_notification(notification)
      ),
      type = "text/plain"
    ) |>
    httr2::req_perform()

  TRUE
}

mark_notification_sending <- function(connection, notification_id) {
  DBI::dbExecute(
    conn = connection,
    statement = "
      UPDATE cycling_platform_admin.notification_outbox
      SET
        notification_status = 'SENDING',
        attempted_at = UTC_TIMESTAMP(),
        attempt_count = attempt_count + 1,
        error_message = NULL
      WHERE notification_id = ?
    ",
    params = list(notification_id)
  )
}

mark_notification_sent <- function(connection, notification_id) {
  DBI::dbExecute(
    conn = connection,
    statement = "
      UPDATE cycling_platform_admin.notification_outbox
      SET
        notification_status = 'SENT',
        sent_at = UTC_TIMESTAMP(),
        error_message = NULL
      WHERE notification_id = ?
    ",
    params = list(notification_id)
  )
}

mark_notification_failed <- function(
  connection,
  notification_id,
  error_message,
  config = list()
) {
  retry_delay_minutes <- achievement_notification_retry_delay_minutes(config)
  max_attempts <- achievement_notification_max_attempts(config)

  DBI::dbExecute(
    conn = connection,
    statement = "
      UPDATE cycling_platform_admin.notification_outbox
      SET
        notification_status = CASE
          WHEN attempt_count >= ? THEN 'FAILED'
          ELSE 'RETRY'
        END,
        next_attempt_at = CASE
          WHEN attempt_count >= ? THEN NULL
          ELSE DATE_ADD(UTC_TIMESTAMP(), INTERVAL ? MINUTE)
        END,
        error_message = ?
      WHERE notification_id = ?
    ",
    params = list(
      max_attempts,
      max_attempts,
      retry_delay_minutes,
      substr(error_message, 1, 2000),
      notification_id
    )
  )
}

deliver_due_notifications <- function(
  connection,
  config = list(),
  limit = 20L
) {
  notifications <- fetch_due_notifications(
    connection = connection,
    config = config,
    limit = limit
  )

  sent <- 0L
  failed <- 0L
  retried <- 0L

  if (nrow(notifications) == 0) {
    return(
      list(
        attempted = 0L,
        sent = 0L,
        failed = 0L,
        retry = 0L
      )
    )
  }

  for (row_index in seq_len(nrow(notifications))) {
    notification <- notifications[row_index, , drop = FALSE]

    mark_notification_sending(
      connection = connection,
      notification_id = notification$notification_id[[1]]
    )

    error <- tryCatch(
      {
        send_outbox_ntfy_notification(
          notification = notification,
          config = config
        )

        NULL
      },
      error = function(e) {
        e
      }
    )

    if (is.null(error)) {
      mark_notification_sent(
        connection = connection,
        notification_id = notification$notification_id[[1]]
      )

      sent <- sent + 1L
    } else {
      mark_notification_failed(
        connection = connection,
        notification_id = notification$notification_id[[1]],
        error_message = conditionMessage(error),
        config = config
      )

      failed <- failed + 1L
      retried <- retried + 1L
    }
  }

  list(
    attempted = nrow(notifications),
    sent = sent,
    failed = failed,
    retry = retried
  )
}

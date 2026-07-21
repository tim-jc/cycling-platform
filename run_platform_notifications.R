# run_platform_notifications.R
source("bootstrap.R")

config <- load_config()

args <- commandArgs(
  trailingOnly = TRUE
)

mode <- "deliver"

if (length(args) > 0) {
  mode <- tolower(args[[1]])
}

if (!mode %in% c("queue", "deliver", "queue_and_deliver")) {
  stop(
    "Unknown notification mode. Use 'queue', 'deliver', or 'queue_and_deliver'.",
    call. = FALSE
  )
}

connection <- get_connection("mysql")

tryCatch(
  {
    execute_sql_file(
      sql_file = file.path(
        "sql",
        "admin",
        "060_create_notification_outbox.sql"
      ),
      connection = connection
    )

    queue_result <- list(
      queued = 0L,
      skipped = 0L
    )

    delivery_result <- list(
      attempted = 0L,
      sent = 0L,
      failed = 0L,
      retry = 0L
    )

    if (mode %in% c("queue", "queue_and_deliver")) {
      queue_result <- queue_activity_achievement_notifications(
        connection = connection,
        config = config
      )

      message(glue::glue(
        "Achievement notification queue: {queue_result$queued} queued, ",
        "{queue_result$skipped} skipped."
      ))
    }

    if (mode %in% c("deliver", "queue_and_deliver")) {
      delivery_result <- deliver_due_notifications(
        connection = connection,
        config = config
      )

      message(glue::glue(
        "Notification delivery: {delivery_result$attempted} attempted, ",
        "{delivery_result$sent} sent, {delivery_result$failed} failed, ",
        "{delivery_result$retry} retry."
      ))
    }
  },
  finally = {
    if (DBI::dbIsValid(connection)) {
      DBI::dbDisconnect(connection)
    }
  }
)

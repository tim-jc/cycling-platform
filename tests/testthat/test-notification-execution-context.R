source_notification_context_files <- function() {
  files <- c(
    file.path("R", "utils", "execution_context.R"),
    file.path("R", "utils", "format_notification_helpers.R")
  )

  for (file in files) {
    if (!file.exists(file)) {
      file <- file.path("..", "..", file)
    }

    source(file)
  }
}

testthat::test_that("execution host prefers the operating-system nodename", {
  source_notification_context_files()

  host <- platform_execution_host(
    system_info = c(nodename = "cycling-prod"),
    hostname_environment = "container-id"
  )

  testthat::expect_equal(host, "cycling-prod")
})

testthat::test_that("execution host falls back safely", {
  source_notification_context_files()

  testthat::expect_equal(
    platform_execution_host(
      system_info = c(nodename = NA_character_),
      hostname_environment = "container-id"
    ),
    "container-id"
  )

  testthat::expect_equal(
    platform_execution_host(
      system_info = c(nodename = NA_character_),
      hostname_environment = ""
    ),
    "unknown"
  )
})

testthat::test_that("execution context has a compact stable structure", {
  source_notification_context_files()

  lines <- format_platform_execution_context(
    platform_execution_context(
      pipeline = "daily-platform",
      status = "SUCCESS",
      duration_seconds = 252,
      host = "cycling-prod"
    )
  )

  testthat::expect_equal(
    lines,
    c(
      "Host: cycling-prod",
      "Pipeline: daily-platform",
      "Status: SUCCESS",
      "Duration: 4m 12s"
    )
  )
})

testthat::test_that("all ntfy senders use shared execution context", {
  root <- if (dir.exists("R")) "." else file.path("..", "..")
  senders <- file.path(
    root,
    "R",
    "utils",
    c(
      "send_notification.R",
      "send_platform_automation_notification.R",
      "send_platform_validation_notification.R",
      "activity_achievement_notifications.R"
    )
  )

  for (sender in senders) {
    text <- paste(readLines(sender, warn = FALSE), collapse = "\n")
    testthat::expect_match(
      text,
      "platform_execution_context(",
      fixed = TRUE,
      info = sender
    )
    testthat::expect_match(
      text,
      "format_platform_execution_context(",
      fixed = TRUE,
      info = sender
    )
  }
})

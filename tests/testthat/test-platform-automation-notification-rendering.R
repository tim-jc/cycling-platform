source_automation_notification_renderer <- function() {
  root <- if (dir.exists("R")) "." else file.path("..", "..")
  source(file.path(root, "R", "utils", "execution_context.R"))
  source(file.path(root, "R", "utils", "format_notification_helpers.R"))
  source(file.path(root, "R", "utils", "send_platform_automation_notification.R"))
}

quiet_notification_fixture <- function() {
  entity_summary <- data.frame(
    entity_name = c("activities", "google_health_heart_rate"),
    entity_status = "SUCCESS",
    rows_inserted = c(0, 1),
    rows_updated = c(0, 7)
  )
  silver_runs <- data.frame(
    entity_name = c("activities", "gear", "activity_streams", "activity_laps"),
    run_status = "SUCCESS",
    run_mode = c("incremental", "full", "repair", "incremental"),
    activities_planned = c(0, 0, 0, 0),
    activities_completed = c(0, 0, 0, 0),
    rows_inserted = c(0, 15, 0, 0),
    rows_updated = 0,
    rows_deleted = 0
  )
  gold_runs <- data.frame(
    entity_name = c("activity_best_efforts", "activity_achievements"),
    run_status = "SUCCESS",
    run_mode = "daily",
    activities_planned = 0,
    activities_completed = 0,
    rows_inserted = 0,
    rows_updated = 0,
    rows_deleted = 0
  )
  phases <- data.frame(
    phase_name = c(
      "raw_ingestion", "silver_transforms", "silver_publication_checks",
      "gold_transforms", "gold_publication_checks", "achievement_notifications",
      "deep_validation"
    ),
    phase_status = c(rep("SUCCESS", 6), "NOT_RUN"),
    duration_seconds = c(312, 1, 4, 1, 1, 0, 0)
  )

  list(
    phase_results = phases,
    raw = list(
      run_line = "Run: raw #172 · SCHEDULED · 5m 5s",
      run_status = "SUCCESS",
      duration_seconds = 305,
      entity_lines = c("activities: SUCCESS · +0 / ~0", "google_health_heart_rate: SUCCESS · +1 / ~7"),
      entity_summary = entity_summary,
      reconciliation_lines = c(
        "Reconciliation: examined 19 · new/recovered 0 · changed 0 · unchanged 19 · missing from source 0",
        "Selective repairs requested: details 0 · streams 0 · laps 0"
      ),
      reconciliation_totals = c(NEW = 0, CHANGED = 0, UNCHANGED = 19, MISSING = 0),
      repair_totals = c(details = 0, streams = 0, laps = 0),
      pending_counts = c(streams = 0, details = 0, laps = 0),
      pending_line = "Pending: streams 0 · details 0 · laps 0"
    ),
    silver = list(lines = paste0(silver_runs$entity_name, ": detail"), runs = silver_runs),
    gold = list(
      lines = paste0(gold_runs$entity_name, ": detail"),
      runs = gold_runs,
      transform_timings = list(
        activity_best_efforts = list(output_changed_activity_count = 0),
        activity_achievements = list(
          evaluation_debt_count = 0,
          remaining_invalidated_count = 0,
          invalidation_action = "none"
        )
      ),
      orchestration_lines = "Gold orchestration: detail"
    ),
    achievements = list(
      lines = c("queued 0", "attempted 0 · sent 0 · failed 0 · retry 0"),
      queue_result = list(queued = 0, skipped = 2, already_sent = 0, already_queued = 0),
      delivery_result = list(attempted = 0, sent = 0, failed = 0, retry = 0)
    ),
    backup = list(
      lines = c("Off-host backup: 16 Aug 04:08 — 20h ago ✓", "Retention: 30-day set reconciled ✓"),
      freshness_status = "HEALTHY",
      reconciliation_status = "HEALTHY"
    )
  )
}

render_fixture <- function(x, status = "SUCCESS", error_message = NULL) {
  format_platform_automation_notification_body(
    run_status = status,
    phase_results = x$phase_results,
    raw_ingestion_summary = x$raw,
    silver_transform_summary = x$silver,
    gold_transform_summary = x$gold,
    achievement_notification_summary = x$achievements,
    backup_health_summary = x$backup,
    error_message = error_message,
    pipeline = "daily-platform",
    window_label = "previous 30 days",
    host = "cycling-prod"
  )
}

testthat::test_that("quiet successful notification suppresses expected zero-state detail", {
  source_automation_notification_renderer()
  x <- quiet_notification_fixture()
  body <- paste(render_fixture(x), collapse = "\n")

  testthat::expect_match(body, "No Strava changes · Google Health refresh completed", fixed = TRUE)
  testthat::expect_match(body, "Silver:\nSUCCESS · no affected activities", fixed = TRUE)
  testthat::expect_match(body, "Gold:\nSUCCESS · no candidates · no evaluation debt", fixed = TRUE)
  testthat::expect_match(body, "Achievement notifications: none", fixed = TRUE)
  testthat::expect_match(body, "Off-host backup: 20h ago ✓", fixed = TRUE)
  testthat::expect_match(body, "raw 5m 12s · silver 1s · gold 1s · checks 5s", fixed = TRUE)
  testthat::expect_false(grepl("Pending:", body, fixed = TRUE))
  testthat::expect_false(grepl("gear: detail", body, fixed = TRUE))
  testthat::expect_false(grepl("deep_validation", body, fixed = TRUE))

  # Rendering does not discard or mutate the detailed source observability.
  testthat::expect_equal(x$raw$entity_summary$rows_updated[[2]], 7)
  testthat::expect_equal(x$silver$runs$rows_inserted[[2]], 15)
  testthat::expect_equal(x$gold$orchestration_lines, "Gold orchestration: detail")
})

testthat::test_that("Raw expands for changes, repairs, pending work, and failures", {
  source_automation_notification_renderer()

  for (mutation in c("new", "changed", "repair", "pending", "failure")) {
    x <- quiet_notification_fixture()
    if (mutation == "new") x$raw$reconciliation_totals[["NEW"]] <- 1
    if (mutation == "changed") x$raw$reconciliation_totals[["CHANGED"]] <- 1
    if (mutation == "repair") x$raw$repair_totals[["streams"]] <- 1
    if (mutation == "pending") x$raw$pending_counts[["laps"]] <- 1
    if (mutation == "failure") x$raw$entity_summary$entity_status[[1]] <- "FAILED"
    body <- paste(render_fixture(x), collapse = "\n")
    testthat::expect_match(body, "Reconciliation: examined", fixed = TRUE, info = mutation)
    testthat::expect_match(body, "Pending:", fixed = TRUE, info = mutation)
  }
})

testthat::test_that("Silver and Gold expand only for operationally meaningful work", {
  source_automation_notification_renderer()

  x <- quiet_notification_fixture()
  x$silver$runs$activities_planned[x$silver$runs$entity_name == "activities"] <- 1
  testthat::expect_match(paste(render_fixture(x), collapse = "\n"), "activities: detail", fixed = TRUE)

  for (field in c("candidates", "output", "debt", "invalidation")) {
    x <- quiet_notification_fixture()
    if (field == "candidates") x$gold$runs$activities_planned[[1]] <- 1
    if (field == "output") x$gold$transform_timings$activity_best_efforts$output_changed_activity_count <- 1
    if (field == "debt") x$gold$transform_timings$activity_achievements$evaluation_debt_count <- 1
    if (field == "invalidation") {
      x$gold$transform_timings$activity_achievements$invalidation_action <- "historical_closure"
      x$gold$lines[[2]] <- "historical invalidation from 2025-06-14 · closure 412"
    }
    body <- paste(render_fixture(x), collapse = "\n")
    testthat::expect_match(body, "activity_best_efforts: detail", fixed = TRUE, info = field)
    if (field == "invalidation") testthat::expect_match(body, "historical invalidation", fixed = TRUE)
  }
})

testthat::test_that("achievement delivery, backup warnings, and phase failures stay detailed", {
  source_automation_notification_renderer()

  x <- quiet_notification_fixture()
  x$achievements$queue_result$queued <- 1
  x$achievements$delivery_result$attempted <- 1
  x$achievements$delivery_result$sent <- 1
  x$achievements$lines <- c("queued 1", "attempted 1 · sent 1 · failed 0 · retry 0")
  body <- paste(render_fixture(x), collapse = "\n")
  testthat::expect_match(body, "queued 1", fixed = TRUE)

  x <- quiet_notification_fixture()
  x$achievements$delivery_result$failed <- 1
  x$achievements$delivery_result$retry <- 1
  x$achievements$lines[[2]] <- "attempted 1 · sent 0 · failed 1 · retry 1"
  testthat::expect_match(paste(render_fixture(x), collapse = "\n"), "failed 1 · retry 1", fixed = TRUE)

  for (status in c("STALE", "CRITICAL")) {
    x <- quiet_notification_fixture()
    x$backup$freshness_status <- status
    x$backup$lines[[1]] <- paste0("Off-host backup: 15 Aug 04:08 — 44h ago ⚠ ", status)
    body <- paste(render_fixture(x), collapse = "\n")
    testthat::expect_match(body, paste0("⚠ ", status), fixed = TRUE)
    testthat::expect_match(body, "15 Aug 04:08", fixed = TRUE)
  }

  x <- quiet_notification_fixture()
  x$phase_results$phase_status[x$phase_results$phase_name == "gold_transforms"] <- "FAILED"
  body <- paste(render_fixture(x, status = "FAILED", error_message = "Gold exploded"), collapse = "\n")
  testthat::expect_match(body, "gold_transforms: FAILED", fixed = TRUE)
  testthat::expect_match(body, "Error:\nGold exploded", fixed = TRUE)

  x <- quiet_notification_fixture()
  x$phase_results$phase_status[x$phase_results$phase_name == "gold_transforms"] <- "NOT_RUN"
  testthat::expect_match(paste(render_fixture(x), collapse = "\n"), "gold_transforms: NOT_RUN", fixed = TRUE)
})

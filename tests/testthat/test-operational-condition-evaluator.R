condition_test_path <- function(...) {
  path <- file.path(...)
  if (!file.exists(path)) path <- file.path("..", "..", path)
  path
}

source(condition_test_path("R", "admin", "operational_condition_evaluator.R"))

condition_observation <- function(
  status,
  domain = "EXECUTION",
  key = "latest_daily_pipeline",
  item_count = if (status %in% c("WARNING", "CRITICAL")) 1L else 0L,
  summary = "fixture",
  observed_at = as.POSIXct("2026-11-10 10:00:00", tz = "UTC")
) {
  data.frame(
    debt_key = key, debt_domain = domain, health_status = status,
    item_count = item_count, summary = summary,
    observed_at_utc = observed_at, stringsAsFactors = FALSE
  )
}

condition_state <- function(active = NA_real_, last_actionable = NA_character_) {
  data.frame(
    active_incident_id = active,
    last_actionable_severity = last_actionable,
    stringsAsFactors = FALSE
  )
}

advance_condition_state <- function(state, observation, next_incident = 1) {
  transition <- derive_operational_condition_transition(observation, state)
  active <- if (!is.null(state) && nrow(state)) state$active_incident_id[[1L]] else NA_real_
  last <- if (!is.null(state) && nrow(state)) state$last_actionable_severity[[1L]] else NA_character_
  if (transition$opens_incident) active <- next_incident
  if (transition$closes_incident) active <- NA_real_
  if (transition$updates_actionable_severity) last <- observation$health_status[[1L]]
  list(
    transition = transition$transition_event[[1L]],
    state = condition_state(active, last)
  )
}

run_condition_sequence <- function(statuses) {
  state <- NULL
  events <- character()
  incident <- 0L
  for (status in statuses) {
    candidate <- derive_operational_condition_transition(
      condition_observation(status), state
    )
    if (candidate$opens_incident) incident <- incident + 1L
    step <- advance_condition_state(state, condition_observation(status), incident)
    if (step$transition != "NONE") events <- c(events, step$transition)
    state <- step$state
  }
  list(events = events, state = state, incident_count = incident)
}

complete_catalogue_fixture <- function() {
  expected <- operational_debt_expected_catalogue()
  data.frame(
    debt_key = expected$debt_key,
    debt_domain = expected$debt_domain,
    health_status = "HEALTHY",
    item_count = 0L,
    summary = paste("fixture", expected$debt_key),
    observed_at_utc = as.POSIXct("2026-11-10 10:00:00", tz = "UTC"),
    stringsAsFactors = FALSE
  )
}

testthat::test_that("initial baseline and initial debt have distinct semantics", {
  healthy <- derive_operational_condition_transition(condition_observation("HEALTHY"))
  warning <- derive_operational_condition_transition(condition_observation("WARNING"))
  info <- derive_operational_condition_transition(condition_observation("INFO"))
  unknown <- derive_operational_condition_transition(condition_observation("UNKNOWN"))

  testthat::expect_identical(healthy$transition_event, "NONE")
  testthat::expect_identical(info$transition_event, "NONE")
  testthat::expect_identical(unknown$transition_event, "NONE")
  testthat::expect_identical(warning$transition_event, "INCIDENT_OPENED")
})

testthat::test_that("failure, running retry, repeated failure, and recovery do not duplicate incidents", {
  # RUNNING does not change the authoritative latest-terminal catalogue row, so
  # repeated CRITICAL observations represent both running retry and repeat poll.
  result <- run_condition_sequence(c("CRITICAL", "CRITICAL", "CRITICAL", "HEALTHY"))
  testthat::expect_identical(
    result$events, c("INCIDENT_OPENED", "INCIDENT_RECOVERED")
  )
  testthat::expect_identical(result$incident_count, 1L)
  testthat::expect_true(is.na(result$state$active_incident_id))
})

testthat::test_that("warning escalation downgrade and recovery preserve one incident", {
  result <- run_condition_sequence(c("WARNING", "CRITICAL", "WARNING", "HEALTHY"))
  testthat::expect_identical(
    result$events,
    c("INCIDENT_OPENED", "SEVERITY_ESCALATED", "SEVERITY_CHANGED", "INCIDENT_RECOVERED")
  )
  testthat::expect_identical(result$incident_count, 1L)
})

testthat::test_that("unknown preserves active incident and last actionable severity", {
  result <- run_condition_sequence(c("CRITICAL", "UNKNOWN", "WARNING", "HEALTHY"))
  testthat::expect_identical(
    result$events,
    c("INCIDENT_OPENED", "SEVERITY_CHANGED", "INCIDENT_RECOVERED")
  )
  testthat::expect_identical(result$incident_count, 1L)
})

testthat::test_that("info records observation without opening or closing debt incident", {
  inactive <- run_condition_sequence(c("INFO", "HEALTHY"))
  active <- run_condition_sequence(c("WARNING", "INFO", "HEALTHY"))
  testthat::expect_length(inactive$events, 0L)
  testthat::expect_identical(
    active$events, c("INCIDENT_OPENED", "INCIDENT_RECOVERED")
  )
})

testthat::test_that("later recurrence opens a distinct incident", {
  result <- run_condition_sequence(c("WARNING", "HEALTHY", "WARNING"))
  testthat::expect_identical(
    result$events, c("INCIDENT_OPENED", "INCIDENT_RECOVERED", "INCIDENT_OPENED")
  )
  testthat::expect_identical(result$incident_count, 2L)
})

testthat::test_that("regenerated timestamps and evidence changes do not invent transitions", {
  state <- condition_state(4, "WARNING")
  first <- condition_observation("WARNING", item_count = 1L, summary = "one")
  second <- condition_observation(
    "WARNING", item_count = 9L, summary = "changed",
    observed_at = as.POSIXct("2026-11-10 11:00:00", tz = "UTC")
  )
  testthat::expect_identical(
    derive_operational_condition_transition(first, state)$transition_event, "NONE"
  )
  testthat::expect_identical(
    derive_operational_condition_transition(second, state)$transition_event, "NONE"
  )
  testthat::expect_false(identical(
    operational_condition_evidence_signature(first),
    operational_condition_evidence_signature(second)
  ))
  timestamp_only <- first
  timestamp_only$observed_at_utc <- timestamp_only$observed_at_utc + 60
  testthat::expect_identical(
    operational_condition_evidence_signature(first),
    operational_condition_evidence_signature(timestamp_only)
  )
})

testthat::test_that("stale execution, Google recovery, and validation states use shared transitions", {
  stale <- condition_observation(
    "CRITICAL", "EXECUTION", "stale_pipeline_execution"
  )
  partial <- condition_observation(
    "WARNING", "RAW", "google_health_daily_ingestion_coverage"
  )
  complete <- condition_observation(
    "HEALTHY", "RAW", "google_health_daily_ingestion_coverage"
  )
  validation_unknown <- condition_observation(
    "UNKNOWN", "VALIDATION", "latest_validation"
  )
  testthat::expect_identical(
    derive_operational_condition_transition(stale)$transition_event, "INCIDENT_OPENED"
  )
  state <- advance_condition_state(NULL, partial, 1)$state
  testthat::expect_identical(
    derive_operational_condition_transition(complete, state)$transition_event,
    "INCIDENT_RECOVERED"
  )
  testthat::expect_identical(
    derive_operational_condition_transition(validation_unknown)$transition_event,
    "NONE"
  )
})

testthat::test_that("complete catalogue validation rejects malformed missing and duplicate rows", {
  catalogue <- complete_catalogue_fixture()
  testthat::expect_equal(nrow(validate_operational_debt_catalogue(catalogue)), 13L)
  testthat::expect_error(
    validate_operational_debt_catalogue(catalogue[, -1L]), "missing column"
  )
  testthat::expect_error(
    validate_operational_debt_catalogue(catalogue[-1L, ]), "identity mismatch"
  )
  testthat::expect_error(
    validate_operational_debt_catalogue(rbind(catalogue, catalogue[1L, ])),
    "duplicate condition identity"
  )
  malformed <- catalogue
  malformed$item_count[[1L]] <- -1L
  testthat::expect_error(
    validate_operational_debt_catalogue(malformed), "malformed"
  )
})

testthat::test_that("catalogue identity excludes volatile evidence", {
  expected <- operational_debt_expected_catalogue()
  testthat::expect_named(expected, c("debt_domain", "debt_key"))
  testthat::expect_equal(anyDuplicated(expected), 0L)
  testthat::expect_false(any(c(
    "run_id", "item_count", "summary", "observed_at_utc"
  ) %in% names(expected)))
})

testthat::test_that("migration and bootstrap publish identical durable tables", {
  bootstrap <- paste(readLines(condition_test_path(
    "sql", "admin", "110_create_operational_condition_state.sql"
  ), warn = FALSE), collapse = "\n")
  migration <- paste(readLines(condition_test_path(
    "sql", "migrations", "019_add_operational_condition_state.sql"
  ), warn = FALSE), collapse = "\n")
  for (table in c(
    "operational_condition_state", "operational_condition_incident",
    "operational_condition_event"
  )) {
    testthat::expect_match(bootstrap, paste0("CREATE TABLE IF NOT EXISTS cycling_platform_admin.", table), fixed = TRUE)
    testthat::expect_match(migration, paste0("CREATE TABLE IF NOT EXISTS cycling_platform_admin.", table), fixed = TRUE)
  }
  create_statements <- function(sql) {
    sql <- gsub("(?m)^--.*$", "", sql, perl = TRUE)
    statements <- trimws(strsplit(sql, ";[[:space:]]*", perl = TRUE)[[1L]])
    statements[grepl("^CREATE TABLE", statements)]
  }
  testthat::expect_identical(
    create_statements(bootstrap), create_statements(migration)
  )
  testthat::expect_match(migration, "UNIQUE KEY uq_operational_condition_event_sequence", fixed = TRUE)
  for (table in c(
    "operational_condition_state", "operational_condition_incident",
    "operational_condition_event"
  )) {
    testthat::expect_match(
      migration,
      paste0("ALTER TABLE cycling_platform_admin.", table),
      fixed = TRUE
    )
  }
})

testthat::test_that("evaluator is serialized and rolls back failed transactions", {
  body <- paste(deparse(evaluate_operational_conditions), collapse = "\n")
  state_reader <- paste(deparse(read_operational_condition_state), collapse = "\n")
  testthat::expect_match(body, "acquire_operational_condition_evaluator_lock", fixed = TRUE)
  testthat::expect_match(body, "validate_operational_debt_catalogue", fixed = TRUE)
  testthat::expect_lt(
    regexpr("validate_operational_debt_catalogue", body, fixed = TRUE)[[1L]],
    regexpr("dbBegin", body, fixed = TRUE)[[1L]]
  )
  testthat::expect_match(body, "dbRollback", fixed = TRUE)
  testthat::expect_match(body, "dbCommit", fixed = TRUE)
  testthat::expect_match(state_reader, "FOR UPDATE", fixed = TRUE)
})

testthat::test_that("preview entry point is read-only and evaluator has no delivery dependency", {
  preview_script <- paste(readLines(condition_test_path(
    "scripts", "operations", "preview_operational_conditions.R"
  ), warn = FALSE), collapse = "\n")
  preview_body <- paste(deparse(preview_operational_condition_evaluation), collapse = "\n")
  evaluator_file <- paste(readLines(condition_test_path(
    "R", "admin", "operational_condition_evaluator.R"
  ), warn = FALSE), collapse = "\n")
  testthat::expect_match(
    preview_script, "preview_operational_condition_evaluation", fixed = TRUE
  )
  testthat::expect_false(grepl("dbExecute|dbBegin|dbCommit|dbRollback", preview_body))
  testthat::expect_false(grepl("send_notification|ntfy|curl|notification_outbox", evaluator_file))
})

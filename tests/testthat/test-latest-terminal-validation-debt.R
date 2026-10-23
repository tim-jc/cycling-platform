validation_fixture <- function(
  statuses,
  outcomes = rep(NA_character_, length(statuses)),
  health = rep(NA_character_, length(statuses)),
  scopes = rep("DEEP", length(statuses)),
  completed_offsets = seq_along(statuses),
  started_offsets = seq_along(statuses)
) {
  completed <- as.POSIXct("2026-10-23 00:00:00", tz = "UTC") +
    completed_offsets * 60
  completed[statuses == "RUNNING"] <- as.POSIXct(NA, tz = "UTC")
  data.frame(
    validation_run_id = seq_along(statuses),
    validation_scope = scopes,
    run_status = statuses,
    validation_outcome = outcomes,
    health_status = health,
    started_at_utc = as.POSIXct("2026-10-23 00:00:00", tz = "UTC") +
      started_offsets * 60,
    completed_at_utc = completed,
    stringsAsFactors = FALSE
  )
}

latest_terminal_validation_fixture <- function(history) {
  if (nrow(history) == 0L) {
    return(data.frame(
      validation_scope = character(), health_status = character()
    ))
  }

  scopes <- unique(history$validation_scope)
  selected <- lapply(scopes, function(scope) {
    candidates <- history[
      history$validation_scope == scope &
        history$run_status %in% c("SUCCESS", "FAILED", "TIMED_OUT"),
      ,
      drop = FALSE
    ]
    if (nrow(candidates) == 0L) {
      return(data.frame(validation_scope = scope, health_status = "UNKNOWN"))
    }
    candidates <- candidates[order(
      candidates$completed_at_utc,
      candidates$validation_run_id,
      decreasing = TRUE,
      na.last = TRUE
    ), , drop = FALSE]
    candidates[1L, c("validation_scope", "health_status"), drop = FALSE]
  })
  do.call(rbind, selected)
}

validation_debt_fixture <- function(history) {
  selected <- latest_terminal_validation_fixture(history)
  if (nrow(selected) == 0L) {
    return(list(health_status = "HEALTHY", item_count = 0L))
  }
  ranks <- c(HEALTHY = 0L, UNKNOWN = 1L, WARNING = 3L, CRITICAL = 4L)
  health <- names(ranks)[match(max(unname(ranks[selected$health_status])), ranks)]
  list(
    health_status = health,
    item_count = as.integer(sum(selected$health_status != "HEALTHY"))
  )
}

validation_sql <- function(path = file.path(
  "sql", "admin", "100_create_operational_observability_views.sql"
)) {
  candidates <- c(path, file.path("..", "..", path))
  paste(readLines(candidates[file.exists(candidates)][1L], warn = FALSE), collapse = "\n")
}

testthat::test_that("no validation history preserves the existing healthy aggregate", {
  result <- validation_debt_fixture(validation_fixture(character()))
  testthat::expect_identical(result$health_status, "HEALTHY")
  testthat::expect_identical(result$item_count, 0L)
})

testthat::test_that("terminal outcomes retain governed health classifications", {
  cases <- list(
    PASSED = c("SUCCESS", "HEALTHY"),
    PASSED_WITH_WARNINGS = c("SUCCESS", "WARNING"),
    FAILED = c("FAILED", "CRITICAL"),
    TIMED_OUT = c("TIMED_OUT", "CRITICAL")
  )
  for (outcome in names(cases)) {
    history <- validation_fixture(
      cases[[outcome]][[1]], outcome, cases[[outcome]][[2]]
    )
    testthat::expect_identical(
      validation_debt_fixture(history)$health_status,
      cases[[outcome]][[2]]
    )
  }
})

testthat::test_that("running validation does not replace a terminal assessment", {
  for (terminal_health in c("CRITICAL", "WARNING", "HEALTHY")) {
    history <- validation_fixture(
      c(if (terminal_health == "CRITICAL") "FAILED" else "SUCCESS", "RUNNING"),
      c(NA, NA),
      c(terminal_health, "UNKNOWN")
    )
    testthat::expect_identical(
      validation_debt_fixture(history)$health_status,
      terminal_health
    )
  }
})

testthat::test_that("a later terminal assessment establishes the next state", {
  expected <- c(HEALTHY = "SUCCESS", CRITICAL = "FAILED", TIMED_OUT = "TIMED_OUT")
  for (label in names(expected)) {
    terminal_status <- unname(expected[[label]])
    final_health <- if (label == "HEALTHY") "HEALTHY" else "CRITICAL"
    history <- validation_fixture(
      c("FAILED", "RUNNING", terminal_status),
      health = c("CRITICAL", "UNKNOWN", final_health)
    )
    testthat::expect_identical(
      validation_debt_fixture(history)$health_status,
      final_health
    )
  }
})

testthat::test_that("multiple active executions leave terminal debt unchanged", {
  history <- validation_fixture(
    c("FAILED", "RUNNING", "RUNNING"),
    health = c("CRITICAL", "UNKNOWN", "UNKNOWN")
  )
  testthat::expect_identical(
    validation_debt_fixture(history)$health_status,
    "CRITICAL"
  )
})

testthat::test_that("an active-only scope remains unknown", {
  history <- validation_fixture(
    c("RUNNING", "RUNNING"),
    health = c("UNKNOWN", "UNKNOWN")
  )
  result <- validation_debt_fixture(history)
  testthat::expect_identical(result$health_status, "UNKNOWN")
  testthat::expect_identical(result$item_count, 1L)
})

testthat::test_that("validation scopes select terminal assessments independently", {
  history <- validation_fixture(
    c("SUCCESS", "RUNNING", "FAILED", "RUNNING"),
    health = c("HEALTHY", "UNKNOWN", "CRITICAL", "UNKNOWN"),
    scopes = c("PUBLICATION", "PUBLICATION", "DEEP", "DEEP")
  )
  selected <- latest_terminal_validation_fixture(history)
  testthat::expect_identical(
    selected$health_status[match("PUBLICATION", selected$validation_scope)],
    "HEALTHY"
  )
  testthat::expect_identical(
    selected$health_status[match("DEEP", selected$validation_scope)],
    "CRITICAL"
  )
  testthat::expect_identical(
    validation_debt_fixture(history)$health_status,
    "CRITICAL"
  )
})

testthat::test_that("completion order and ID tie-break govern overlapping runs", {
  out_of_order <- validation_fixture(
    c("FAILED", "SUCCESS"),
    health = c("CRITICAL", "HEALTHY"),
    completed_offsets = c(20, 10)
  )
  testthat::expect_identical(
    latest_terminal_validation_fixture(out_of_order)$health_status,
    "CRITICAL"
  )

  tied <- validation_fixture(
    c("FAILED", "SUCCESS"),
    health = c("CRITICAL", "HEALTHY"),
    completed_offsets = c(20, 20)
  )
  testthat::expect_identical(
    latest_terminal_validation_fixture(tied)$health_status,
    "HEALTHY"
  )
})

testthat::test_that("unknown latest terminal evidence is not bypassed", {
  history <- validation_fixture(
    c("SUCCESS", "SUCCESS"),
    outcomes = c("PASSED", NA),
    health = c("HEALTHY", "UNKNOWN")
  )
  result <- validation_debt_fixture(history)
  testthat::expect_identical(result$health_status, "UNKNOWN")
  testthat::expect_identical(result$item_count, 1L)
})

testthat::test_that("failed terminal execution remains critical with incomplete evidence", {
  history <- validation_fixture("FAILED", NA, "CRITICAL")
  testthat::expect_identical(
    validation_debt_fixture(history)$health_status,
    "CRITICAL"
  )
})

testthat::test_that("legacy, unsupported and informational assessments retain view semantics", {
  legacy <- validation_fixture("SUCCESS", NA, "WARNING")
  unsupported <- validation_fixture("SUCCESS", "UNSUPPORTED", "UNKNOWN")
  informational <- validation_fixture("SUCCESS", "PASSED", "HEALTHY")
  testthat::expect_identical(validation_debt_fixture(legacy)$health_status, "WARNING")
  testthat::expect_identical(validation_debt_fixture(unsupported)$health_status, "UNKNOWN")
  testthat::expect_identical(validation_debt_fixture(informational)$health_status, "HEALTHY")
})

testthat::test_that("stale running remains independent from latest assessment", {
  history <- validation_fixture(
    c("FAILED", "RUNNING"),
    health = c("CRITICAL", "UNKNOWN"),
    started_offsets = c(1, -500)
  )
  now <- as.POSIXct("2026-10-23 00:00:00", tz = "UTC")
  stale_count <- sum(
    history$run_status == "RUNNING" &
      history$started_at_utc < now - 6 * 60 * 60
  )
  testthat::expect_identical(validation_debt_fixture(history)$health_status, "CRITICAL")
  testthat::expect_identical(as.integer(stale_count), 1L)
})

testthat::test_that("an administratively reconciled abandoned run is terminal failure evidence", {
  history <- validation_fixture(
    c("SUCCESS", "FAILED"),
    outcomes = c("PASSED", "FAILED"),
    health = c("HEALTHY", "CRITICAL"),
    completed_offsets = c(10, 20)
  )
  testthat::expect_identical(
    validation_debt_fixture(history)$health_status,
    "CRITICAL"
  )
})

testthat::test_that("historical validation rows remain unchanged and visible", {
  history <- validation_fixture(
    c("FAILED", "RUNNING", "SUCCESS"),
    health = c("CRITICAL", "UNKNOWN", "HEALTHY")
  )
  original <- history
  validation_debt_fixture(history)
  testthat::expect_identical(history, original)
  testthat::expect_equal(nrow(history), 3L)
})

testthat::test_that("canonical SQL implements latest terminal scope selection", {
  sql <- validation_sql()
  testthat::expect_match(
    sql,
    "terminal.run_status IN ('SUCCESS', 'FAILED', 'TIMED_OUT')",
    fixed = TRUE
  )
  testthat::expect_match(sql, "PARTITION BY terminal.validation_scope", fixed = TRUE)
  testthat::expect_match(
    sql,
    "ORDER BY terminal.completed_at_utc DESC,",
    fixed = TRUE
  )
  testthat::expect_match(sql, "terminal.validation_run_id DESC", fixed = TRUE)
  testthat::expect_match(sql, "WHEN terminal.validation_run_id IS NULL THEN 'UNKNOWN'", fixed = TRUE)
  testthat::expect_false(grepl(
    "SELECT MAX(latest.validation_run_id)", sql, fixed = TRUE
  ))
  testthat::expect_match(sql, "INTERVAL 6 HOUR", fixed = TRUE)
})

testthat::test_that("pipeline, backup and public view contracts remain present", {
  sql <- validation_sql()
  for (text in c(
    "terminal.run_status IN ('SUCCESS', 'FAILED')",
    "FROM cycling_platform_admin.v_backup_health_latest",
    "CREATE OR REPLACE VIEW cycling_platform_admin.v_operational_debt_latest AS",
    "CREATE OR REPLACE VIEW cycling_platform_admin.v_platform_health_latest AS"
  )) testthat::expect_match(sql, text, fixed = TRUE)

  for (column in c(
    "debt_key", "debt_domain", "health_status", "item_count", "summary",
    "observed_at_utc"
  )) testthat::expect_match(sql, column, fixed = TRUE)
})

reconciliation_summary_source <- function() {
  path <- file.path("R", "utils", "format_activity_reconciliation_summary.R")
  if (!file.exists(path)) path <- file.path("..", "..", path)
  source(path)
}
reconciliation_summary_source()

testthat::test_that("integer64 reconciliation counts format as ordinary counts", {
  reconciliation <- data.frame(
    reconciliation_status = c("CHANGED", "UNCHANGED"),
    child_status = c("INCOMPLETE", "COMPLETE"),
    details_repair_required = bit64::as.integer64(c(3, 0)),
    streams_repair_required = bit64::as.integer64(c(3, 0)),
    laps_repair_required = bit64::as.integer64(c(3, 0)),
    activity_count = bit64::as.integer64(c(3, 17))
  )

  lines <- format_activity_reconciliation_summary(reconciliation)

  testthat::expect_equal(
    lines[[1]],
    "Reconciliation: examined 20 · new/recovered 0 · changed 3 · unchanged 17 · missing from source 0"
  )
  testthat::expect_equal(
    lines[[2]],
    "Selective repairs requested: details 3 · streams 3 · laps 3"
  )
  testthat::expect_false(any(grepl("e-", lines, fixed = TRUE)))
})

testthat::test_that("multiple child-status rows aggregate by reconciliation status", {
  reconciliation <- data.frame(
    reconciliation_status = c("CHANGED", "CHANGED", "MISSING"),
    child_status = c("COMPLETE", "INCOMPLETE", "COMPLETE"),
    details_repair_required = c(0, 1, 0),
    streams_repair_required = c(0, 1, 0),
    laps_repair_required = c(0, 1, 0),
    activity_count = c(2, 1, 4)
  )

  lines <- format_activity_reconciliation_summary(reconciliation)
  testthat::expect_match(lines[[1]], "examined 3", fixed = TRUE)
  testthat::expect_match(lines[[1]], "changed 3", fixed = TRUE)
  testthat::expect_match(lines[[1]], "missing from source 4", fixed = TRUE)
})

testthat::test_that("daily notification normalises database counts before aggregation", {
  root <- if (file.exists("run_daily_platform.R")) "." else file.path("..", "..")
  source_text <- paste(readLines(file.path(root, "run_daily_platform.R"), warn = FALSE), collapse = "\n")
  testthat::expect_match(
    source_text,
    "reconciliation <- normalise_activity_reconciliation_counts(reconciliation)",
    fixed = TRUE
  )
})

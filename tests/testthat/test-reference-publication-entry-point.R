find_reference_publication_project_root <- function() {
  candidates <- c(".", "../..")
  candidate <- candidates[file.exists(file.path(candidates, "bootstrap.R"))][1]
  normalizePath(candidate, mustWork = TRUE)
}

reference_publication_project_root <- find_reference_publication_project_root()
source(file.path(
  reference_publication_project_root,
  "R",
  "reference",
  "planned_events.R"
))
source(file.path(
  reference_publication_project_root,
  "R",
  "reference",
  "publish_reference_data.R"
))

reference_result <- function(
  inserted_events = 0L,
  updated_events = 0L,
  unchanged_events = 0L,
  inserted_stages = 0L,
  updated_stages = 0L,
  unchanged_stages = 0L,
  removed_stages = 0L
) {
  list(
    inserted_events = inserted_events,
    updated_events = updated_events,
    unchanged_events = unchanged_events,
    inserted_stages = inserted_stages,
    updated_stages = updated_stages,
    unchanged_stages = unchanged_stages,
    removed_stages = removed_stages
  )
}

testthat::test_that("aggregate publication invokes planned events once", {
  calls <- 0L
  messages <- character()
  result <- publish_reference_data(
    planned_events_publisher = function() {
      calls <<- calls + 1L
      reference_result(inserted_events = 1L)
    },
    log = function(message) messages <<- c(messages, message)
  )

  testthat::expect_equal(calls, 1L)
  testthat::expect_equal(result$planned_events$inserted_events, 1L)
  testthat::expect_true(any(grepl(
    "1 dataset published and validated",
    messages,
    fixed = TRUE
  )))
})

testthat::test_that("unchanged publication is a successful normal outcome", {
  messages <- character()
  result <- publish_reference_data(
    planned_events_publisher = function() {
      reference_result(unchanged_events = 3L, unchanged_stages = 4L)
    },
    log = function(message) messages <<- c(messages, message)
  )

  testthat::expect_equal(result$planned_events$unchanged_events, 3L)
  testthat::expect_equal(result$planned_events$unchanged_stages, 4L)
  testthat::expect_true(any(grepl(
    "events inserted 0, updated 0, unchanged 3",
    messages,
    fixed = TRUE
  )))
})

testthat::test_that("publisher and reconciliation failures propagate", {
  testthat::expect_error(
    publish_reference_data(
      planned_events_publisher = function() {
        stop("planned-events write failed")
      },
      log = function(...) NULL
    ),
    "planned-events write failed"
  )

  testthat::expect_error(
    publish_reference_data(
      planned_events_publisher = function() {
        stop("post-publication validation failed")
      },
      log = function(...) NULL
    ),
    "post-publication validation failed"
  )
})

testthat::test_that("canonical script is a thin platform-owned entry point", {
  path <- file.path(
    reference_publication_project_root,
    "scripts",
    "reference",
    "publish_reference_data.R"
  )
  text <- paste(readLines(path, warn = FALSE), collapse = "\n")

  testthat::expect_match(text, 'source("bootstrap.R")', fixed = TRUE)
  testthat::expect_match(text, "publish_reference_data()", fixed = TRUE)
  testthat::expect_false(grepl("publish_planned_events(", text, fixed = TRUE))
})

testthat::test_that("Reference publication is absent from scheduled entry points", {
  scheduled_paths <- c(
    "run_daily_platform.R",
    "run_raw_ingestion.R",
    "run_silver.R",
    "R/transforms/run_silver_transformations.R",
    "R/transforms/run_gold_transformations.R"
  )
  scheduled_text <- paste(unlist(lapply(
    file.path(reference_publication_project_root, scheduled_paths),
    readLines,
    warn = FALSE
  )), collapse = "\n")

  testthat::expect_false(grepl(
    "publish_reference_data",
    scheduled_text,
    fixed = TRUE
  ))
  testthat::expect_false(grepl(
    "run_planned_events_publication",
    scheduled_text,
    fixed = TRUE
  ))
})

testthat::test_that("planned-events runner retains publisher validation result", {
  connected <- 0L
  disconnected <- 0L
  received_events <- NULL
  events <- list(list(event_key = "fixture"))

  result <- run_planned_events_publication(
    events = events,
    connect = function(database_name) {
      connected <<- connected + 1L
      testthat::expect_identical(
        database_name,
        "cycling_platform_reference"
      )
      "connection"
    },
    disconnect = function(connection) {
      disconnected <<- disconnected + 1L
    },
    publisher = function(connection, value) {
      testthat::expect_identical(connection, "connection")
      received_events <<- value
      reference_result(unchanged_events = 1L)
    }
  )

  testthat::expect_equal(connected, 1L)
  testthat::expect_equal(disconnected, 1L)
  testthat::expect_identical(received_events, events)
  testthat::expect_equal(result$unchanged_events, 1L)
})

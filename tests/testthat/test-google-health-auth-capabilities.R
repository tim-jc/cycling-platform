find_google_health_test_root <- function() {
  candidates <- c(".", "../..")
  root <- candidates[file.exists(file.path(
    candidates,
    "R",
    "api",
    "get_google_health_access_token.R"
  ))][1]
  normalizePath(root, mustWork = TRUE)
}

google_health_test_root <- find_google_health_test_root()
source(file.path(
  google_health_test_root,
  "R",
  "api",
  "get_google_health_access_token.R"
))
source(file.path(
  google_health_test_root,
  "R",
  "api",
  "get_google_health_exercise.R"
))
source(file.path(
  google_health_test_root,
  "R",
  "api",
  "probe_google_health_capabilities.R"
))

google_health_json_response <- function(body, status = 200L) {
  httr2::response(
    status_code = status,
    headers = list(`content-type` = "application/json"),
    body = charToRaw(jsonlite::toJSON(body, auto_unbox = TRUE))
  )
}

testthat::test_that("required Google Health scopes are canonical and narrow", {
  scopes <- google_health_required_scopes()
  testthat::expect_setequal(scopes, c(
    "https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly",
    "https://www.googleapis.com/auth/googlehealth.sleep.readonly",
    "https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly"
  ))
  testthat::expect_false(any(grepl("cloud-platform", scopes, fixed = TRUE)))
})

testthat::test_that("authentication check validates and reports required scopes", {
  token <- "access-token-must-not-appear"
  refresh <- "refresh-token-must-not-appear"
  secret <- "client-secret-must-not-appear"
  output <- testthat::capture_messages(
    report <- check_google_health_authentication(
      access_token_fetcher = function(verbose) token,
      scope_fetcher = function(access_token) google_health_required_scopes(),
      verbose = TRUE
    )
  )

  testthat::expect_true(report$valid)
  testthat::expect_match(paste(output, collapse = "\n"), "Required scopes: 3")
  testthat::expect_match(
    paste(output, collapse = "\n"),
    "Granted required scopes: 3"
  )
  visible <- paste(output, collapse = "\n")
  testthat::expect_false(grepl(token, visible, fixed = TRUE))
  testthat::expect_false(grepl(refresh, paste(output, collapse = "\n"), fixed = TRUE))
  testthat::expect_false(grepl(secret, paste(output, collapse = "\n"), fixed = TRUE))
})

testthat::test_that("authentication check fails for a missing required scope", {
  granted <- setdiff(
    google_health_required_scopes(),
    "https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly"
  )
  testthat::expect_error(
    check_google_health_authentication(
      access_token_fetcher = function(verbose) "opaque-token",
      scope_fetcher = function(access_token) granted,
      verbose = FALSE
    ),
    "activity_and_fitness[.]readonly"
  )
})

testthat::test_that("authentication check preserves refresh failure", {
  testthat::expect_error(
    check_google_health_authentication(
      access_token_fetcher = function(verbose) stop("invalid_grant"),
      scope_fetcher = function(access_token) character(),
      verbose = FALSE
    ),
    "invalid_grant"
  )
})

testthat::test_that("token metadata scope parsing supports Google response", {
  scopes <- google_health_required_scopes()
  response <- google_health_json_response(list(scope = paste(scopes, collapse = " ")))
  actual <- get_google_health_granted_scopes(
    "opaque-token",
    request_perform = function(request) response
  )
  testthat::expect_setequal(actual, scopes)
})

testthat::test_that("Exercise interval filter uses session semantics", {
  filter <- google_health_interval_filter(
    "exercise",
    as.Date("2026-08-01"),
    as.Date("2026-08-08")
  )
  testthat::expect_match(filter, "exercise[.]interval[.]start_time", perl = TRUE)
  testthat::expect_match(filter, "2026-08-01T00:00:00Z", fixed = TRUE)
  testthat::expect_match(filter, "2026-08-08T00:00:00Z", fixed = TRUE)
  testthat::expect_false(grepl("sample_time", filter, fixed = TRUE))
})

testthat::test_that("Exercise probe reports records and zero-record access", {
  config <- list()
  with_records <- function(path, config, query, token) {
    google_health_json_response(list(dataPoints = list(
      list(name = "exercise/one"),
      list(name = "exercise/two")
    )))
  }
  empty <- function(path, config, query, token) {
    google_health_json_response(list(dataPoints = list()))
  }
  clock_values <- as.POSIXct(
    c("2026-08-15 10:00:00", "2026-08-15 10:00:01"),
    tz = "UTC"
  )
  clock <- local({
    index <- 0L
    function() {
      index <<- index + 1L
      clock_values[[index]]
    }
  })
  probe_result <- suppressMessages(run_google_health_capability_probe(
    probe_name = "Exercise",
    data_type = "exercise",
    filter = "exercise.interval.start_time >= x",
    page_size = 100L,
    google_user_id = "me",
    config = config,
    token = "opaque",
    request_performer = with_records,
    clock = clock
  ))
  testthat::expect_equal(probe_result$data_point_count, 2L)
  testthat::expect_match(
    format_google_health_exercise_capability(probe_result),
    "2 data points",
    fixed = TRUE
  )

  empty_result <- google_health_probe_data_points(
    "exercise", "filter", 100L, "me", config, "opaque",
    request_performer = empty
  )
  testthat::expect_equal(empty_result$data_point_count, 0L)
  testthat::expect_match(
    format_google_health_exercise_capability(empty_result),
    "accessible, zero records",
    fixed = TRUE
  )
})

testthat::test_that("Exercise permission failure is reported without token", {
  result <- suppressMessages(run_google_health_capability_probe(
    "Exercise",
    "exercise",
    "filter",
    100L,
    "me",
    list(),
    "access-token-secret",
    request_performer = function(...) stop("permission denied"),
    clock = local({
      values <- as.POSIXct(c("2026-08-15 10:00:00", "2026-08-15 10:00:01"), tz = "UTC")
      index <- 0L
      function() {
        index <<- index + 1L
        values[[index]]
      }
    })
  ))
  formatted <- format_google_health_exercise_capability(result)
  testthat::expect_false(result$success)
  testthat::expect_match(formatted, "permission denied", fixed = TRUE)
  testthat::expect_false(grepl("access-token-secret", formatted, fixed = TRUE))
})

testthat::test_that("capability probe provides conventional help", {
  script <- file.path(
    google_health_test_root,
    "scripts",
    "google_health",
    "probe_capabilities.R"
  )
  output <- system2(
    file.path(R.home("bin"), "Rscript"),
    c("--vanilla", shQuote(script), "--help"),
    stdout = TRUE,
    stderr = TRUE
  )
  testthat::expect_equal(attr(output, "status") %||% 0L, 0L)
  testthat::expect_match(paste(output, collapse = "\n"), "Usage:")
  testthat::expect_match(paste(output, collapse = "\n"), "Exercise capability")
})

testthat::test_that("production authentication runbook uses durable paths and wrapper", {
  runbook <- paste(readLines(
    file.path(google_health_test_root, "docs", "google_health_authentication.md"),
    warn = FALSE
  ), collapse = "\n")
  testthat::expect_match(
    runbook,
    "/srv/cycling/config/platform/runtime.Renviron",
    fixed = TRUE
  )
  testthat::expect_match(
    runbook,
    "/run/cycling-platform/runtime.Renviron",
    fixed = TRUE
  )
  testthat::expect_match(
    runbook,
    "scripts/compose.sh run --rm cycling-platform",
    fixed = TRUE
  )
  testthat::expect_match(runbook, "tim:tim", fixed = TRUE)
  testthat::expect_match(runbook, "0600", fixed = TRUE)
  testthat::expect_match(
    runbook,
    "place it outside\n   `/srv/cycling/config/platform`",
    fixed = TRUE
  )
  testthat::expect_match(
    runbook,
    "~/credential-backups/cycling-platform/",
    fixed = TRUE
  )
})

testthat::test_that("authentication entry point never formats token prefixes", {
  script <- paste(readLines(
    file.path(
      google_health_test_root,
      "scripts",
      "google_health",
      "check_authentication.R"
    ),
    warn = FALSE
  ), collapse = "\n")
  testthat::expect_false(grepl("access token prefix", script, ignore.case = TRUE))
  testthat::expect_false(grepl("substr\\s*\\(", script, perl = TRUE))
})

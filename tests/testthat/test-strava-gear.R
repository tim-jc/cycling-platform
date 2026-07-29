gear_source <- function(path) {
  candidate <- file.path("R", path)
  if (!file.exists(candidate)) {
    candidate <- file.path("..", "..", "R", path)
  }
  source(candidate)
}

gear_source(file.path("api", "get_gear.R"))
gear_source(file.path("quality", "report_gear_resolution.R"))

testthat::test_that("gear parser preserves detailed bike payload and lineage", {
  observed_at <- as.POSIXct("2026-07-29 10:00:00", tz = "UTC")
  gear <- list(
    id = "b1",
    name = "Road bike",
    primary = TRUE,
    distance = 1234.5,
    resource_state = 3L,
    brand_name = "BMC",
    model_name = "Teammachine",
    frame_type = 3L,
    description = "Race bike"
  )

  parsed <- parse_strava_gear(
    gear, "bike", TRUE, observed_at, run_id = 9L, source_id = 1L
  )

  testthat::expect_equal(parsed$gear_id, "b1")
  testthat::expect_equal(parsed$gear_type, "bike")
  testthat::expect_equal(parsed$gear_name, "Road bike")
  testthat::expect_true(parsed$is_primary)
  testthat::expect_equal(parsed$distance_metres, 1234.5)
  testthat::expect_equal(nchar(parsed$payload_hash), 64L)
  testthat::expect_match(parsed$source_payload, "Teammachine")
  testthat::expect_equal(parsed$first_observed_at, observed_at)
})

testthat::test_that("gear parser supports shoes, unknown, and missing optionals", {
  shoe <- parse_strava_gear(
    list(id = "g1", name = "Trail shoes"),
    "shoes", TRUE, Sys.time(), 1L, 1L
  )
  historical <- parse_strava_gear(
    list(id = "old1", name = "Retired bike"),
    "unknown", FALSE, Sys.time(), 1L, 1L
  )

  testthat::expect_equal(shoe$gear_type, "shoes")
  testthat::expect_true(is.na(shoe$brand_name))
  testthat::expect_equal(historical$gear_type, "unknown")
  testthat::expect_false(historical$observed_in_current_collection)
  testthat::expect_error(
    parse_strava_gear(list(id = "b1"), "bike", TRUE, Sys.time(), 1L, 1L),
    "Malformed"
  )
  testthat::expect_error(
    parse_strava_gear(list(id = "b1", name = "Bike"), "horse", TRUE,
                      Sys.time(), 1L, 1L)
  )
})

testthat::test_that("identical payloads hash identically and changes retain history", {
  base <- list(id = "b1", name = "Bike", primary = TRUE, distance = 10)
  first <- parse_strava_gear(base, "bike", TRUE, Sys.time(), 1L, 1L)
  repeated <- parse_strava_gear(base, "bike", TRUE, Sys.time(), 2L, 1L)
  renamed <- parse_strava_gear(
    utils::modifyList(base, list(name = "Renamed")),
    "bike", TRUE, Sys.time(), 3L, 1L
  )
  distance_changed <- parse_strava_gear(
    utils::modifyList(base, list(distance = 11)),
    "bike", TRUE, Sys.time(), 4L, 1L
  )
  primary_changed <- parse_strava_gear(
    utils::modifyList(base, list(primary = FALSE)),
    "bike", TRUE, Sys.time(), 5L, 1L
  )

  testthat::expect_identical(first$payload_hash, repeated$payload_hash)
  testthat::expect_false(first$payload_hash == renamed$payload_hash)
  testthat::expect_false(first$payload_hash == distance_changed$payload_hash)
  testthat::expect_false(first$payload_hash == primary_changed$payload_hash)
})

testthat::test_that("Silver reference model selects latest and retains historical gear", {
  times <- as.POSIXct(
    c("2026-07-01", "2026-07-02", "2026-07-03"),
    tz = "UTC"
  )
  observations <- dplyr::bind_rows(
    parse_strava_gear(
      list(id = "b1", name = "Old name", distance = 10),
      "bike", TRUE, times[[1]], 1L, 1L
    ),
    parse_strava_gear(
      list(id = "b1", name = "New name", distance = 20),
      "bike", TRUE, times[[2]], 2L, 1L
    ),
    parse_strava_gear(
      list(id = "old", name = "Retired"),
      "unknown", FALSE, times[[3]], 2L, 1L
    )
  )

  silver <- build_silver_gear_rows(observations, 2L)

  testthat::expect_equal(nrow(silver), 2L)
  testthat::expect_equal(silver$gear_name[silver$gear_id == "b1"], "New name")
  testthat::expect_equal(
    silver$first_observed_at[silver$gear_id == "b1"],
    times[[1]]
  )
  testthat::expect_true(silver$is_current[silver$gear_id == "b1"])
  testthat::expect_true(silver$is_historical[silver$gear_id == "old"])
  testthat::expect_equal(unique(silver$resolution_status), "RESOLVED")
})

testthat::test_that("failed run cannot retire prior current gear", {
  observation <- parse_strava_gear(
    list(id = "b1", name = "Bike"),
    "bike", TRUE, Sys.time(), 10L, 1L
  )

  # A failed run 11 is deliberately not supplied as latest_successful_run_id.
  silver <- build_silver_gear_rows(observation, 10L)
  testthat::expect_true(silver$is_current)
})

testthat::test_that("ride-summary display contract is explicit", {
  testthat::expect_equal(
    resolve_activity_gear_name(c("b1", NA, "missing"), c("Road bike", NA, NA)),
    c("Road bike", "Not recorded", "Unknown gear (missing)")
  )
})

testthat::test_that("gear DDL and transform encode history and safe disappearance", {
  root <- if (dir.exists("sql")) "." else file.path("..", "..")
  raw_sql <- readLines(
    file.path(root, "sql", "raw", "050_create_strava_gear_observations.sql")
  )
  silver_sql <- readLines(
    file.path(root, "sql", "silver", "050_transform_gear.sql")
  )
  raw_text <- paste(raw_sql, collapse = "\n")
  silver_text <- paste(silver_sql, collapse = "\n")

  testthat::expect_match(raw_text, "UNIQUE KEY uq_gear_observation_payload")
  testthat::expect_match(raw_text, "gear_resolution_attempts")
  testthat::expect_match(silver_text, "entity_status = 'SUCCESS'", fixed = TRUE)
  testthat::expect_match(silver_text, "ROW_NUMBER()")
  testthat::expect_false(grepl(" AS row_number", silver_text, ignore.case = TRUE))

  transform_file <- file.path(
    root, "R", "transforms", "rebuild_silver_gear.R"
  )
  transform_text <- paste(readLines(transform_file), collapse = "\n")
  testthat::expect_match(transform_text, "DBI::dbWithTransaction", fixed = TRUE)
})

testthat::test_that("gear client fetches current and historical IDs once", {
  paths <- character()
  responses <- list(
    "/athlete" = list(
      bikes = list(list(id = "b1")),
      shoes = list(list(id = "g1"))
    ),
    "/gear/b1" = list(id = "b1", name = "Bike"),
    "/gear/g1" = list(id = "g1", name = "Shoes"),
    "/gear/old" = list(id = "old", name = "Old bike")
  )
  request_fn <- function(path, config, token) {
    paths <<- c(paths, path)
    responses[[path]]
  }

  result <- get_gear(
    run_id = 1L,
    source_id = 1L,
    activity_gear_ids = c("b1", "old", "old"),
    config = list(),
    token_fn = function() "token",
    request_fn = request_fn,
    body_fn = identity
  )

  testthat::expect_equal(result$source_records, 2L)
  testthat::expect_equal(result$historical_lookup_count, 1L)
  testthat::expect_equal(result$request_count, 4L)
  testthat::expect_setequal(result$observations$gear_id, c("b1", "g1", "old"))
  testthat::expect_equal(
    result$observations$gear_type[result$observations$gear_id == "old"],
    "unknown"
  )
  testthat::expect_equal(sum(paths == "/gear/old"), 1L)
})

testthat::test_that("gear client handles empty collection and explicit not found", {
  request_fn <- function(path, config, token) {
    if (identical(path, "/athlete")) {
      return(list(bikes = list(), shoes = list()))
    }
    error <- simpleError("not found")
    error$status_code <- 404L
    stop(error)
  }

  result <- get_gear(
    1L, 1L, "retired", list(),
    token_fn = function() "token",
    request_fn = request_fn,
    body_fn = identity
  )

  testthat::expect_equal(nrow(result$observations), 0L)
  testthat::expect_equal(result$unresolved$gear_id, "retired")
  testthat::expect_equal(result$unresolved$resolution_status, "NOT_FOUND")
})

testthat::test_that("gear client fails clearly for scope, auth, and partial failure", {
  missing_scope <- function(path, config, token) list(id = 1)
  testthat::expect_error(
    get_gear(
      1L, 1L, character(), list(),
      token_fn = function() "token",
      request_fn = missing_scope,
      body_fn = identity
    ),
    "profile:read_all"
  )

  auth_failure <- function(path, config, token) stop("401 Unauthorized")
  testthat::expect_error(
    get_gear(
      1L, 1L, character(), list(),
      token_fn = function() "token",
      request_fn = auth_failure,
      body_fn = identity
    ),
    "401"
  )

  partial <- function(path, config, token) {
    if (identical(path, "/athlete")) {
      return(list(bikes = list(list(id = "b1")), shoes = list()))
    }
    stop("503 retry exhausted")
  }
  testthat::expect_error(
    get_gear(
      1L, 1L, character(), list(),
      token_fn = function() "token",
      request_fn = partial,
      body_fn = identity
    ),
    "503"
  )

  incomplete_current <- function(path, config, token) {
    if (identical(path, "/athlete")) {
      return(list(bikes = list(list(id = "b1")), shoes = list()))
    }
    error <- simpleError("not found")
    error$status_code <- 404L
    stop(error)
  }
  testthat::expect_error(
    get_gear(
      1L, 1L, character(), list(),
      token_fn = function() "token",
      request_fn = incomplete_current,
      body_fn = identity
    ),
    "refusing an incomplete current snapshot"
  )
})

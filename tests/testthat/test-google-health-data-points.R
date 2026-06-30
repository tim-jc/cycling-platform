testthat::test_that("Google Health payload JSON preserves numeric precision", {
  get_google_health_file <- file.path(
    "R",
    "api",
    "get_google_health_data_points.R"
  )

  if (!file.exists(get_google_health_file)) {
    get_google_health_file <- file.path(
      "..",
      "..",
      "R",
      "api",
      "get_google_health_data_points.R"
    )
  }

  source(
    get_google_health_file
  )

  payload <- google_health_payload_to_json(
    list(
      value = 53.196583
    )
  )

  testthat::expect_true(
    grepl(
      "53.196583",
      payload,
      fixed = TRUE
    )
  )

  testthat::expect_false(
    grepl(
      "53.1966",
      payload,
      fixed = TRUE
    )
  )
})

testthat::test_that("Google Health heart-rate API responses are shaped for raw loading", {
  get_google_health_file <- file.path(
    "R",
    "api",
    "get_google_health_data_points.R"
  )

  if (!file.exists(get_google_health_file)) {
    get_google_health_file <- file.path(
      "..",
      "..",
      "R",
      "api",
      "get_google_health_data_points.R"
    )
  }

  source(
    get_google_health_file
  )

  response_payload <- list(
    data_type = "heart-rate",
    filter = "heart_rate.sample_time.physical_time >= \"2026-06-27T00:00:00Z\"",
    page_count = 1L,
    pages = list(
      list(
        dataPoints = list(
          list(
            name = "users/me/dataTypes/heart-rate/dataPoints/example",
            dataSource = list(
              name = "fitbit-air"
            ),
            heartRate = list(
              beatsPerMinute = "61",
              sampleTime = list(
                physicalTime = "2026-06-27T06:30:00.847416Z",
                utcOffset = "+01:00"
              )
            )
          )
        )
      )
    )
  )

  shaped <- google_health_shape_heart_rate_response(
    response_payload = response_payload,
    fitbit_user_id = "me",
    activity_date = as.Date("2026-06-27"),
    detail_level = "data_points",
    run_id = 1L,
    source_id = 2L,
    retrieved_at = as.POSIXct(
      "2026-06-27 06:31:00",
      tz = "UTC"
    )
  )

  testthat::expect_equal(
    nrow(shaped),
    1L
  )

  testthat::expect_equal(
    shaped$source_id[[1]],
    2L
  )

  testthat::expect_equal(
    shaped$fitbit_user_id[[1]],
    "me"
  )

  testthat::expect_equal(
    as.character(shaped$activity_date[[1]]),
    "2026-06-27"
  )

  testthat::expect_equal(
    shaped$detail_level[[1]],
    "data_points"
  )

  testthat::expect_true(
    is.na(shaped$dataset_interval[[1]])
  )

  testthat::expect_true(
    grepl(
      "\"page_count\":1",
      shaped$heart_rate_payload[[1]],
      fixed = TRUE
    )
  )

  testthat::expect_true(
    grepl(
      "\"beatsPerMinute\":\"61\"",
      shaped$heart_rate_payload[[1]],
      fixed = TRUE
    )
  )
})

testthat::test_that("Google Health heart-rate response natural key split works", {
  split_existing_rows_file <- file.path(
    "R",
    "database",
    "split_existing_rows.R"
  )

  if (!file.exists(split_existing_rows_file)) {
    split_existing_rows_file <- file.path(
      "..",
      "..",
      "R",
      "database",
      "split_existing_rows.R"
    )
  }

  source(
    split_existing_rows_file
  )

  incoming <- tibble::tibble(
    source_id = c(2L, 2L),
    fitbit_user_id = c("me", "me"),
    activity_date = as.Date(c("2026-06-27", "2026-06-28")),
    detail_level = c("data_points", "data_points"),
    run_id = c(1L, 1L)
  )

  existing <- tibble::tibble(
    source_id = 2L,
    fitbit_user_id = "me",
    activity_date = as.Date("2026-06-27"),
    detail_level = "data_points"
  )

  split <- split_existing_rows(
    data = incoming,
    existing_keys = existing,
    key_columns = c(
      "source_id",
      "fitbit_user_id",
      "activity_date",
      "detail_level"
    )
  )

  testthat::expect_equal(
    nrow(split$to_insert),
    1L
  )

  testthat::expect_equal(
    nrow(split$to_update),
    1L
  )

  testthat::expect_true(
    split$to_insert$activity_date[[1]] == as.Date("2026-06-28")
  )
})

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

testthat::test_that("Google Health heart-rate data points are shaped for raw loading", {
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

  data_points <- list(
    list(
      name = "users/me/dataTypes/heart-rate/dataPoints/example",
      dataSource = list(
        name = "fitbit-air"
      ),
      heartRate = list(
        beatsPerMinute = "61",
        sampleTime = list(
          physicalTime = "2026-06-27T06:30:00Z",
          utcOffset = "+01:00",
          civilDate = list(
            year = 2026,
            month = 6,
            day = 27
          )
        )
      )
    )
  )

  shaped <- google_health_shape_data_points(
    data_points = data_points,
    data_type = "heart-rate",
    google_user_id = "me",
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
    nchar(shaped$data_point_key[[1]]),
    64L
  )

  testthat::expect_equal(
    shaped$data_type[[1]],
    "heart-rate"
  )

  testthat::expect_equal(
    shaped$value_name[[1]],
    "beats_per_minute"
  )

  testthat::expect_equal(
    shaped$value_numeric[[1]],
    61
  )

  testthat::expect_equal(
    as.character(shaped$sample_civil_date[[1]]),
    "2026-06-27"
  )

  testthat::expect_true(
    grepl(
      "\"beatsPerMinute\":\"61\"",
      shaped$data_point_payload[[1]],
      fixed = TRUE
    )
  )
})

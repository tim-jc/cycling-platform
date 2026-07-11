testthat::test_that("Google Health daily RHR payloads are shaped for raw loading", {
  data_points_file <- file.path(
    "R",
    "api",
    "get_google_health_data_points.R"
  )

  daily_file <- file.path(
    "R",
    "api",
    "get_google_health_daily_summaries.R"
  )

  if (!file.exists(data_points_file)) {
    data_points_file <- file.path(
      "..",
      "..",
      "R",
      "api",
      "get_google_health_data_points.R"
    )
  }

  if (!file.exists(daily_file)) {
    daily_file <- file.path(
      "..",
      "..",
      "R",
      "api",
      "get_google_health_daily_summaries.R"
    )
  }

  source(data_points_file)
  source(daily_file)

  payloads <- list(
    list(
      dataSource = list(
        name = "fitbit-air"
      ),
      dailyRestingHeartRate = list(
        date = list(
          year = 2026,
          month = 7,
          day = 10
        ),
        beatsPerMinute = "46",
        dailyRestingHeartRateMetadata = list(
          calculationMethod = "WITH_SLEEP"
        )
      )
    ),
    list(
      name = "users/me/dataTypes/daily-resting-heart-rate/dataPoints/example",
      dataSource = list(
        name = "fitbit-air"
      ),
      dailyRestingHeartRate = list(
        date = list(
          year = 2026,
          month = 7,
          day = 10
        ),
        beatsPerMinute = "47",
        dailyRestingHeartRateMetadata = list(
          calculationMethod = "WITH_SLEEP"
        )
      )
    )
  )

  shaped <- google_health_shape_daily_resting_heart_rate(
    data_points = payloads,
    google_health_user_id = "me",
    run_id = 1L,
    source_id = 2L,
    retrieved_at = as.POSIXct(
      "2026-07-11 06:00:00",
      tz = "UTC"
    )
  )

  testthat::expect_equal(nrow(shaped), 2L)
  testthat::expect_equal(as.character(shaped$activity_date[[1]]), "2026-07-10")
  testthat::expect_equal(shaped$resting_heart_rate_bpm[[1]], 46)
  testthat::expect_equal(shaped$calculation_method[[1]], "WITH_SLEEP")
  testthat::expect_true(is.na(shaped$source_data_point_id[[1]]))
  testthat::expect_equal(length(unique(shaped$daily_resting_heart_rate_key)), 2L)
  testthat::expect_equal(nchar(shaped$daily_resting_heart_rate_key[[1]]), 64L)
  testthat::expect_true(
    grepl(
      "\"dailyRestingHeartRate\"",
      shaped$daily_resting_heart_rate_payload[[1]],
      fixed = TRUE
    )
  )

  shaped_again <- google_health_shape_daily_resting_heart_rate(
    data_points = payloads,
    google_health_user_id = "me",
    run_id = 2L,
    source_id = 2L,
    retrieved_at = as.POSIXct(
      "2026-07-11 07:00:00",
      tz = "UTC"
    )
  )

  testthat::expect_equal(
    shaped$daily_resting_heart_rate_key,
    shaped_again$daily_resting_heart_rate_key
  )
})

testthat::test_that("Google Health daily RHR empty responses shape cleanly", {
  data_points_file <- file.path(
    "R",
    "api",
    "get_google_health_data_points.R"
  )

  daily_file <- file.path(
    "R",
    "api",
    "get_google_health_daily_summaries.R"
  )

  if (!file.exists(data_points_file)) {
    data_points_file <- file.path(
      "..",
      "..",
      "R",
      "api",
      "get_google_health_data_points.R"
    )
  }

  if (!file.exists(daily_file)) {
    daily_file <- file.path(
      "..",
      "..",
      "R",
      "api",
      "get_google_health_daily_summaries.R"
    )
  }

  source(data_points_file)
  source(daily_file)

  shaped <- google_health_shape_daily_resting_heart_rate(
    data_points = list(),
    google_health_user_id = "me",
    run_id = 1L,
    source_id = 2L,
    retrieved_at = Sys.time()
  )

  testthat::expect_equal(nrow(shaped), 0L)
  testthat::expect_true("daily_resting_heart_rate_key" %in% names(shaped))
})

testthat::test_that("Google Health daily HRV payloads are shaped for raw loading", {
  data_points_file <- file.path(
    "R",
    "api",
    "get_google_health_data_points.R"
  )

  daily_file <- file.path(
    "R",
    "api",
    "get_google_health_daily_summaries.R"
  )

  if (!file.exists(data_points_file)) {
    data_points_file <- file.path(
      "..",
      "..",
      "R",
      "api",
      "get_google_health_data_points.R"
    )
  }

  if (!file.exists(daily_file)) {
    daily_file <- file.path(
      "..",
      "..",
      "R",
      "api",
      "get_google_health_daily_summaries.R"
    )
  }

  source(data_points_file)
  source(daily_file)

  payloads <- list(
    list(
      dataSource = list(
        name = "fitbit-air"
      ),
      dailyHeartRateVariability = list(
        date = list(
          year = 2026,
          month = 7,
          day = 10
        ),
        averageHeartRateVariabilityMilliseconds = "39",
        deepSleepRootMeanSquareOfSuccessiveDifferencesMilliseconds = "31.2",
        nonRemHeartRateBeatsPerMinute = "52",
        entropy = "3.2"
      )
    ),
    list(
      dataSource = list(
        name = "fitbit-air"
      ),
      dailyHeartRateVariability = list(
        date = list(
          year = 2026,
          month = 7,
          day = 10
        ),
        averageHeartRateVariabilityMilliseconds = "40"
      )
    )
  )

  shaped <- google_health_shape_daily_heart_rate_variability(
    data_points = payloads,
    google_health_user_id = "me",
    run_id = 1L,
    source_id = 2L,
    retrieved_at = as.POSIXct(
      "2026-07-11 06:00:00",
      tz = "UTC"
    )
  )

  testthat::expect_equal(nrow(shaped), 2L)
  testthat::expect_equal(as.character(shaped$activity_date[[1]]), "2026-07-10")
  testthat::expect_equal(shaped$average_hrv_milliseconds[[1]], 39)
  testthat::expect_equal(shaped$deep_sleep_rmssd_milliseconds[[1]], 31.2)
  testthat::expect_equal(shaped$non_rem_heart_rate_bpm[[1]], 52)
  testthat::expect_equal(shaped$entropy[[1]], 3.2)
  testthat::expect_true(is.na(shaped$deep_sleep_rmssd_milliseconds[[2]]))
  testthat::expect_equal(length(unique(shaped$daily_heart_rate_variability_key)), 2L)
  testthat::expect_equal(nchar(shaped$daily_heart_rate_variability_key[[1]]), 64L)
  testthat::expect_true(
    grepl(
      "\"dailyHeartRateVariability\"",
      shaped$daily_heart_rate_variability_payload[[1]],
      fixed = TRUE
    )
  )
})

testthat::test_that("Google Health daily HRV empty responses shape cleanly", {
  data_points_file <- file.path(
    "R",
    "api",
    "get_google_health_data_points.R"
  )

  daily_file <- file.path(
    "R",
    "api",
    "get_google_health_daily_summaries.R"
  )

  if (!file.exists(data_points_file)) {
    data_points_file <- file.path(
      "..",
      "..",
      "R",
      "api",
      "get_google_health_data_points.R"
    )
  }

  if (!file.exists(daily_file)) {
    daily_file <- file.path(
      "..",
      "..",
      "R",
      "api",
      "get_google_health_daily_summaries.R"
    )
  }

  source(data_points_file)
  source(daily_file)

  shaped <- google_health_shape_daily_heart_rate_variability(
    data_points = list(),
    google_health_user_id = "me",
    run_id = 1L,
    source_id = 2L,
    retrieved_at = Sys.time()
  )

  testthat::expect_equal(nrow(shaped), 0L)
  testthat::expect_true("daily_heart_rate_variability_key" %in% names(shaped))
})

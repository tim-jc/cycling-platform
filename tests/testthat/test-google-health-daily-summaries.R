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
        name = "fitbit-air",
        platform = "FITBIT",
        recordingMethod = "DERIVED",
        device = list()
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
        name = "apple-health",
        platform = "HEALTH_KIT",
        recordingMethod = "UNKNOWN",
        device = list(
          manufacturer = "Apple Inc.",
          model = "Apple Watch"
        )
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
  testthat::expect_equal(shaped$source_platform[[1]], "FITBIT")
  testthat::expect_equal(shaped$source_ecosystem[[1]], "fitbit")
  testthat::expect_equal(shaped$source_recording_method[[1]], "DERIVED")
  testthat::expect_true(is.na(shaped$source_device_manufacturer[[1]]))
  testthat::expect_equal(shaped$source_platform[[2]], "HEALTH_KIT")
  testthat::expect_equal(shaped$source_ecosystem[[2]], "apple_health")
  testthat::expect_equal(shaped$source_device_manufacturer[[2]], "Apple Inc.")
  testthat::expect_equal(shaped$source_device_model[[2]], "Apple Watch")
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

testthat::test_that("Google Health daily source provenance maps known and unknown ecosystems", {
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

  testthat::expect_equal(
    google_health_source_ecosystem("FITBIT"),
    "fitbit"
  )

  testthat::expect_equal(
    google_health_source_ecosystem("HEALTH_KIT"),
    "apple_health"
  )

  testthat::expect_equal(
    google_health_source_ecosystem(
      source_platform = NA_character_,
      source_device_manufacturer = "Apple Inc."
    ),
    "apple_health"
  )

  testthat::expect_equal(
    google_health_source_ecosystem(NA_character_),
    "unknown"
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
        name = "fitbit-air",
        platform = "FITBIT",
        recordingMethod = "DERIVED",
        device = list()
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
        name = "apple-health",
        platform = "HEALTH_KIT",
        recordingMethod = "PASSIVELY_MEASURED",
        device = list(
          manufacturer = "Apple Inc."
        )
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
  testthat::expect_equal(shaped$source_platform[[1]], "FITBIT")
  testthat::expect_equal(shaped$source_ecosystem[[1]], "fitbit")
  testthat::expect_equal(shaped$source_recording_method[[2]], "PASSIVELY_MEASURED")
  testthat::expect_equal(shaped$source_ecosystem[[2]], "apple_health")
  testthat::expect_equal(shaped$source_device_manufacturer[[2]], "Apple Inc.")
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

testthat::test_that("Google Health daily respiratory-rate payloads are shaped for raw loading", {
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
        platform = "FITBIT",
        recordingMethod = "DERIVED",
        device = list()
      ),
      dailyRespiratoryRate = list(
        date = list(
          year = 2026,
          month = 7,
          day = 10
        ),
        breathsPerMinute = "14.2"
      )
    ),
    list(
      dataSource = list(
        platform = "HEALTH_KIT",
        recordingMethod = "PASSIVELY_MEASURED",
        device = list(
          manufacturer = "Apple Inc.",
          model = "Apple Watch"
        )
      ),
      dailyRespiratoryRate = list(
        date = list(
          year = 2026,
          month = 7,
          day = 10
        ),
        breathsPerMinute = "15.1"
      )
    )
  )

  shaped <- google_health_shape_daily_respiratory_rate(
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
  testthat::expect_equal(shaped$respiratory_rate_brpm[[1]], 14.2)
  testthat::expect_true(is.na(shaped$source_data_point_id[[1]]))
  testthat::expect_equal(shaped$source_platform[[1]], "FITBIT")
  testthat::expect_equal(shaped$source_ecosystem[[1]], "fitbit")
  testthat::expect_equal(shaped$source_recording_method[[1]], "DERIVED")
  testthat::expect_equal(shaped$source_platform[[2]], "HEALTH_KIT")
  testthat::expect_equal(shaped$source_ecosystem[[2]], "apple_health")
  testthat::expect_equal(shaped$source_device_manufacturer[[2]], "Apple Inc.")
  testthat::expect_equal(shaped$source_device_model[[2]], "Apple Watch")
  testthat::expect_equal(length(unique(shaped$daily_respiratory_rate_key)), 2L)
  testthat::expect_equal(nchar(shaped$daily_respiratory_rate_key[[1]]), 64L)
  testthat::expect_true(
    grepl(
      "\"dailyRespiratoryRate\"",
      shaped$daily_respiratory_rate_payload[[1]],
      fixed = TRUE
    )
  )

  shaped_again <- google_health_shape_daily_respiratory_rate(
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
    shaped$daily_respiratory_rate_key,
    shaped_again$daily_respiratory_rate_key
  )
})

testthat::test_that("Google Health daily respiratory-rate empty responses shape cleanly", {
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

  shaped <- google_health_shape_daily_respiratory_rate(
    data_points = list(),
    google_health_user_id = "me",
    run_id = 1L,
    source_id = 2L,
    retrieved_at = Sys.time()
  )

  testthat::expect_equal(nrow(shaped), 0L)
  testthat::expect_true("daily_respiratory_rate_key" %in% names(shaped))
})

testthat::test_that("Google Health daily source grain allows same-day ecosystem overlap", {
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

  fitbit_payload <- jsonlite::toJSON(
    list(platform = "FITBIT", value = 46),
    auto_unbox = TRUE,
    digits = NA
  )

  apple_payload <- jsonlite::toJSON(
    list(platform = "HEALTH_KIT", value = 47),
    auto_unbox = TRUE,
    digits = NA
  )

  fitbit_key <- google_health_daily_source_grain_key(
    data_type = "daily-resting-heart-rate",
    google_health_user_id = "me",
    source_data_point_id = NA_character_,
    activity_date = as.Date("2026-07-10"),
    source_platform = "FITBIT",
    source_recording_method = "DERIVED",
    source_device_manufacturer = NA_character_,
    source_device_model = NA_character_,
    payload = fitbit_payload
  )

  apple_key <- google_health_daily_source_grain_key(
    data_type = "daily-resting-heart-rate",
    google_health_user_id = "me",
    source_data_point_id = NA_character_,
    activity_date = as.Date("2026-07-10"),
    source_platform = "HEALTH_KIT",
    source_recording_method = "UNKNOWN",
    source_device_manufacturer = "Apple Inc.",
    source_device_model = "Apple Watch",
    payload = apple_payload
  )

  repeated_fitbit_key <- google_health_daily_source_grain_key(
    data_type = "daily-resting-heart-rate",
    google_health_user_id = "me",
    source_data_point_id = NA_character_,
    activity_date = as.Date("2026-07-10"),
    source_platform = "FITBIT",
    source_recording_method = "DERIVED",
    source_device_manufacturer = NA_character_,
    source_device_model = NA_character_,
    payload = fitbit_payload
  )

  testthat::expect_false(identical(fitbit_key, apple_key))
  testthat::expect_identical(fitbit_key, repeated_fitbit_key)
})

testthat::test_that("Google Health daily provenance backfill plan is idempotent", {
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

  backfill_file <- file.path(
    "R",
    "quality",
    "backfill_google_health_daily_source_provenance.R"
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

  if (!file.exists(backfill_file)) {
    backfill_file <- file.path(
      "..",
      "..",
      "R",
      "quality",
      "backfill_google_health_daily_source_provenance.R"
    )
  }

  source(data_points_file)
  source(daily_file)
  source(backfill_file)

  fitbit_payload <- as.character(
    jsonlite::toJSON(
      list(
        dataSource = list(
          platform = "FITBIT",
          recordingMethod = "DERIVED"
        ),
        dailyRestingHeartRate = list(
          date = list(
            year = 2026,
            month = 7,
            day = 10
          ),
          beatsPerMinute = "46"
        )
      ),
      auto_unbox = TRUE,
      digits = NA
    )
  )

  unknown_payload <- as.character(
    jsonlite::toJSON(
      list(
        dailyRestingHeartRate = list(
          date = list(
            year = 2026,
            month = 7,
            day = 11
          ),
          beatsPerMinute = "47"
        )
      ),
      auto_unbox = TRUE,
      digits = NA
    )
  )

  rows <- tibble::tibble(
    row_key = c(
      "already",
      "fitbit",
      "unknown",
      "bad"
    ),
    source_ecosystem = c(
      "fitbit",
      NA_character_,
      NA_character_,
      NA_character_
    ),
    source_platform = c(
      "FITBIT",
      NA_character_,
      NA_character_,
      NA_character_
    ),
    source_recording_method = c(
      "DERIVED",
      NA_character_,
      NA_character_,
      NA_character_
    ),
    source_device_manufacturer = NA_character_,
    source_device_model = NA_character_,
    payload = c(
      fitbit_payload,
      fitbit_payload,
      unknown_payload,
      "{not json"
    )
  )

  planned <- google_health_daily_provenance_backfill_plan(rows)

  testthat::expect_equal(
    planned$backfill_action,
    c(
      "already_populated",
      "update",
      "unknown_source",
      "unparseable"
    )
  )

  testthat::expect_equal(
    planned$parsed_source_ecosystem[[2]],
    "fitbit"
  )

  testthat::expect_equal(
    planned$parsed_source_ecosystem[[3]],
    "unknown"
  )
})

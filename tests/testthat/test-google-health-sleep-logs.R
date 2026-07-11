testthat::test_that("Google Health sleep logs are shaped for raw loading", {
  data_points_file <- file.path(
    "R",
    "api",
    "get_google_health_data_points.R"
  )

  sleep_logs_file <- file.path(
    "R",
    "api",
    "get_google_health_sleep_logs.R"
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

  if (!file.exists(sleep_logs_file)) {
    sleep_logs_file <- file.path(
      "..",
      "..",
      "R",
      "api",
      "get_google_health_sleep_logs.R"
    )
  }

  source(
    data_points_file
  )

  source(
    sleep_logs_file
  )

  sleep_payloads <- list(
    list(
      name = "users/me/dataTypes/sleep/dataPoints/sleep-session-1",
      dataSource = list(
        name = "fitbit"
      ),
      sleep = list(
        interval = list(
          startTime = list(
            physicalTime = "2026-06-27T22:15:00.123456Z",
            utcOffset = "3600s",
            civilTime = list(
              date = list(
                year = 2026,
                month = 6,
                day = 27
              )
            )
          ),
          endTime = list(
            physicalTime = "2026-06-28T06:45:00Z",
            utcOffset = "3600s",
            civilTime = list(
              date = list(
                year = 2026,
                month = 6,
                day = 28
              )
            )
          )
        ),
        type = "STAGES",
        stages = list(
          list(
            stage = "DEEP",
            interval = list()
          ),
          list(
            stage = "LIGHT",
            interval = list()
          )
        ),
        metadata = list(
          stagesStatus = "SUCCEEDED",
          processed = TRUE
        ),
        summary = list(
          stagesSummary = list(
            list(stage = "DEEP"),
            list(stage = "LIGHT")
          )
        )
      )
    )
  )

  shaped <- google_health_shape_sleep_logs(
    sleep_logs = sleep_payloads,
    google_user_id = "me",
    run_id = 1L,
    source_id = 2L,
    retrieved_at = as.POSIXct(
      "2026-06-28 07:00:00",
      tz = "UTC"
    )
  )

  testthat::expect_equal(
    nrow(shaped),
    1L
  )

  testthat::expect_equal(
    nchar(shaped$sleep_log_key[[1]]),
    64L
  )

  testthat::expect_false(
    inherits(
      shaped$sleep_log_key,
      "hash"
    )
  )

  testthat::expect_equal(
    shaped$source_log_id[[1]],
    "users/me/dataTypes/sleep/dataPoints/sleep-session-1"
  )

  testthat::expect_equal(
    format(
      shaped$start_physical_time[[1]],
      "%Y-%m-%d %H:%M:%S",
      tz = "UTC"
    ),
    "2026-06-27 22:15:00"
  )

  testthat::expect_equal(
    format(
      shaped$end_physical_time[[1]],
      "%Y-%m-%d %H:%M:%S",
      tz = "UTC"
    ),
    "2026-06-28 06:45:00"
  )

  testthat::expect_equal(
    as.character(shaped$start_civil_date[[1]]),
    "2026-06-27"
  )

  testthat::expect_equal(
    as.character(shaped$end_civil_date[[1]]),
    "2026-06-28"
  )

  testthat::expect_equal(
    shaped$sleep_type[[1]],
    "STAGES"
  )

  testthat::expect_equal(
    shaped$stages_status[[1]],
    "SUCCEEDED"
  )

  testthat::expect_equal(
    shaped$is_processed[[1]],
    1L
  )

  testthat::expect_true(
    is.na(shaped$is_nap[[1]])
  )

  testthat::expect_equal(
    shaped$has_sleep_stages[[1]],
    1L
  )

  testthat::expect_equal(
    shaped$sleep_stage_count[[1]],
    2L
  )

  testthat::expect_equal(
    shaped$has_sleep_summary[[1]],
    1L
  )

  testthat::expect_true(
    grepl(
      "\"sleep\"",
      shaped$sleep_log_payload[[1]],
      fixed = TRUE
    )
  )
})

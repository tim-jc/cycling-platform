testthat::test_that("best effort calculation returns peak value and provenance", {
  transform_file <- file.path(
    "R",
    "transforms",
    "rebuild_gold_activity_best_efforts.R"
  )

  if (!file.exists(transform_file)) {
    transform_file <- file.path(
      "..",
      "..",
      "R",
      "transforms",
      "rebuild_gold_activity_best_efforts.R"
    )
  }

  source(transform_file)

  activity_streams <- data.frame(
    activity_id = rep(1, 6),
    sample_index = 1:6,
    time_seconds = 0:5,
    distance_metres = seq(0, 50, by = 10),
    latitude = rep(53.1, 6),
    longitude = rep(-2.8, 6),
    watts = c(100, 200, 300, 400, 100, 100)
  )

  result <- compute_activity_best_effort(
    activity_streams = activity_streams,
    metric_column = "watts",
    metric_name = "watts",
    duration_seconds = 3L
  )

  testthat::expect_equal(
    result$peak_value[[1]],
    300
  )

  testthat::expect_equal(
    result$start_sample_index[[1]],
    2L
  )

  testthat::expect_equal(
    result$end_sample_index[[1]],
    4L
  )

  testthat::expect_equal(
    result$sample_count[[1]],
    3L
  )
})

testthat::test_that("best effort calculation skips windows with missing watts", {
  transform_file <- file.path(
    "R",
    "transforms",
    "rebuild_gold_activity_best_efforts.R"
  )

  if (!file.exists(transform_file)) {
    transform_file <- file.path(
      "..",
      "..",
      "R",
      "transforms",
      "rebuild_gold_activity_best_efforts.R"
    )
  }

  source(transform_file)

  activity_streams <- data.frame(
    activity_id = rep(1, 4),
    sample_index = 1:4,
    time_seconds = 0:3,
    distance_metres = seq(0, 30, by = 10),
    latitude = rep(53.1, 4),
    longitude = rep(-2.8, 4),
    watts = c(100, NA, 300, 400)
  )

  result <- compute_activity_best_effort(
    activity_streams = activity_streams,
    metric_column = "watts",
    metric_name = "watts",
    duration_seconds = 2L
  )

  testthat::expect_equal(
    result$peak_value[[1]],
    350
  )

  testthat::expect_equal(
    result$start_sample_index[[1]],
    3L
  )
})

testthat::test_that("best effort calculation supports configured v1 metrics", {
  transform_file <- file.path(
    "R",
    "transforms",
    "rebuild_gold_activity_best_efforts.R"
  )

  if (!file.exists(transform_file)) {
    transform_file <- file.path(
      "..",
      "..",
      "R",
      "transforms",
      "rebuild_gold_activity_best_efforts.R"
    )
  }

  source(transform_file)

  activity_streams <- data.frame(
    activity_id = rep(1, 5),
    sample_index = 1:5,
    time_seconds = 0:4,
    distance_metres = seq(0, 40, by = 10),
    latitude = rep(53.1, 5),
    longitude = rep(-2.8, 5),
    watts = c(100, 200, 300, 400, 500),
    cadence_rpm = c(70, 80, 90, 100, 110),
    heartrate_bpm = c(120, 130, 140, 150, 160)
  )

  result <- compute_activity_best_efforts(
    activity_streams = activity_streams,
    metrics = c(
      "watts",
      "cadence_rpm",
      "heartrate_bpm"
    ),
    durations = 2L
  )

  testthat::expect_equal(
    sort(result$metric_name),
    c(
      "cadence_rpm",
      "heartrate_bpm",
      "watts"
    )
  )

  testthat::expect_equal(
    result$peak_value[result$metric_name == "watts"],
    450
  )

  testthat::expect_equal(
    result$peak_value[result$metric_name == "cadence_rpm"],
    105
  )

  testthat::expect_equal(
    result$peak_value[result$metric_name == "heartrate_bpm"],
    155
  )
})

testthat::test_that("best effort calculation skips all-NA metrics safely", {
  transform_file <- file.path(
    "R",
    "transforms",
    "rebuild_gold_activity_best_efforts.R"
  )

  if (!file.exists(transform_file)) {
    transform_file <- file.path(
      "..",
      "..",
      "R",
      "transforms",
      "rebuild_gold_activity_best_efforts.R"
    )
  }

  source(transform_file)

  activity_streams <- data.frame(
    activity_id = rep(1, 3),
    sample_index = 1:3,
    time_seconds = 0:2,
    distance_metres = seq(0, 20, by = 10),
    latitude = rep(53.1, 3),
    longitude = rep(-2.8, 3),
    watts = c(100, 200, 300),
    cadence_rpm = c(NA, NA, NA),
    heartrate_bpm = c(120, 130, 140)
  )

  result <- compute_activity_best_efforts(
    activity_streams = activity_streams,
    metrics = c(
      "watts",
      "cadence_rpm",
      "heartrate_bpm"
    ),
    durations = 2L
  )

  testthat::expect_false(
    "cadence_rpm" %in% result$metric_name
  )

  testthat::expect_true(
    all(
      c(
        "watts",
        "heartrate_bpm"
      ) %in% result$metric_name
    )
  )
})

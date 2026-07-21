source_activity_achievement_files <- function() {
  helper_files <- c(
    file.path("R", "utils", "format_notification_helpers.R"),
    file.path("R", "transforms", "rebuild_gold_activity_achievements.R"),
    file.path("R", "utils", "activity_achievement_notifications.R")
  )

  for (helper_file in helper_files) {
    if (!file.exists(helper_file)) {
      helper_file <- file.path("..", "..", helper_file)
    }

    source(helper_file)
  }
}

testthat::test_that("activity achievements calculate all-time and annual records", {
  source_activity_achievement_files()

  source_rows <- data.frame(
    activity_id = bit64::as.integer64(
      c(
        "1",
        "2",
        "3",
        "4"
      )
    ),
    activity_date = as.Date(
      c(
        "2025-12-31",
        "2026-01-10",
        "2026-01-20",
        "2026-01-25"
      )
    ),
    achievement_type = "power_best_effort",
    metric_name = "power_watts",
    duration_seconds = 1200L,
    metric_value = c(
      300,
      290,
      310,
      310
    )
  )

  achievements <- compute_activity_achievements(
    source_rows = source_rows,
    calculation_version = "test_v1"
  )

  activity_2_year <- achievements[
    achievements$activity_id == bit64::as.integer64("2") &
      achievements$comparison_scope == "calendar_year",
    ,
    drop = FALSE
  ]

  testthat::expect_equal(
    nrow(activity_2_year),
    1L
  )

  testthat::expect_equal(
    activity_2_year$previous_best_value[[1]],
    300
  )

  testthat::expect_equal(
    as.character(activity_2_year$previous_best_date[[1]]),
    "2025-12-31"
  )

  testthat::expect_equal(
    activity_2_year$days_since_previous_best[[1]],
    10L
  )

  activity_3_all_time <- achievements[
    achievements$activity_id == bit64::as.integer64("3") &
      achievements$comparison_scope == "all_time",
    ,
    drop = FALSE
  ]

  testthat::expect_equal(
    nrow(activity_3_all_time),
    1L
  )

  testthat::expect_equal(
    activity_3_all_time$previous_best_value[[1]],
    300
  )

  testthat::expect_false(
    any(
      achievements$activity_id == bit64::as.integer64("4")
    )
  )
})

testthat::test_that("activity achievement keys are deterministic", {
  source_activity_achievement_files()

  key_1 <- activity_achievement_key(
    activity_id = "123",
    achievement_type = "longest_distance",
    metric_name = "distance_metres",
    duration_seconds = 0L,
    comparison_scope = "all_time",
    comparison_period_start = as.Date("1000-01-01"),
    comparison_period_end = as.Date("9999-12-31")
  )

  key_2 <- activity_achievement_key(
    activity_id = "123",
    achievement_type = "longest_distance",
    metric_name = "distance_metres",
    duration_seconds = 0L,
    comparison_scope = "all_time",
    comparison_period_start = as.Date("1000-01-01"),
    comparison_period_end = as.Date("9999-12-31")
  )

  testthat::expect_equal(
    key_1,
    key_2
  )

  testthat::expect_equal(
    nchar(key_1),
    64L
  )
})

testthat::test_that("activity-level records such as distance are supported", {
  source_activity_achievement_files()

  source_rows <- data.frame(
    activity_id = bit64::as.integer64(
      c(
        "10",
        "11"
      )
    ),
    activity_date = as.Date(
      c(
        "2026-01-01",
        "2026-02-01"
      )
    ),
    achievement_type = "longest_distance",
    metric_name = "distance_metres",
    duration_seconds = 0L,
    metric_value = c(
      100000,
      125000
    )
  )

  achievements <- compute_activity_achievements(
    source_rows = source_rows,
    calculation_version = "test_v1"
  )

  testthat::expect_true(
    any(
      achievements$activity_id == bit64::as.integer64("11") &
        achievements$comparison_scope == "all_time"
    )
  )
})

testthat::test_that("daily candidates include recent activities after baseline exists", {
  source_activity_achievement_files()

  candidates <- daily_activity_achievement_candidate_ids(
    candidate_activity_ids = c("1", "2"),
    recent_activity_ids = c("2", "3"),
    mode = "daily",
    existing_achievement_count = 10
  )

  testthat::expect_equal(
    candidates,
    c("1", "2", "3")
  )

  initial_candidates <- daily_activity_achievement_candidate_ids(
    candidate_activity_ids = c("1", "2"),
    recent_activity_ids = c("2", "3"),
    mode = "daily",
    existing_achievement_count = 0
  )

  testthat::expect_equal(
    initial_candidates,
    c("1", "2")
  )
})

testthat::test_that("achievement notification body groups activity achievements", {
  source_activity_achievement_files()

  activity <- data.frame(
    activity_id = bit64::as.integer64("99"),
    activity_name = "Sunday Ride",
    start_date_local = as.Date("2026-07-19"),
    distance_kilometres = 142.3
  )

  achievements <- data.frame(
    activity_achievement_key = c(
      "a",
      "b"
    ),
    achievement_type = c(
      "power_best_effort",
      "longest_distance"
    ),
    metric_name = c(
      "power_watts",
      "distance_metres"
    ),
    duration_seconds = c(
      1200L,
      0L
    ),
    comparison_scope = c(
      "all_time",
      "calendar_year"
    ),
    metric_value = c(
      301,
      142300
    ),
    previous_best_value = c(
      295,
      130000
    ),
    previous_best_activity_id = bit64::as.integer64(
      c(
        "88",
        "77"
      )
    ),
    previous_best_date = as.Date(
      c(
        "2026-06-01",
        "2025-05-10"
      )
    ),
    days_since_previous_best = c(
      NA_integer_,
      426L
    ),
    achievement_title = c(
      "New all-time 20-minute power best",
      "New this year longest ride"
    ),
    achievement_detail = c(
      "New all-time 20-minute power best: 301 W",
      "New this year longest ride: 142.3 km -- best for 426 days"
    )
  )

  body <- format_activity_achievement_notification_body(
    activity = activity,
    achievements = achievements
  )

  testthat::expect_true(
    any(grepl("Sunday Ride", body))
  )

  testthat::expect_true(
    any(grepl("20-minute power", body))
  )

  testthat::expect_true(
    any(grepl("best for 426 days", body))
  )
})

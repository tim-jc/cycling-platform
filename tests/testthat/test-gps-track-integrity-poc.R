track_integrity_path <- function(...) {
  path <- file.path(...)
  if (!file.exists(path)) path <- file.path("..", "..", path)
  path
}

source(track_integrity_path(
  "R", "quality", "profile_activity_track_integrity.R"
))

track_fixture <- function(
  sample_index = 1:3,
  latitude = c(53, 53.001, 53.002),
  longitude = c(-2, -2, -2),
  time_seconds = c(0, 1, 2),
  distance_metres = c(0, 100, 200),
  activity_id = "123456789"
) {
  data.frame(
    activity_id = rep(activity_id, length(sample_index)),
    sample_index = sample_index,
    latitude = latitude,
    longitude = longitude,
    time_seconds = time_seconds,
    distance_metres = distance_metres
  )
}

testthat::test_that("normal one-second GPS recording is measured numerically", {
  result <- profile_activity_track_integrity(track_fixture())

  testthat::expect_identical(result$summary$activity_id, "123456789")
  testthat::expect_equal(result$summary$sample_count, 3L)
  testthat::expect_equal(result$summary$valid_coordinate_count, 3L)
  testthat::expect_equal(result$summary$elapsed_time_interval_seconds[["p50"]], 1)
  testthat::expect_equal(
    result$summary$geographic_displacement_metres[["p50"]],
    111.195,
    tolerance = 0.01
  )
  testthat::expect_equal(
    result$summary$maximum_implied_geographic_speed_metres_per_second,
    111.195,
    tolerance = 0.01
  )
})

testthat::test_that("irregular and plausible sparse sampling remains measured", {
  result <- profile_activity_track_integrity(track_fixture(
    time_seconds = c(0, 2, 7),
    distance_metres = c(0, 50, 120)
  ))

  testthat::expect_equal(result$summary$maximum_time_gap_seconds, 5)
  testthat::expect_equal(result$summary$elapsed_time_interval_seconds[["minimum"]], 2)
  testthat::expect_equal(result$summary$device_distance_increment_metres[["maximum"]], 70)
  testthat::expect_false("segment_classification" %in% names(result$summary))
})

testthat::test_that("stationary repeated coordinates are not errors", {
  result <- profile_activity_track_integrity(track_fixture(
    latitude = rep(53, 3),
    longitude = rep(-2, 3),
    distance_metres = c(0, 0, 0)
  ))

  testthat::expect_equal(result$summary$repeated_coordinate_segment_count, 2L)
  testthat::expect_equal(result$summary$repeated_cumulative_distance_count, 2L)
  testthat::expect_equal(result$summary$decreasing_cumulative_distance_count, 0L)
})

testthat::test_that("duplicate timestamps do not cause division by zero", {
  stationary <- profile_activity_track_integrity(track_fixture(
    latitude = c(53, 53, 53.001),
    longitude = rep(-2, 3),
    time_seconds = c(0, 0, 1)
  ))
  moving <- profile_activity_track_integrity(track_fixture(
    time_seconds = c(0, 0, 1)
  ))

  testthat::expect_equal(stationary$summary$duplicate_timestamp_count, 1L)
  testthat::expect_equal(moving$summary$duplicate_timestamp_count, 1L)
  testthat::expect_equal(moving$summary$implied_geographic_speed_metres_per_second[["count"]], 1)
  duplicate_row <- moving$diagnostics[
    moving$diagnostics$diagnostic_type == "NON_INCREASING_TIME", , drop = FALSE
  ]
  testthat::expect_true(is.na(duplicate_row$implied_geographic_speed_metres_per_second[[1]]))
  testthat::expect_gt(duplicate_row$geographic_displacement_metres[[1]], 100)
})

testthat::test_that("time and cumulative-distance regressions are retained", {
  result <- profile_activity_track_integrity(track_fixture(
    time_seconds = c(0, 5, 4),
    distance_metres = c(0, 100, 90)
  ))

  testthat::expect_equal(result$summary$decreasing_timestamp_count, 1L)
  testthat::expect_equal(result$summary$non_increasing_timestamp_count, 1L)
  testthat::expect_equal(result$summary$decreasing_cumulative_distance_count, 1L)
  testthat::expect_true("NON_INCREASING_TIME" %in% result$diagnostics$diagnostic_type)
  testthat::expect_true("DISTANCE_REGRESSION" %in% result$diagnostics$diagnostic_type)
})

testthat::test_that("long gaps and large jumps are reported without thresholds", {
  gap <- profile_activity_track_integrity(track_fixture(
    time_seconds = c(0, 1, 3601)
  ))
  jump <- profile_activity_track_integrity(track_fixture(
    latitude = c(53, 53.001, -20),
    longitude = c(-2, -2, 130),
    time_seconds = c(0, 1, 2)
  ))

  testthat::expect_equal(gap$summary$maximum_time_gap_seconds, 3600)
  testthat::expect_gt(jump$summary$geographic_displacement_metres[["maximum"]], 1e6)
  testthat::expect_gt(
    jump$summary$maximum_implied_geographic_speed_metres_per_second,
    1e6
  )
})

testthat::test_that("invalid and zero-zero coordinates remain distinct", {
  result <- profile_activity_track_integrity(track_fixture(
    sample_index = 1:4,
    latitude = c(53, 91, 0, 53.001),
    longitude = c(-2, -2, 0, -2),
    time_seconds = 0:3,
    distance_metres = c(0, 10, 20, 30)
  ))

  testthat::expect_equal(result$summary$valid_coordinate_count, 3L)
  testthat::expect_equal(result$summary$invalid_coordinate_count, 1L)
  testthat::expect_equal(result$summary$zero_zero_coordinate_count, 1L)
  testthat::expect_true("INVALID_COORDINATE" %in% result$diagnostics$diagnostic_type)
  testthat::expect_true("ZERO_ZERO_COORDINATE" %in% result$diagnostics$diagnostic_type)
  testthat::expect_equal(result$summary$geographic_displacement_metres[["count"]], 1)
})

testthat::test_that("missing and non-finite endpoints cannot create displacement", {
  result <- profile_activity_track_integrity(track_fixture(
    sample_index = 1:4,
    latitude = c(53, NA, Inf, 53.001),
    longitude = c(-2, -2, -2, -2),
    time_seconds = 0:3,
    distance_metres = c(0, 10, 20, 30)
  ))

  testthat::expect_equal(result$summary$invalid_coordinate_count, 2L)
  testthat::expect_equal(result$summary$geographic_displacement_metres[["count"]], 0)
  testthat::expect_equal(result$summary$implied_geographic_speed_metres_per_second[["count"]], 0)
})

testthat::test_that("empty and single-sample activities are deliberate", {
  empty <- track_fixture()[0, ]
  empty_result <- profile_activity_track_integrity(empty)
  single_result <- profile_activity_track_integrity(track_fixture()[1, , drop = FALSE])

  testthat::expect_equal(empty_result$summary$sample_count, 0L)
  testthat::expect_true(is.na(empty_result$summary$activity_id))
  testthat::expect_equal(nrow(empty_result$diagnostics), 0L)
  testthat::expect_equal(single_result$summary$sample_count, 1L)
  testthat::expect_equal(single_result$summary$elapsed_time_interval_seconds[["count"]], 0)
  testthat::expect_true(is.na(single_result$summary$maximum_time_gap_seconds))
})

testthat::test_that("out-of-order and discontinuous sample indexes are not sorted", {
  result <- profile_activity_track_integrity(track_fixture(
    sample_index = c(1, 3, 2),
    time_seconds = c(0, 2, 1)
  ))

  testthat::expect_equal(result$summary$first_sample_index, 1L)
  testthat::expect_equal(result$summary$last_sample_index, 2L)
  testthat::expect_equal(result$summary$sample_index_gap_count, 1L)
  testthat::expect_equal(result$summary$sample_index_non_increasing_count, 1L)
  testthat::expect_true("SAMPLE_INDEX_GAP" %in% result$diagnostics$diagnostic_type)
  testthat::expect_true("NON_INCREASING_SAMPLE_INDEX" %in% result$diagnostics$diagnostic_type)
})

testthat::test_that("diagnostics are bounded per category", {
  samples <- track_fixture(
    sample_index = 1:10,
    latitude = seq(53, 53.009, length.out = 10),
    longitude = rep(-2, 10),
    time_seconds = 0:9,
    distance_metres = seq(0, 900, length.out = 10)
  )
  result <- profile_activity_track_integrity(samples, diagnostic_limit = 2)
  category_counts <- table(result$diagnostics$diagnostic_type)
  testthat::expect_true(all(category_counts <= 2))
})

testthat::test_that("GPS and device distance agreement is measured", {
  result <- profile_activity_track_integrity(track_fixture(
    latitude = c(53, 53.001, 53.002),
    longitude = rep(-2, 3),
    distance_metres = c(0, 111.195, 222.390)
  ))

  testthat::expect_equal(
    result$summary$gps_device_distance_absolute_difference_metres[["maximum"]],
    0,
    tolerance = 0.001
  )
  testthat::expect_equal(
    result$summary$gps_device_distance_relative_discrepancy[["maximum"]],
    0,
    tolerance = 0.00001
  )
})

testthat::test_that("GPS displacement greater than device distance is signed positively", {
  result <- profile_activity_track_integrity(track_fixture(
    sample_index = 1:2,
    latitude = c(53, 53.01),
    longitude = c(-2, -2),
    time_seconds = c(0, 10),
    distance_metres = c(0, 10)
  ))
  diagnostic <- result$diagnostics[
    result$diagnostics$diagnostic_type ==
      "LARGEST_GPS_DEVICE_DISTANCE_DISCREPANCY", , drop = FALSE
  ]

  testthat::expect_gt(diagnostic$gps_device_distance_signed_difference_metres[[1]], 1000)
  testthat::expect_equal(
    diagnostic$gps_device_distance_absolute_difference_metres[[1]],
    abs(diagnostic$gps_device_distance_signed_difference_metres[[1]])
  )
  testthat::expect_true(is.finite(diagnostic$gps_device_distance_relative_discrepancy[[1]]))
})

testthat::test_that("device distance greater than straight-line displacement is signed negatively", {
  result <- profile_activity_track_integrity(track_fixture(
    sample_index = 1:2,
    latitude = c(53, 53.001),
    longitude = c(-2, -2),
    time_seconds = c(0, 60),
    distance_metres = c(0, 500)
  ))
  diagnostic <- result$diagnostics[
    result$diagnostics$diagnostic_type ==
      "LARGEST_GPS_DEVICE_DISTANCE_DISCREPANCY", , drop = FALSE
  ]

  testthat::expect_lt(diagnostic$gps_device_distance_signed_difference_metres[[1]], 0)
  testthat::expect_equal(diagnostic$device_distance_difference_metres[[1]], 500)
})

testthat::test_that("stationary zero increments have stable relative discrepancy", {
  result <- profile_activity_track_integrity(track_fixture(
    latitude = rep(53, 3),
    longitude = rep(-2, 3),
    distance_metres = c(0, 0, 0)
  ))

  testthat::expect_equal(
    result$summary$gps_device_distance_relative_discrepancy[["maximum"]],
    0
  )
  testthat::expect_true(all(is.finite(
    result$diagnostics$gps_device_distance_relative_discrepancy[
      !is.na(result$diagnostics$gps_device_distance_relative_discrepancy)
    ]
  )))
})

testthat::test_that("movement with zero device increment remains finite", {
  result <- profile_activity_track_integrity(track_fixture(
    sample_index = 1:2,
    latitude = c(53, 53.001),
    longitude = c(-2, -2),
    time_seconds = c(0, 1),
    distance_metres = c(0, 0)
  ))

  testthat::expect_equal(
    result$summary$gps_device_distance_relative_discrepancy[["maximum"]],
    1
  )
  testthat::expect_true(is.finite(
    result$summary$gps_device_distance_relative_discrepancy[["maximum"]]
  ))
})

testthat::test_that("negative device increments are measured without suppression", {
  result <- profile_activity_track_integrity(track_fixture(
    sample_index = 1:2,
    latitude = c(53, 53.001),
    longitude = c(-2, -2),
    time_seconds = c(0, 1),
    distance_metres = c(100, 90)
  ))

  testthat::expect_equal(result$summary$decreasing_cumulative_distance_count, 1L)
  testthat::expect_gt(
    result$summary$gps_device_distance_signed_difference_metres[["maximum"]],
    100
  )
  testthat::expect_true(is.finite(
    result$summary$gps_device_distance_relative_discrepancy[["maximum"]]
  ))
})

testthat::test_that("invalid endpoints do not produce discrepancy measurements", {
  result <- profile_activity_track_integrity(track_fixture(
    sample_index = 1:2,
    latitude = c(53, 91),
    longitude = c(-2, -2),
    time_seconds = c(0, 1),
    distance_metres = c(0, 100)
  ))

  testthat::expect_equal(
    result$summary$gps_device_distance_absolute_difference_metres[["count"]],
    0
  )
  testthat::expect_equal(
    result$summary$gps_device_distance_relative_discrepancy[["count"]],
    0
  )
})

testthat::test_that("long route gaps preserve both distance measurements", {
  result <- profile_activity_track_integrity(track_fixture(
    sample_index = 1:2,
    latitude = c(51.45, 51.50),
    longitude = c(-1.00, -1.60),
    time_seconds = c(0, 10327),
    distance_metres = c(0, 52495.5)
  ))
  diagnostic <- result$diagnostics[
    result$diagnostics$diagnostic_type ==
      "LARGEST_GPS_DEVICE_DISTANCE_DISCREPANCY", , drop = FALSE
  ]

  testthat::expect_equal(diagnostic$elapsed_time_difference_seconds[[1]], 10327)
  testthat::expect_equal(diagnostic$device_distance_difference_metres[[1]], 52495.5)
  testthat::expect_gt(diagnostic$geographic_displacement_metres[[1]], 40000)
  testthat::expect_lt(diagnostic$gps_device_distance_signed_difference_metres[[1]], 0)
})

testthat::test_that("the explicit-ID fetch is parameterised and bounded", {
  captured <- new.env(parent = emptyenv())
  get_query <- function(connection, statement, params) {
    captured$connection <- connection
    captured$statement <- statement
    captured$params <- params
    track_fixture()[0, ]
  }

  fetch_activity_track_samples(
    connection = "read-only-connection",
    activity_ids = c("19748350909", "19750357368"),
    get_query = get_query
  )

  testthat::expect_identical(captured$connection, "read-only-connection")
  testthat::expect_match(captured$statement, "WHERE activity_id IN (?, ?)", fixed = TRUE)
  testthat::expect_match(captured$statement, "ORDER BY activity_id, sample_index", fixed = TRUE)
  testthat::expect_identical(captured$params, as.list(c("19748350909", "19750357368")))
  testthat::expect_error(
    validate_track_audit_activity_ids("1 OR 1=1"),
    "digits only"
  )
  testthat::expect_error(
    validate_track_audit_activity_ids(as.character(1:51)),
    "At most 50"
  )
})

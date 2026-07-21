test_that("silver activity stream rows are built from raw JSON payloads", {
  transform_file <- file.path(
    "R",
    "transforms",
    "rebuild_silver_activity_streams.R"
  )

  if (!file.exists(transform_file)) {
    transform_file <- file.path(
      "..",
      "..",
      "R",
      "transforms",
      "rebuild_silver_activity_streams.R"
    )
  }

  source(transform_file)

  raw_streams <- data.frame(
    activity_id = rep(123, 5),
    stream_type = c(
      "time",
      "distance",
      "latlng",
      "watts",
      "moving"
    ),
    original_size = c(3, 3, 3, 2, 3),
    retrieved_at = as.POSIXct(
      rep("2026-07-20 10:00:00", 5),
      tz = "UTC"
    ),
    stream_payload = c(
      "[0,1,2]",
      "[0,10.5,21.25]",
      "[[53.196583,-2.880290],[53.196612,-2.880347],[53.196700,-2.880400]]",
      "[101,202]",
      "[true,true,false]"
    )
  )

  rows <- build_silver_activity_stream_rows(raw_streams)

  expect_equal(nrow(rows), 3)
  expect_equal(rows$activity_id, c(123, 123, 123))
  expect_equal(rows$sample_index, c(1, 2, 3))
  expect_equal(rows$time_seconds, c(0L, 1L, 2L))
  expect_equal(rows$distance_metres, c(0, 10.5, 21.25))
  expect_equal(rows$latitude[[1]], 53.196583)
  expect_equal(rows$longitude[[2]], -2.880347)
  expect_equal(rows$watts, c(101L, 202L, NA_integer_))
  expect_equal(rows$is_moving, c(TRUE, TRUE, FALSE))
  expect_equal(rows$raw_stream_count, c(5L, 5L, 5L))
  expect_equal(rows$raw_max_original_size, c(3L, 3L, 3L))
})

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

test_that("affected stream plans preserve Strava IDs above 32-bit range", {
  transform_file <- file.path("R", "transforms", "rebuild_silver_activity_streams.R")
  if (!file.exists(transform_file)) {
    transform_file <- file.path("..", "..", transform_file)
  }
  source(transform_file)

  activity_ids <- c("19748350909", "19750357368", "19760000000")
  raw_summary <- data.frame(
    activity_id = bit64::as.integer64(c("19748350909", "19750357368")),
    expected_row_count = c(339L, 717L)
  )
  plan <- build_silver_stream_affected_activity_plan(activity_ids, raw_summary)

  expect_s3_class(plan$activity_id, "integer64")
  expect_identical(
    as.character(plan$activity_id),
    c("19748350909", "19750357368", "19760000000")
  )
  expect_equal(plan$expected_row_count, c(339, 717, 0))
  expect_identical(
    format_activity_id_filter(plan$activity_id),
    "19748350909, 19750357368, 19760000000"
  )
})

test_that("zero-work stream repairs are logged as successful runs", {
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

  for (admin_file in c(
    file.path("R", "admin", "ensure_transform_logging_tables.R"),
    file.path("R", "admin", "create_transform_run.R"),
    file.path("R", "admin", "update_transform_run.R")
  )) {
    if (!file.exists(admin_file)) {
      admin_file <- file.path("..", "..", admin_file)
    }

    source(admin_file)
  }

  calls <- new.env(parent = emptyenv())
  calls$created <- NULL
  calls$updated <- NULL

  mocked_names <- c(
    "get_silver_stream_repair_activity_plan",
    "ensure_transform_logging_tables",
    "create_transform_run",
    "update_transform_run"
  )
  original_bindings <- mget(
    mocked_names,
    envir = globalenv(),
    inherits = FALSE
  )

  on.exit(
    list2env(
      original_bindings,
      envir = globalenv()
    ),
    add = TRUE
  )

  assign(
    "get_silver_stream_repair_activity_plan",
    function(connection) {
      data.frame(
        activity_id = numeric(),
        expected_row_count = numeric()
      )
    },
    envir = globalenv()
  )
  assign(
    "ensure_transform_logging_tables",
    function(connection) {
      invisible(NULL)
    },
    envir = globalenv()
  )
  assign(
    "create_transform_run",
    function(...) {
      calls$created <- list(...)
      99L
    },
    envir = globalenv()
  )
  assign(
    "update_transform_run",
    function(...) {
      calls$updated <- list(...)
      invisible(NULL)
    },
    envir = globalenv()
  )

  expect_message(
    rebuild_silver_activity_streams(
      connection = "mock-connection",
      mode = "repair"
    ),
    "No silver activity streams require rebuild"
  )

  expect_equal(calls$created$total_batches, 0L)
  expect_equal(calls$created$activities_planned, 0L)
  expect_equal(calls$updated$transform_run_id, 99L)
  expect_equal(calls$updated$run_status, "SUCCESS")
})

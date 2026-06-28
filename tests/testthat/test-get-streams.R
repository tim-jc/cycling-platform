testthat::test_that("stream payload JSON preserves coordinate precision", {
  get_streams_file <- file.path(
    "R",
    "api",
    "get_streams.R"
  )

  if (!file.exists(get_streams_file)) {
    get_streams_file <- file.path(
      "..",
      "..",
      "R",
      "api",
      "get_streams.R"
    )
  }

  source(
    get_streams_file
  )

  latlng <- list(
    c(53.196583, -2.880290),
    c(53.196612, -2.880347)
  )

  payload <- stream_payload_to_json(latlng)

  testthat::expect_true(
    grepl(
      "53.196583",
      payload,
      fixed = TRUE
    )
  )

  testthat::expect_true(
    grepl(
      "-2.880347",
      payload,
      fixed = TRUE
    )
  )

  testthat::expect_false(
    grepl(
      "(^|\\[|,)53\\.1966(,|\\])",
      payload,
      perl = TRUE
    )
  )
})

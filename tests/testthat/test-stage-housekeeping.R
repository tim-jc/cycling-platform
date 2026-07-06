testthat::test_that("stage truncation requires explicit force", {
  stage_tables_file <- file.path(
    "R",
    "stage",
    "stage_tables.R"
  )

  truncate_stage_tables_file <- file.path(
    "R",
    "stage",
    "truncate_stage_tables.R"
  )

  if (!file.exists(stage_tables_file)) {
    stage_tables_file <- file.path(
      "..",
      "..",
      "R",
      "stage",
      "stage_tables.R"
    )
  }

  if (!file.exists(truncate_stage_tables_file)) {
    truncate_stage_tables_file <- file.path(
      "..",
      "..",
      "R",
      "stage",
      "truncate_stage_tables.R"
    )
  }

  source(stage_tables_file)
  source(truncate_stage_tables_file)

  testthat::expect_error(
    truncate_stage_tables(
      connection = NULL
    ),
    "force = TRUE",
    fixed = TRUE
  )
})

testthat::test_that("stage table validation rejects unknown tables", {
  stage_tables_file <- file.path(
    "R",
    "stage",
    "stage_tables.R"
  )

  if (!file.exists(stage_tables_file)) {
    stage_tables_file <- file.path(
      "..",
      "..",
      "R",
      "stage",
      "stage_tables.R"
    )
  }

  source(stage_tables_file)

  testthat::expect_error(
    validate_stage_tables("not_a_stage_table"),
    "Unknown stage table",
    fixed = TRUE
  )
})

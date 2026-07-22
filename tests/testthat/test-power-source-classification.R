testthat::test_that("TrainerRoad power cutoff gear defaults to roller bike", {
  admin_file <- file.path(
    "R",
    "admin",
    "ensure_power_source_classification.R"
  )

  if (!file.exists(admin_file)) {
    admin_file <- file.path(
      "..",
      "..",
      "R",
      "admin",
      "ensure_power_source_classification.R"
    )
  }

  source(admin_file)

  testthat::expect_equal(
    trainerroad_power_cutover_gear_id(list()),
    "b2708460"
  )
})

testthat::test_that("TrainerRoad power cutoff gear is config driven", {
  admin_file <- file.path(
    "R",
    "admin",
    "ensure_power_source_classification.R"
  )

  if (!file.exists(admin_file)) {
    admin_file <- file.path(
      "..",
      "..",
      "R",
      "admin",
      "ensure_power_source_classification.R"
    )
  }

  source(admin_file)

  config <- list(
    transforms = list(
      trainerroad_power_cutover_gear_id = "bike_a"
    )
  )

  testthat::expect_equal(
    trainerroad_power_cutover_gear_id(config),
    "bike_a"
  )
})

testthat::test_that("legacy power source gear helper returns TrainerRoad cutoff gear", {
  admin_file <- file.path(
    "R",
    "admin",
    "ensure_power_source_classification.R"
  )

  if (!file.exists(admin_file)) {
    admin_file <- file.path(
      "..",
      "..",
      "R",
      "admin",
      "ensure_power_source_classification.R"
    )
  }

  source(admin_file)

  testthat::expect_equal(
    power_source_cutover_gear_ids(list()),
    "b2708460"
  )
})

testthat::test_that("power source SQL placeholders match gear count", {
  admin_file <- file.path(
    "R",
    "admin",
    "ensure_power_source_classification.R"
  )

  if (!file.exists(admin_file)) {
    admin_file <- file.path(
      "..",
      "..",
      "R",
      "admin",
      "ensure_power_source_classification.R"
    )
  }

  source(admin_file)

  testthat::expect_equal(
    power_source_sql_placeholders("b2708460"),
    "?"
  )
})

testthat::test_that("TrainerRoad cutoff derivation defaults to roller bike only", {
  admin_file <- file.path(
    "R",
    "admin",
    "ensure_power_source_classification.R"
  )

  if (!file.exists(admin_file)) {
    admin_file <- file.path(
      "..",
      "..",
      "R",
      "admin",
      "ensure_power_source_classification.R"
    )
  }

  source(admin_file)

  testthat::expect_equal(
    formals(derive_power_meter_cutover)$approved_gear_ids,
    "b2708460"
  )
})

testthat::test_that("Silver SQL uses TrainerRoad roller-bike rule names", {
  sql_file <- file.path(
    "sql",
    "silver",
    "020_transform_activities.sql"
  )

  if (!file.exists(sql_file)) {
    sql_file <- file.path(
      "..",
      "..",
      "sql",
      "silver",
      "020_transform_activities.sql"
    )
  }

  sql <- paste(
    readLines(sql_file, warn = FALSE),
    collapse = "\n"
  )

  testthat::expect_true(
    grepl(
      "trainerroad_virtual_power_before_roller_bike_power_cutover",
      sql,
      fixed = TRUE
    )
  )

  testthat::expect_true(
    grepl(
      "trainerroad_at_or_after_roller_bike_power_cutover",
      sql,
      fixed = TRUE
    )
  )

  testthat::expect_false(
    grepl(
      "trainerroad_virtual_power_before_power_meter_cutover",
      sql,
      fixed = TRUE
    )
  )
})

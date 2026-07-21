testthat::test_that("power source cutover gear ids default to approved bikes", {
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
    c(
      "b2708460",
      "b3311095"
    )
  )
})

testthat::test_that("power source cutover gear ids are config driven", {
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
      power_source_cutover_gear_ids = c(
        "bike_a",
        "bike_b"
      )
    )
  )

  testthat::expect_equal(
    power_source_cutover_gear_ids(config),
    c(
      "bike_a",
      "bike_b"
    )
  )
})

testthat::test_that("power source SQL placeholders match approved gear count", {
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
    power_source_sql_placeholders(
      c(
        "b2708460",
        "b3311095"
      )
    ),
    "?, ?"
  )
})

inventory_project_root <- if (file.exists("R/config/platform_database_inventory.R")) "." else file.path("..", "..")
source(file.path(inventory_project_root, "R", "config", "platform_database_inventory.R"))

testthat::test_that("database inventory governs six databases and five durable backups", {
  inventory <- load_platform_database_inventory(inventory_project_root)
  testthat::expect_identical(nrow(inventory), 6L)
  testthat::expect_setequal(platform_required_databases(inventory), c(
    "cycling_platform_admin", "cycling_platform_raw", "cycling_platform_stage",
    "cycling_platform_reference", "cycling_platform_silver", "cycling_platform_gold"
  ))
  testthat::expect_identical(platform_backup_databases(inventory), c(
    "cycling_platform_admin", "cycling_platform_raw", "cycling_platform_reference",
    "cycling_platform_silver", "cycling_platform_gold"
  ))
  testthat::expect_false("cycling_platform_stage" %in% platform_backup_databases(inventory))
  testthat::expect_identical(platform_contract_domains(inventory), c("reference", "silver", "gold"))
})

testthat::test_that("missing and inaccessible Reference are actionable", {
  missing <- platform_database_access_findings(
    NULL,
    "cycling_platform_reference",
    function(...) stop("Unknown database 'cycling_platform_reference'")
  )
  inaccessible <- platform_database_access_findings(
    NULL,
    "cycling_platform_reference",
    function(...) stop("Access denied for user to database cycling_platform_reference")
  )
  testthat::expect_identical(missing$issue, "missing_database")
  testthat::expect_identical(inaccessible$issue, "inaccessible_database")
})

testthat::test_that("canonical Reference settings are inventory-driven", {
  inventory <- load_platform_database_inventory(inventory_project_root)
  reference <- inventory[inventory$domain == "reference", , drop = FALSE]
  testthat::expect_identical(reference$character_set, "utf8mb4")
  testthat::expect_identical(reference$collation, "utf8mb4_general_ci")
  testthat::expect_identical(platform_canonical_character_set(inventory), "utf8mb4")
  testthat::expect_identical(platform_canonical_collation(inventory), "utf8mb4_general_ci")

  validation <- paste(readLines(file.path(inventory_project_root, "R", "validation", "validate_platform_completeness.R")), collapse = "\n")
  testthat::expect_match(validation, "platform_required_databases_accessible", fixed = TRUE)
  testthat::expect_false(grepl("ALTER DATABASE", validation, fixed = TRUE))
})

testthat::test_that("collation validation detects incorrect Reference defaults", {
  source(file.path(
    inventory_project_root,
    "R",
    "validation",
    "validate_platform_completeness.R"
  ))
  query <- platform_collation_validation_query()

  testthat::expect_match(query, "cycling_platform_reference", fixed = TRUE)
  testthat::expect_match(
    query,
    "schemata.default_character_set_name <> 'utf8mb4'",
    fixed = TRUE
  )
  testthat::expect_match(
    query,
    "schemata.default_collation_name <> 'utf8mb4_general_ci'",
    fixed = TRUE
  )
  testthat::expect_false(grepl("ALTER DATABASE", query, fixed = TRUE))
  testthat::expect_false(grepl("CONVERT TO CHARACTER SET", query, fixed = TRUE))
})

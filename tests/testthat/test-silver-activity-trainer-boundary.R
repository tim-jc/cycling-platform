trainer_boundary_project_root <- function() {
  candidates <- c(".", "../..")
  root <- candidates[
    file.exists(file.path(candidates, "sql", "silver", "010_create_activities.sql"))
  ][1]
  normalizePath(root, mustWork = TRUE)
}

trainer_boundary_read <- function(...) {
  paste(
    readLines(file.path(trainer_boundary_project_root(), ...), warn = FALSE),
    collapse = "\n"
  )
}

testthat::test_that("Raw activity payload retains Strava trainer provenance", {
  source_payload <- data.frame(id = 1, trainer = TRUE)
  raw_payload <- jsonlite::toJSON(
    source_payload,
    auto_unbox = TRUE,
    null = "null"
  )
  decoded <- jsonlite::fromJSON(raw_payload, simplifyVector = FALSE)

  testthat::expect_true(decoded[[1]]$trainer)

  raw_ddl <- trainer_boundary_read("sql", "raw", "010_create_strava_activities.sql")
  ingestion <- trainer_boundary_read("R", "api", "get_activities.R")
  testthat::expect_match(raw_ddl, "raw_payload JSON NOT NULL", fixed = TRUE)
  testthat::expect_match(ingestion, "raw_payload = raw_payload", fixed = TRUE)
})

testthat::test_that("Silver activity schema and publication omit is_trainer", {
  ddl <- trainer_boundary_read("sql", "silver", "010_create_activities.sql")
  transform <- trainer_boundary_read("sql", "silver", "020_transform_activities.sql")

  testthat::expect_false(grepl("is_trainer BOOLEAN", ddl, fixed = TRUE))
  testthat::expect_false(grepl("is_trainer_raw AS is_trainer", transform, fixed = TRUE))
  testthat::expect_false(grepl("\n    is_trainer,", transform, fixed = TRUE))
  testthat::expect_match(ddl, "is_manual BOOLEAN NULL", fixed = TRUE)
  testthat::expect_match(ddl, "has_streams BOOLEAN NOT NULL", fixed = TRUE)
})

testthat::test_that("Raw trainer remains internal power-classification evidence", {
  transform <- trainer_boundary_read("sql", "silver", "020_transform_activities.sql")

  testthat::expect_match(
    transform,
    "JSON_EXTRACT(a.raw_payload, '$.trainer')",
    fixed = TRUE
  )
  testthat::expect_match(
    transform,
    "JSON_EXTRACT(a.raw_payload, '$[0].trainer')",
    fixed = TRUE
  )
  testthat::expect_match(
    transform,
    "COALESCE(evidence.is_trainer_raw, 0) = 0",
    fixed = TRUE
  )
  testthat::expect_match(
    transform,
    "evidence.source_identity_text LIKE '%trainerroad%'",
    fixed = TRUE
  )
  testthat::expect_false(grepl("is_indoor", transform, fixed = TRUE))
})

testthat::test_that("Power audit and validation read trainer from Raw", {
  report <- trainer_boundary_read("R", "quality", "report_power_source_classification.R")
  validation <- trainer_boundary_read("R", "validation", "validate_gold_publication.R")

  testthat::expect_false(grepl("activities.is_trainer", report, fixed = TRUE))
  testthat::expect_false(grepl("activities.is_trainer", validation, fixed = TRUE))
  testthat::expect_match(report, "AS source_trainer", fixed = TRUE)
  testthat::expect_match(report, "JSON_EXTRACT(raw.raw_payload, '$.trainer')", fixed = TRUE)
  testthat::expect_match(report, "NOT IN ('true', '1')", fixed = TRUE)
  testthat::expect_match(validation, "JSON_EXTRACT(raw.raw_payload, '$.trainer')", fixed = TRUE)
  testthat::expect_match(validation, "NOT IN ('true', '1')", fixed = TRUE)
})

testthat::test_that("migration and publication validation govern column absence", {
  migration <- trainer_boundary_read(
    "sql", "migrations", "010_drop_silver_activities_is_trainer.sql"
  )
  validation <- trainer_boundary_read(
    "R", "validation", "validate_platform_completeness.R"
  )

  testthat::expect_match(migration, "DROP COLUMN IF EXISTS is_trainer", fixed = TRUE)
  testthat::expect_match(
    validation,
    'check_name = "silver_activity_trainer_contract_shape"',
    fixed = TRUE
  )
  testthat::expect_match(validation, "forbidden_column_present", fixed = TRUE)
  testthat::expect_match(validation, "required_neighbouring_column_missing", fixed = TRUE)
})

testthat::test_that("Silver-to-Gold snapshots remain trainer-independent", {
  change_context <- trainer_boundary_read(
    "R", "transforms", "run_silver_transformations.R"
  )
  snapshot <- regmatches(
    change_context,
    regexpr(
      "silver_activity_gold_snapshot <- function[\\s\\S]*?\\n}",
      change_context,
      perl = TRUE
    )
  )

  testthat::expect_false(grepl("is_trainer", snapshot, fixed = TRUE))
  testthat::expect_match(snapshot, "power_source_type", fixed = TRUE)
  testthat::expect_match(snapshot, "is_power_record_eligible", fixed = TRUE)
})

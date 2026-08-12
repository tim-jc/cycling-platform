source_backup_observability <- function() {
  inventory_file <- file.path("R", "config", "platform_database_inventory.R")
  file <- file.path(
    "R",
    "utils",
    "backup_observability.R"
  )

  if (!file.exists(file)) {
    inventory_file <- file.path("..", "..", inventory_file)
    file <- file.path("..", "..", file)
  }

  source(inventory_file)
  source(file)
}

backup_manifest_fixture <- function() {
  databases <- c(
    "cycling_platform_admin",
    "cycling_platform_raw",
    "cycling_platform_reference",
    "cycling_platform_silver",
    "cycling_platform_gold"
  )

  list(
    started_at = as.POSIXct("2026-07-26 04:00:00", tz = "UTC"),
    completed_at = as.POSIXct("2026-07-26 04:06:00", tz = "UTC"),
    backup_host = "mac",
    source_host = "cycling-prod",
    run_prefix = "2026-07-26_050000",
    files = data.frame(
      database_name = databases,
      filename = paste0(
        "2026-07-26_050000_",
        databases,
        ".sql.gz"
      ),
      compressed_bytes = c(101, 202, 303, 404, 505),
      uncompressed_bytes = c(1001, 2002, 3003, 4004, 5005),
      verified_at = rep(
        as.POSIXct("2026-07-26 04:06:00", tz = "UTC"),
        5
      )
    )
  )
}

backup_inventory_fixture <- function(
  completed_at = as.POSIXct("2026-07-26 04:06:00", tz = "UTC")
) {
  manifest <- backup_manifest_fixture()

  list(
    runs = data.frame(
      backup_run_id = 1L,
      completed_at = completed_at,
      status = "SUCCESS",
      run_prefix = manifest$run_prefix,
      expected_database_count = 5L,
      created_at = completed_at
    ),
    files = data.frame(
      backup_run_id = 1L,
      database_name = manifest$files$database_name,
      filename = manifest$files$filename
    ),
    disk = data.frame(
      filename = manifest$files$filename,
      modified_at = rep(completed_at, 5),
      compressed_bytes = manifest$files$compressed_bytes
    )
  )
}

testthat::test_that("backup manifest requires exactly five durable databases", {
  source_backup_observability()

  manifest <- backup_manifest_fixture()

  testthat::expect_invisible(
    validate_backup_manifest(manifest)
  )

  incomplete <- manifest
  incomplete$files <- incomplete$files[-5, ]

  testthat::expect_error(
    validate_backup_manifest(incomplete),
    "coverage is invalid"
  )

  stage <- manifest
  stage$files$database_name[[5]] <- "cycling_platform_stage"

  testthat::expect_error(
    validate_backup_manifest(stage),
    "coverage is invalid"
  )
})

testthat::test_that("failed finalization preserves the prior success artefact", {
  source_backup_observability()

  status_path <- tempfile(fileext = ".json")
  manifest <- backup_manifest_fixture()

  write_backup_success_artifact(manifest, status_path)
  original <- readLines(status_path, warn = FALSE)

  incomplete <- manifest
  incomplete$files <- incomplete$files[-1, ]

  testthat::expect_error(
    write_backup_success_artifact(incomplete, status_path)
  )
  testthat::expect_equal(
    readLines(status_path, warn = FALSE),
    original
  )
})

testthat::test_that("success artefact contains host, run and per-file metadata", {
  source_backup_observability()

  status_path <- tempfile(fileext = ".json")
  manifest <- backup_manifest_fixture()

  write_backup_success_artifact(manifest, status_path)
  artifact <- jsonlite::read_json(status_path, simplifyVector = TRUE)

  testthat::expect_equal(artifact$status, "SUCCESS")
  testthat::expect_equal(artifact$backup_host, "mac")
  testthat::expect_equal(artifact$source_host, "cycling-prod")
  testthat::expect_equal(artifact$run_prefix, "2026-07-26_050000")
  testthat::expect_setequal(
    artifact$databases,
    backup_expected_databases()
  )
  testthat::expect_equal(nrow(artifact$files), 5L)
  testthat::expect_equal(
    artifact$files$compressed_bytes,
    c(101, 202, 303, 404, 505)
  )
})

testthat::test_that("successful manifest produces complete append-only metadata", {
  source_backup_observability()

  metadata <- backup_run_metadata(backup_manifest_fixture())

  testthat::expect_equal(metadata$status, "SUCCESS")
  testthat::expect_equal(metadata$expected_database_count, 5L)
  testthat::expect_equal(metadata$successful_database_count, 5L)
  testthat::expect_equal(metadata$duration_seconds, 360L)
  testthat::expect_equal(metadata$total_compressed_bytes, 1515)
})

testthat::test_that("success artefact reader handles missing and malformed files", {
  source_backup_observability()

  missing <- tempfile(fileext = ".json")

  testthat::expect_equal(
    read_backup_success_artifact(missing)$status,
    "MISSING"
  )

  malformed <- tempfile(fileext = ".json")
  writeLines("{not-json", malformed)

  testthat::expect_equal(
    read_backup_success_artifact(malformed)$status,
    "MALFORMED"
  )
})

testthat::test_that("historical four-database success artefacts remain readable", {
  source_backup_observability()
  path <- tempfile(fileext = ".json")
  jsonlite::write_json(
    list(status = "SUCCESS", databases = backup_legacy_databases()),
    path,
    auto_unbox = TRUE
  )
  testthat::expect_identical(read_backup_success_artifact(path)$status, "VALID")
})

testthat::test_that("backup freshness thresholds are inclusive at 30 and 48 hours", {
  source_backup_observability()

  now <- as.POSIXct("2026-07-27 10:00:00", tz = "UTC")

  testthat::expect_equal(
    backup_freshness_status(now - 30 * 3600, now)$status,
    "HEALTHY"
  )
  testthat::expect_equal(
    backup_freshness_status(now - 31 * 3600, now)$status,
    "STALE"
  )
  testthat::expect_equal(
    backup_freshness_status(now - 48 * 3600, now)$status,
    "STALE"
  )
  testthat::expect_equal(
    backup_freshness_status(now - 49 * 3600, now)$status,
    "CRITICAL"
  )
  testthat::expect_equal(
    backup_freshness_status(as.POSIXct(NA), now)$status,
    "MISSING"
  )
})

testthat::test_that("latest failure does not invalidate an earlier fresh success", {
  source_backup_observability()

  now <- as.POSIXct("2026-07-27 10:00:00", tz = "UTC")
  successful_at <- now - 20 * 3600

  # Freshness is deliberately based on latest SUCCESS, not latest attempted run.
  testthat::expect_equal(
    backup_freshness_status(successful_at, now)$status,
    "HEALTHY"
  )
})

testthat::test_that("complete retained backup inventory reconciles cleanly", {
  source_backup_observability()

  inventory <- backup_inventory_fixture()
  result <- reconcile_backup_inventory(
    backup_runs = inventory$runs,
    backup_run_files = inventory$files,
    disk_files = inventory$disk,
    now = as.POSIXct("2026-07-27 04:00:00", tz = "UTC"),
    retention_days = 30
  )

  testthat::expect_equal(result$status, "HEALTHY")
  testthat::expect_equal(result$missing_file_count, 0L)
  testthat::expect_equal(result$incomplete_run_count, 0L)
  testthat::expect_equal(result$orphan_file_count, 0L)
})

testthat::test_that("historical four-database backup sets remain recognised", {
  source_backup_observability()
  inventory <- backup_inventory_fixture()
  reference_row <- inventory$files$database_name == "cycling_platform_reference"
  reference_file <- inventory$files$filename[reference_row]
  inventory$files <- inventory$files[!reference_row, , drop = FALSE]
  inventory$runs$expected_database_count <- 4L
  inventory$disk <- inventory$disk[
    inventory$disk$filename != reference_file,
    ,
    drop = FALSE
  ]

  testthat::expect_true(
    backup_database_set_is_recognised(inventory$files$database_name)
  )
  result <- reconcile_backup_inventory(
    inventory$runs,
    inventory$files,
    inventory$disk,
    now = as.POSIXct("2026-07-27 04:00:00", tz = "UTC")
  )
  testthat::expect_equal(result$status, "HEALTHY")
  testthat::expect_equal(result$incomplete_run_count, 0L)
})

testthat::test_that("mixed historical and current generations reconcile", {
  source_backup_observability()
  current <- backup_inventory_fixture(
    as.POSIXct("2026-08-11 05:06:00", tz = "UTC")
  )
  legacy_databases <- backup_legacy_databases()
  legacy_prefix <- "2026-08-05_050000"
  legacy_completed <- as.POSIXct("2026-08-05 05:06:00", tz = "UTC")
  runs <- rbind(
    data.frame(
      backup_run_id = 2L,
      completed_at = legacy_completed,
      status = "SUCCESS",
      run_prefix = legacy_prefix,
      expected_database_count = 4L,
      created_at = legacy_completed
    ),
    current$runs
  )
  files <- rbind(
    data.frame(
      backup_run_id = 2L,
      database_name = legacy_databases,
      filename = paste0(legacy_prefix, "_", legacy_databases, ".sql.gz")
    ),
    current$files
  )
  disk <- rbind(
    data.frame(
      filename = paste0(legacy_prefix, "_", legacy_databases, ".sql.gz"),
      modified_at = rep(legacy_completed, 4L),
      compressed_bytes = rep(100, 4L)
    ),
    current$disk
  )

  result <- reconcile_backup_inventory(
    runs,
    files,
    disk,
    now = as.POSIXct("2026-08-12 05:00:00", tz = "UTC")
  )
  testthat::expect_equal(result$status, "HEALTHY")
  testthat::expect_equal(result$retained_file_count, 9L)
  testthat::expect_equal(result$incomplete_run_count, 0L)
  testthat::expect_silent(
    jsonlite::toJSON(result$issues, auto_unbox = TRUE)
  )
})

testthat::test_that("set-aware retention preserves newest complete set", {
  source_backup_observability()
  databases <- backup_expected_databases()
  prefixes <- c("2026-05-01_050000", "2026-06-01_050000")
  disk <- do.call(rbind, lapply(seq_along(prefixes), function(index) {
    data.frame(
      filename = paste0(prefixes[[index]], "_", databases, ".sql.gz"),
      modified_at = rep(
        as.POSIXct(paste0(substr(prefixes[[index]], 1, 10), " 05:00:00"), tz = "UTC"),
        length(databases)
      ),
      compressed_bytes = 100
    )
  }))
  plan <- backup_retention_plan(
    disk,
    now = as.POSIXct("2026-08-12 05:00:00", tz = "UTC"),
    retention_days = 30
  )
  testthat::expect_identical(
    plan$newest_complete_prefix,
    "2026-06-01_050000"
  )
  testthat::expect_true(all(grepl(
    "2026-05-01_050000",
    plan$delete_files,
    fixed = TRUE
  )))
  testthat::expect_false(any(grepl(
    "2026-06-01_050000",
    plan$delete_files,
    fixed = TRUE
  )))
})

testthat::test_that("set-aware retention handles partial prefixes as sets", {
  source_backup_observability()
  prefix <- "2026-05-01_050000"
  databases <- backup_expected_databases()[1:2]
  disk <- data.frame(
    filename = paste0(prefix, "_", databases, ".sql.gz"),
    modified_at = rep(as.POSIXct("2026-05-01 05:00:00", tz = "UTC"), 2L),
    compressed_bytes = 100
  )
  sets <- classify_backup_sets(disk)
  testthat::expect_identical(sets$format, "incomplete")
  testthat::expect_false(sets$complete)
  plan <- backup_retention_plan(
    disk,
    now = as.POSIXct("2026-08-12 05:00:00", tz = "UTC"),
    retention_days = 30
  )
  testthat::expect_setequal(plan$delete_files, disk$filename)
  testthat::expect_true(is.na(plan$newest_complete_prefix))
})

testthat::test_that("four-file prefixes after current format begins are incomplete", {
  source_backup_observability()
  current_prefix <- "2026-08-11_050000"
  partial_prefix <- "2026-08-12_050000"
  disk <- rbind(
    data.frame(
      filename = paste0(
        current_prefix, "_", backup_expected_databases(), ".sql.gz"
      ),
      modified_at = as.POSIXct("2026-08-11 05:06:00", tz = "UTC"),
      compressed_bytes = 100
    ),
    data.frame(
      filename = paste0(
        partial_prefix, "_", backup_legacy_databases(), ".sql.gz"
      ),
      modified_at = as.POSIXct("2026-08-12 05:06:00", tz = "UTC"),
      compressed_bytes = 100
    )
  )
  sets <- classify_backup_sets(disk)
  partial <- sets[sets$run_prefix == partial_prefix, , drop = FALSE]
  testthat::expect_identical(partial$format, "incomplete")
  testthat::expect_false(partial$complete)
})

testthat::test_that("a new-format run missing Reference is incomplete", {
  source_backup_observability()
  inventory <- backup_inventory_fixture()
  reference_row <- inventory$files$database_name == "cycling_platform_reference"
  reference_file <- inventory$files$filename[reference_row]
  inventory$files <- inventory$files[!reference_row, , drop = FALSE]
  inventory$disk <- inventory$disk[
    inventory$disk$filename != reference_file,
    ,
    drop = FALSE
  ]

  result <- reconcile_backup_inventory(
    inventory$runs,
    inventory$files,
    inventory$disk,
    now = as.POSIXct("2026-07-27 04:00:00", tz = "UTC")
  )
  testthat::expect_equal(result$status, "WARNING")
  testthat::expect_equal(result$missing_file_count, 1L)
  testthat::expect_equal(result$incomplete_run_count, 1L)
})

testthat::test_that("reconciliation detects missing and incomplete retained runs", {
  source_backup_observability()

  inventory <- backup_inventory_fixture()
  inventory$disk <- inventory$disk[-1, ]

  result <- reconcile_backup_inventory(
    inventory$runs,
    inventory$files,
    inventory$disk,
    now = as.POSIXct("2026-07-27 04:00:00", tz = "UTC")
  )

  testthat::expect_equal(result$status, "WARNING")
  testthat::expect_equal(result$missing_file_count, 1L)
  testthat::expect_equal(result$incomplete_run_count, 1L)
})

testthat::test_that("reconciliation detects incomplete metadata schema coverage", {
  source_backup_observability()

  inventory <- backup_inventory_fixture()
  inventory$files <- inventory$files[-1, ]
  inventory$disk <- inventory$disk[-1, ]

  result <- reconcile_backup_inventory(
    inventory$runs,
    inventory$files,
    inventory$disk,
    now = as.POSIXct("2026-07-27 04:00:00", tz = "UTC")
  )

  testthat::expect_equal(result$incomplete_run_count, 1L)
})

testthat::test_that("reconciliation detects orphan and malformed files", {
  source_backup_observability()

  inventory <- backup_inventory_fixture()
  extra <- data.frame(
    filename = "unexpected.sql.gz",
    modified_at = as.POSIXct("2026-07-27 03:00:00", tz = "UTC"),
    compressed_bytes = 100
  )
  inventory$disk <- rbind(inventory$disk, extra)

  result <- reconcile_backup_inventory(
    inventory$runs,
    inventory$files,
    inventory$disk,
    now = as.POSIXct("2026-07-27 04:00:00", tz = "UTC"),
    managed_since = as.POSIXct("2026-07-26 00:00:00", tz = "UTC")
  )

  testthat::expect_equal(result$orphan_file_count, 1L)
  testthat::expect_equal(result$unexpected_file_count, 1L)
})

testthat::test_that("reconciliation treats stage files as unexpected", {
  source_backup_observability()

  inventory <- backup_inventory_fixture()
  stage <- data.frame(
    filename = "2026-07-27_050000_cycling_platform_stage.sql.gz",
    modified_at = as.POSIXct("2026-07-27 03:00:00", tz = "UTC"),
    compressed_bytes = 100
  )
  inventory$disk <- rbind(inventory$disk, stage)

  result <- reconcile_backup_inventory(
    inventory$runs,
    inventory$files,
    inventory$disk,
    now = as.POSIXct("2026-07-27 04:00:00", tz = "UTC"),
    managed_since = as.POSIXct("2026-07-26 00:00:00", tz = "UTC")
  )

  testthat::expect_equal(result$unexpected_file_count, 1L)
})

testthat::test_that("reconciliation detects retained files beyond retention", {
  source_backup_observability()

  inventory <- backup_inventory_fixture()
  inventory$disk$modified_at[[1]] <- as.POSIXct(
    "2026-06-01 04:00:00",
    tz = "UTC"
  )

  result <- reconcile_backup_inventory(
    inventory$runs,
    inventory$files,
    inventory$disk,
    now = as.POSIXct("2026-07-27 04:00:00", tz = "UTC"),
    retention_days = 30
  )

  testthat::expect_equal(result$expired_file_count, 1L)
})

testthat::test_that("expired metadata does not require expired files", {
  source_backup_observability()

  inventory <- backup_inventory_fixture(
    completed_at = as.POSIXct("2026-05-01 04:00:00", tz = "UTC")
  )
  inventory$disk <- inventory$disk[0, ]

  result <- reconcile_backup_inventory(
    inventory$runs,
    inventory$files,
    inventory$disk,
    now = as.POSIXct("2026-07-27 04:00:00", tz = "UTC"),
    retention_days = 30
  )

  testthat::expect_equal(result$status, "HEALTHY")
  testthat::expect_equal(result$missing_file_count, 0L)
})

backup_health_fixture <- function(
  freshness_status,
  age_hours,
  reconciliation_status = "HEALTHY"
) {
  list(
    latest_success = data.frame(
      completed_at = as.POSIXct("2026-07-26 04:06:00", tz = "UTC"),
      source_host = "cycling-prod",
      run_prefix = "2026-07-26_050000"
    ),
    latest_reconciliation = data.frame(
      status = reconciliation_status,
      retention_days = 30L,
      missing_file_count = 0L,
      incomplete_run_count = 0L,
      orphan_file_count = 0L,
      expired_file_count = 0L,
      unexpected_file_count = 0L
    ),
    freshness_status = freshness_status,
    age_hours = age_hours
  )
}

testthat::test_that("backup notification wording covers health levels", {
  source_backup_observability()

  healthy <- format_backup_health_lines(
    backup_health_fixture("HEALTHY", 21)
  )
  stale <- format_backup_health_lines(
    backup_health_fixture("STALE", 31)
  )
  critical <- format_backup_health_lines(
    backup_health_fixture("CRITICAL", 49)
  )

  testthat::expect_match(healthy[[1]], "21h ago ✓", fixed = TRUE)
  testthat::expect_match(stale[[1]], "STALE", fixed = TRUE)
  testthat::expect_match(critical[[1]], "CRITICAL", fixed = TRUE)
  testthat::expect_match(
    healthy[[2]],
    "30-day set reconciled ✓",
    fixed = TRUE
  )
})

testthat::test_that("backup notification reports reconciliation warnings", {
  source_backup_observability()

  health <- backup_health_fixture("HEALTHY", 21, "WARNING")
  health$latest_reconciliation$missing_file_count <- 1L

  lines <- format_backup_health_lines(health)

  testthat::expect_match(lines[[2]], "Retention: WARNING", fixed = TRUE)
  testthat::expect_match(lines[[2]], "missing 1", fixed = TRUE)
})

testthat::test_that("backup notification reports missing observability", {
  source_backup_observability()

  health <- list(
    latest_success = data.frame(),
    latest_reconciliation = data.frame(),
    freshness_status = "MISSING",
    age_hours = NA_real_
  )

  lines <- format_backup_health_lines(health)

  testthat::expect_match(
    lines[[1]],
    "no successful backup recorded",
    fixed = TRUE
  )
  testthat::expect_match(
    lines[[2]],
    "no reconciliation recorded",
    fixed = TRUE
  )
})

testthat::test_that("backup script does not introduce success notifications", {
  script <- file.path("scripts", "backup_mariadb.sh")

  if (!file.exists(script)) {
    script <- file.path("..", "..", script)
  }

  text <- paste(readLines(script, warn = FALSE), collapse = "\n")

  testthat::expect_false(grepl("ntfy", text, ignore.case = TRUE))
  testthat::expect_false(grepl("send_notification", text, fixed = TRUE))
})

testthat::test_that("backup script derives the durable set from the shared inventory", {
  script <- file.path("scripts", "backup_mariadb.sh")
  inventory <- file.path("config", "platform_databases.tsv")

  if (!file.exists(script)) {
    script <- file.path("..", "..", script)
    inventory <- file.path("..", "..", inventory)
  }

  text <- paste(readLines(script, warn = FALSE), collapse = "\n")
  configured <- utils::read.delim(inventory, stringsAsFactors = FALSE)
  durable <- configured$database_name[configured$backup_included]

  testthat::expect_match(text, "config/platform_databases.tsv", fixed = TRUE)
  testthat::expect_identical(durable, c(
    "cycling_platform_admin",
    "cycling_platform_raw",
    "cycling_platform_reference",
    "cycling_platform_silver",
    "cycling_platform_gold"
  ))
  testthat::expect_false("cycling_platform_stage" %in% durable)
})

testthat::test_that("backup observability R runs from an unprotected runtime", {
  script <- file.path("scripts", "backup_mariadb.sh")

  if (!file.exists(script)) {
    script <- file.path("..", "..", script)
  }

  text <- paste(readLines(script, warn = FALSE), collapse = "\n")

  testthat::expect_match(
    text,
    "/tmp/cycling-platform-backup-runtime-\\$\\$"
  )
  testthat::expect_match(
    text,
    'Rscript - \\',
    fixed = TRUE
  )
  testthat::expect_match(
    text,
    '--exclude "backups"',
    fixed = TRUE
  )
  testthat::expect_false(
    grepl('--exclude "renv/library"', text, fixed = TRUE)
  )
  testthat::expect_match(
    text,
    'cp "$RUNTIME_STATUS_FILE" "${BACKUP_STATUS_FILE}.tmp"',
    fixed = TRUE
  )
  testthat::expect_match(
    text,
    ') < "$RUNTIME_FINALIZER_SCRIPT"',
    fixed = TRUE
  )
  testthat::expect_false(
    grepl(
      ') < "$PROJECT_DIR/scripts/finalize_backup_observability.R"',
      text,
      fixed = TRUE
    )
  )
})

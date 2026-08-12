find_backup_workflow_root <- function() {
  candidates <- c(".", "../..")
  candidate <- candidates[file.exists(file.path(candidates, "bootstrap.R"))][1]
  normalizePath(candidate, mustWork = TRUE)
}

backup_workflow_root <- find_backup_workflow_root()

write_executable <- function(path, lines) {
  writeLines(c("#!/usr/bin/env bash", lines), path)
  Sys.chmod(path, "0755")
  path
}

run_physical_backup_fixture <- function(
  directory,
  dump_lines,
  nc_status = 0L,
  lock_directory = file.path(directory, "backup.lock"),
  attempts = 1L
) {
  dump <- write_executable(
    file.path(directory, "mysqldump"),
    dump_lines
  )
  nc <- write_executable(
    file.path(directory, "nc"),
    c(paste("exit", as.integer(nc_status)))
  )
  log <- file.path(directory, "backup.log")
  status <- system2(
    "bash",
    file.path(backup_workflow_root, "scripts/backup_mariadb.sh"),
    env = c(
      paste0("MYSQLDUMP=", dump),
      paste0("NC_BIN=", nc),
      paste0("BACKUP_DIR=", file.path(directory, "backups")),
      paste0("BACKUP_LOCK_DIR=", lock_directory),
      paste0("BACKUP_DUMP_MAX_ATTEMPTS=", attempts),
      "BACKUP_DUMP_RETRY_SLEEP_SECONDS=1",
      "MARIADB_HOST=fixture-host",
      "MARIADB_PORT=3306",
      "MARIADB_USER=fixture-user",
      "MARIADB_PASSWORD=fixture-password"
    ),
    stdout = log,
    stderr = log
  )
  list(status = status, log = readLines(log, warn = FALSE))
}

write_backup_health_artifact <- function(path, completed_at) {
  databases <- c(
    "cycling_platform_admin",
    "cycling_platform_raw",
    "cycling_platform_reference",
    "cycling_platform_silver",
    "cycling_platform_gold"
  )
  filenames <- paste0(
    "2026-08-11_050000_", databases, ".sql.gz"
  )
  vapply(
    file.path(dirname(path), filenames),
    function(file) {
      writeBin(as.raw(1L), file)
      file
    },
    character(1)
  )
  jsonlite::write_json(
    list(
      status = "SUCCESS",
      started_at = "2026-08-11T04:00:00Z",
      completed_at = completed_at,
      backup_host = "mac",
      source_host = "cycling-prod",
      run_prefix = "2026-08-11_050000",
      databases = databases,
      files = data.frame(
        database_name = databases,
        filename = filenames
      )
    ),
    path,
    auto_unbox = TRUE
  )
}

testthat::test_that("physical health uses Mac artefact authority", {
  source(file.path(
    backup_workflow_root,
    "R/config/platform_database_inventory.R"
  ))
  source(file.path(
    backup_workflow_root,
    "R/utils/backup_observability.R"
  ))
  now <- as.POSIXct("2026-08-12 12:00:00", tz = "UTC")
  testthat::expect_identical(
    backup_freshness_status(now - 30 * 3600, now)$status,
    "HEALTHY"
  )
  testthat::expect_identical(
    backup_freshness_status(now - 31 * 3600, now)$status,
    "STALE"
  )
  testthat::expect_identical(
    backup_freshness_status(now - 49 * 3600, now)$status,
    "CRITICAL"
  )
})

testthat::test_that("physical health rejects an artefact whose dumps are absent", {
  directory <- tempfile("backup-health-")
  dir.create(directory)
  artifact <- file.path(directory, "latest_success.json")
  write_backup_health_artifact(
    artifact,
    format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
  unlink(file.path(
    directory,
    "2026-08-11_050000_cycling_platform_gold.sql.gz"
  ))
  output <- withr::with_dir(
    backup_workflow_root,
    system2(
      "Rscript",
      c(
        "scripts/check_backup_physical_health.R",
        artifact,
        "30",
        "48"
      ),
      stdout = TRUE
    )
  )
  testthat::expect_match(output[[length(output)]], "^INCOMPLETE\\t")
})

testthat::test_that("workflow preserves backup failure when notification fails", {
  directory <- tempfile("backup-workflow-")
  dir.create(directory)
  artifact <- file.path(directory, "latest_success.json")
  write_backup_health_artifact(
    artifact,
    format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
  backup_command <- file.path(directory, "backup.sh")
  curl_command <- file.path(directory, "curl.sh")
  writeLines(c("#!/usr/bin/env bash", "exit 7"), backup_command)
  writeLines(c("#!/usr/bin/env bash", "exit 9"), curl_command)
  Sys.chmod(c(backup_command, curl_command), "0755")

  status <- system2(
    "bash",
    c(file.path(
      backup_workflow_root,
      "scripts/run_backup_workflow.sh"
    ), "backup"),
    env = c(
      paste0("BACKUP_COMMAND=", backup_command),
      paste0("CURL_BIN=", curl_command),
      paste0("BACKUP_STATUS_FILE=", artifact),
      paste0("BACKUP_ALERT_STATE_DIR=", file.path(directory, "state")),
      "NTFY_TOPIC=fixture-topic"
    ),
    stdout = FALSE,
    stderr = FALSE
  )
  testthat::expect_equal(status, 7L)
})

testthat::test_that("verified dumps followed by finalizer failure are identified", {
  directory <- tempfile("backup-workflow-")
  dir.create(directory)
  artifact <- file.path(directory, "latest_success.json")
  write_backup_health_artifact(
    artifact,
    format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
  backup_command <- write_executable(
    file.path(directory, "backup.sh"),
    c(
      "printf '%s\\n' '2026-08-12_050000' > \"$BACKUP_PHYSICAL_SUCCESS_MARKER\"",
      "exit 7"
    )
  )
  delivery <- file.path(directory, "delivery")
  curl_command <- write_executable(
    file.path(directory, "curl.sh"),
    c("printf '%s\\n' \"$@\" > \"$TEST_DELIVERY\"", "exit 0")
  )

  status <- system2(
    "bash",
    c(file.path(
      backup_workflow_root,
      "scripts/run_backup_workflow.sh"
    ), "backup"),
    env = c(
      paste0("BACKUP_COMMAND=", backup_command),
      paste0("CURL_BIN=", curl_command),
      paste0("TEST_DELIVERY=", delivery),
      paste0("BACKUP_STATUS_FILE=", artifact),
      paste0("BACKUP_ALERT_STATE_DIR=", file.path(directory, "state")),
      "NTFY_TOPIC=fixture-topic"
    ),
    stdout = FALSE,
    stderr = FALSE
  )
  testthat::expect_equal(status, 7L)
  testthat::expect_true(any(grepl(
    "Failure class: observability/finalizer",
    readLines(delivery, warn = FALSE),
    fixed = TRUE
  )))
})

testthat::test_that("physical backup respects active and removes stale locks", {
  active_directory <- tempfile("backup-physical-")
  dir.create(active_directory)
  active_lock <- file.path(active_directory, "active.lock")
  dir.create(active_lock)
  writeLines(as.character(Sys.getpid()), file.path(active_lock, "pid"))
  writeLines(as.character(as.integer(Sys.time())), file.path(active_lock, "started_at"))
  active <- run_physical_backup_fixture(
    active_directory,
    c("exit 99"),
    lock_directory = active_lock
  )
  testthat::expect_equal(active$status, 0L)
  testthat::expect_true(any(grepl("another backup run is active", active$log)))
  testthat::expect_true(dir.exists(active_lock))

  stale_directory <- tempfile("backup-physical-")
  dir.create(stale_directory)
  stale_lock <- file.path(stale_directory, "stale.lock")
  dir.create(stale_lock)
  writeLines("99999999", file.path(stale_lock, "pid"))
  writeLines("1", file.path(stale_lock, "started_at"))
  stale <- run_physical_backup_fixture(
    stale_directory,
    c("exit 99"),
    nc_status = 1L,
    lock_directory = stale_lock
  )
  testthat::expect_equal(stale$status, 1L)
  testthat::expect_true(any(grepl("stale lock removed", stale$log)))
  testthat::expect_false(dir.exists(stale_lock))
})

testthat::test_that("source and dump failures preserve retry safety", {
  unreachable_directory <- tempfile("backup-physical-")
  dir.create(unreachable_directory)
  unreachable <- run_physical_backup_fixture(
    unreachable_directory,
    c("exit 99"),
    nc_status = 1L
  )
  testthat::expect_equal(unreachable$status, 1L)
  testthat::expect_true(any(grepl(
    "TCP connectivity check failed",
    unreachable$log
  )))

  retry_directory <- tempfile("backup-physical-")
  dir.create(retry_directory)
  attempts_file <- file.path(retry_directory, "attempts")
  failed_dump <- run_physical_backup_fixture(
    retry_directory,
    c(
      "if [[ \"${1:-}\" == \"--help\" ]]; then exit 0; fi",
      paste0("printf 'attempt\\n' >> '", attempts_file, "'"),
      "exit 1"
    ),
    attempts = 2L
  )
  testthat::expect_equal(failed_dump$status, 1L)
  testthat::expect_length(readLines(attempts_file), 2L)
  testthat::expect_true(any(grepl("after 2 attempt", failed_dump$log)))
})

testthat::test_that("empty dump is rejected before publication", {
  directory <- tempfile("backup-physical-")
  dir.create(directory)
  result <- run_physical_backup_fixture(
    directory,
    c(
      "if [[ \"${1:-}\" == \"--help\" ]]; then exit 0; fi",
      "exit 0"
    )
  )
  testthat::expect_equal(result$status, 1L)
  testthat::expect_true(any(grepl("uncompressed dump is empty", result$log)))
  testthat::expect_false(file.exists(file.path(
    directory,
    "backups",
    "latest_success.json"
  )))
})

testthat::test_that("successful backup must advance latest-success authority", {
  directory <- tempfile("backup-workflow-")
  dir.create(directory)
  artifact <- file.path(directory, "latest_success.json")
  write_backup_health_artifact(
    artifact,
    format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
  backup_command <- file.path(directory, "backup.sh")
  curl_command <- file.path(directory, "curl.sh")
  writeLines(c(
    "#!/usr/bin/env bash",
    "printf '%s\\n' '2026-08-12_050000' > \"$BACKUP_PHYSICAL_SUCCESS_MARKER\"",
    "exit 0"
  ), backup_command)
  writeLines(c("#!/usr/bin/env bash", "exit 0"), curl_command)
  Sys.chmod(c(backup_command, curl_command), "0755")

  status <- system2(
    "bash",
    c(file.path(
      backup_workflow_root,
      "scripts/run_backup_workflow.sh"
    ), "backup"),
    env = c(
      paste0("BACKUP_COMMAND=", backup_command),
      paste0("CURL_BIN=", curl_command),
      paste0("BACKUP_STATUS_FILE=", artifact),
      paste0("BACKUP_ALERT_STATE_DIR=", file.path(directory, "state")),
      "NTFY_TOPIC=fixture-topic"
    ),
    stdout = FALSE,
    stderr = FALSE
  )
  testthat::expect_equal(status, 1L)
})

testthat::test_that("successful backup accepts a matching latest-success prefix", {
  directory <- tempfile("backup-workflow-")
  dir.create(directory)
  artifact <- file.path(directory, "latest_success.json")
  write_backup_health_artifact(
    artifact,
    format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
  backup_command <- file.path(directory, "backup.sh")
  writeLines(c(
    "#!/usr/bin/env bash",
    "printf '%s\\n' '2026-08-11_050000' > \"$BACKUP_PHYSICAL_SUCCESS_MARKER\"",
    "exit 0"
  ), backup_command)
  Sys.chmod(backup_command, "0755")

  status <- system2(
    "bash",
    c(file.path(
      backup_workflow_root,
      "scripts/run_backup_workflow.sh"
    ), "backup"),
    env = c(
      paste0("BACKUP_COMMAND=", backup_command),
      paste0("BACKUP_STATUS_FILE=", artifact),
      paste0("BACKUP_ALERT_STATE_DIR=", file.path(directory, "state")),
      "NTFY_TOPIC="
    ),
    stdout = FALSE,
    stderr = FALSE
  )
  testthat::expect_equal(status, 0L)
})

testthat::test_that("stale alert is sent once for an unchanged condition", {
  directory <- tempfile("backup-workflow-")
  dir.create(directory)
  artifact <- file.path(directory, "latest_success.json")
  write_backup_health_artifact(artifact, "2020-01-01T00:00:00Z")
  deliveries <- file.path(directory, "deliveries")
  curl_command <- file.path(directory, "curl.sh")
  writeLines(c(
    "#!/usr/bin/env bash",
    "printf 'delivered\\n' >> \"$TEST_DELIVERIES\"",
    "exit 0"
  ), curl_command)
  Sys.chmod(curl_command, "0755")
  command <- c(file.path(
    backup_workflow_root,
    "scripts/run_backup_workflow.sh"
  ), "check")
  environment <- c(
    paste0("CURL_BIN=", curl_command),
    paste0("TEST_DELIVERIES=", deliveries),
    paste0("BACKUP_STATUS_FILE=", artifact),
    paste0("BACKUP_ALERT_STATE_DIR=", file.path(directory, "state")),
    "NTFY_TOPIC=fixture-topic"
  )

  first <- system2("bash", command, env = environment, stdout = FALSE)
  second <- system2("bash", command, env = environment, stdout = FALSE)
  testthat::expect_equal(first, 0L)
  testthat::expect_equal(second, 0L)
  testthat::expect_length(readLines(deliveries), 1L)
})

testthat::test_that("backup workflow distinguishes finalizer failures", {
  script <- paste(readLines(
    file.path(backup_workflow_root, "scripts/run_backup_workflow.sh"),
    warn = FALSE
  ), collapse = "\n")
  backup_script <- paste(readLines(
    file.path(backup_workflow_root, "scripts/backup_mariadb.sh"),
    warn = FALSE
  ), collapse = "\n")
  testthat::expect_match(
    script,
    'failure_class="observability/finalizer"',
    fixed = TRUE
  )
  testthat::expect_match(
    backup_script,
    "BACKUP_PHYSICAL_SUCCESS_MARKER",
    fixed = TRUE
  )
})

testthat::test_that("physical backup retains its established safety checks", {
  backup_script <- paste(readLines(
    file.path(backup_workflow_root, "scripts/backup_mariadb.sh"),
    warn = FALSE
  ), collapse = "\n")
  testthat::expect_match(backup_script, "BACKUP_DUMP_MAX_ATTEMPTS", fixed = TRUE)
  testthat::expect_match(backup_script, "gzip -t", fixed = TRUE)
  testthat::expect_match(
    backup_script,
    '[[ ! -s "$temporary_output_file" ]]',
    fixed = TRUE
  )
  testthat::expect_match(backup_script, "LOCK_MAX_AGE_SECONDS", fixed = TRUE)
  testthat::expect_match(
    backup_script,
    "MariaDB TCP connectivity check failed",
    fixed = TRUE
  )
})

testthat::test_that("restored Admin warning explains metadata lag", {
  source(file.path(
    backup_workflow_root,
    "R/config/platform_database_inventory.R"
  ))
  source(file.path(
    backup_workflow_root,
    "R/utils/backup_observability.R"
  ))
  lines <- format_backup_health_lines(list(
    latest_success = data.frame(),
    latest_reconciliation = data.frame(),
    freshness_status = "MISSING",
    age_hours = NA_real_
  ))
  testthat::expect_match(lines[[1]], "Admin metadata may lag", fixed = TRUE)
})

find_backup_launchd_root <- function() {
  candidates <- c(".", "../..")
  candidate <- candidates[file.exists(file.path(
    candidates,
    "scripts",
    "install_backup_launchd.sh"
  ))][1]
  normalizePath(candidate, mustWork = TRUE)
}

backup_launchd_root <- find_backup_launchd_root()
backup_launchd_installer <- file.path(
  backup_launchd_root,
  "scripts",
  "install_backup_launchd.sh"
)

write_fake_macos_command <- function(directory, name) {
  path <- file.path(directory, name)
  writeLines(c("#!/usr/bin/env bash", "exit 0"), path)
  Sys.chmod(path, "0755")
  path
}

backup_launchd_fixture <- function() {
  root <- tempfile("backup-launchd-")
  dir.create(root, recursive = TRUE)
  root <- normalizePath(root, mustWork = TRUE)
  fake_bin <- file.path(root, "bin")
  install_root <- file.path(root, "Library", "Application Support", "cycling-platform", "backup")
  config_dir <- file.path(install_root, "config")
  legacy_dir <- file.path(root, "legacy")
  dir.create(fake_bin)
  dir.create(config_dir, recursive = TRUE)
  dir.create(legacy_dir)
  write_fake_macos_command(fake_bin, "launchctl")
  write_fake_macos_command(fake_bin, "plutil")
  config <- file.path(config_dir, "backup.env")
  writeLines(c(
    "MARIADB_HOST=fixture-host",
    "MARIADB_PORT=3306",
    "MARIADB_USER=fixture-user",
    "MARIADB_PASSWORD=fixture-secret",
    "NTFY_TOPIC=fixture-topic"
  ), config)
  Sys.chmod(config, "0600")

  list(
    root = root,
    install_root = install_root,
    runtime = file.path(install_root, "runtime"),
    config_dir = config_dir,
    config = config,
    data = file.path(install_root, "data"),
    logs = file.path(root, "Library", "Logs", "cycling-platform"),
    agents = file.path(root, "LaunchAgents"),
    legacy = legacy_dir,
    path = paste(fake_bin, Sys.getenv("PATH"), sep = .Platform$path.sep)
  )
}

backup_launchd_env <- function(fixture, extra = character()) {
  setting <- function(name, value) {
    paste0(name, "=", shQuote(value))
  }

  c(
    setting("PATH", fixture$path),
    setting("HOME", fixture$root),
    setting("BACKUP_INSTALL_ROOT", fixture$install_root),
    setting("BACKUP_CONFIG_DIR", fixture$config_dir),
    setting("BACKUP_CONFIG_FILE", fixture$config),
    setting("BACKUP_DATA_DIR", fixture$data),
    setting("BACKUP_LOG_DIR", fixture$logs),
    setting("BACKUP_LAUNCHD_AGENT_DIR", fixture$agents),
    setting("BACKUP_LEGACY_DATA_DIR", fixture$legacy),
    "BACKUP_SKIP_CRON_MIGRATION=1",
    extra
  )
}

run_backup_launchd_installer <- function(fixture, mode, extra = character()) {
  suppressWarnings(
    system2(
      "bash",
      c(backup_launchd_installer, mode),
      env = backup_launchd_env(fixture, extra),
      stdout = TRUE,
      stderr = TRUE
    )
  )
}

write_direct_runtime_health_artifact <- function(fixture) {
  databases <- c(
    "cycling_platform_admin",
    "cycling_platform_raw",
    "cycling_platform_reference",
    "cycling_platform_silver",
    "cycling_platform_gold"
  )
  prefix <- "2026-08-14_050000"
  filenames <- paste0(prefix, "_", databases, ".sql.gz")
  dir.create(fixture$data, recursive = TRUE, showWarnings = FALSE)
  for (filename in filenames) {
    writeBin(as.raw(1L), file.path(fixture$data, filename))
  }
  jsonlite::write_json(
    list(
      status = "SUCCESS",
      started_at = "2026-08-14T04:00:00Z",
      completed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      backup_host = "fixture-mac",
      source_host = "fixture-source",
      run_prefix = prefix,
      databases = databases,
      files = data.frame(database_name = databases, filename = filenames)
    ),
    file.path(fixture$data, "latest_success.json"),
    auto_unbox = TRUE
  )
  prefix
}

direct_runtime_env <- function(fixture, extra = character()) {
  c(
    paste0("HOME=", shQuote(fixture$root)),
    paste0("PATH=", shQuote(fixture$path)),
    extra
  )
}

testthat::test_that("backup runtime renders a minimal manifest beside safe plists", {
  fixture <- backup_launchd_fixture()
  render <- file.path(fixture$root, "rendered runtime")
  output <- system2(
    "bash",
    c(backup_launchd_installer, "render", shQuote(render)),
    env = backup_launchd_env(fixture),
    stdout = TRUE,
    stderr = TRUE
  )
  testthat::expect_equal(attr(output, "status") %||% 0L, 0L)
  manifest <- jsonlite::read_json(
    file.path(render, "runtime-manifest.json"),
    simplifyVector = TRUE
  )
  testthat::expect_equal(manifest$runtime_schema_version, 1L)
  testthat::expect_true(nrow(manifest$files) >= 15L)
  testthat::expect_true(file.exists(file.path(
    render,
    "R",
    "backup",
    "bootstrap_backup_runtime.R"
  )))
  testthat::expect_false(dir.exists(file.path(render, "tests")))
  testthat::expect_false(dir.exists(file.path(render, "exploration")))
  rendered_text <- paste(unlist(lapply(
    list.files(render, full.names = TRUE, recursive = TRUE),
    readLines,
    warn = FALSE
  )), collapse = "\n")
  testthat::expect_false(grepl("/Documents/", rendered_text, fixed = TRUE))
  testthat::expect_false(grepl("STRAVA_", rendered_text, fixed = TRUE))
  testthat::expect_false(grepl("GOOGLE_HEALTH_", rendered_text, fixed = TRUE))

  backup_plist <- paste(readLines(
    file.path(render, "com.tim-jc.cycling-platform-backup.plist"),
    warn = FALSE
  ), collapse = "\n")
  health_plist <- paste(readLines(
    file.path(render, "com.tim-jc.cycling-platform-backup-health.plist"),
    warn = FALSE
  ), collapse = "\n")
  for (plist in c(backup_plist, health_plist)) {
    testthat::expect_true(grepl(fixture$runtime, plist, fixed = TRUE))
    testthat::expect_true(grepl(fixture$config, plist, fixed = TRUE))
    testthat::expect_true(grepl(fixture$data, plist, fixed = TRUE))
    testthat::expect_true(grepl(fixture$logs, plist, fixed = TRUE))
    testthat::expect_false(grepl("/Documents/", plist, fixed = TRUE))
  }
})

testthat::test_that("install is idempotent and preserves migrated backup state", {
  fixture <- backup_launchd_fixture()
  writeLines("fixture", file.path(fixture$legacy, "latest_success.json"))
  writeBin(as.raw(1:3), file.path(
    fixture$legacy,
    "2026-08-14_050000_cycling_platform_admin.sql.gz"
  ))

  first <- run_backup_launchd_installer(fixture, "install")
  second <- run_backup_launchd_installer(fixture, "install")

  testthat::expect_equal(attr(first, "status") %||% 0L, 0L)
  testthat::expect_equal(attr(second, "status") %||% 0L, 0L)
  testthat::expect_true(file.exists(file.path(fixture$data, "latest_success.json")))
  testthat::expect_true(file.exists(file.path(
    fixture$data,
    "2026-08-14_050000_cycling_platform_admin.sql.gz"
  )))
  testthat::expect_equal(
    as.integer(file.info(fixture$config)$mode) %% 512L,
    strtoi("600", base = 8L)
  )
})

testthat::test_that("direct runtime resolves canonical paths without plist environment", {
  fixture <- backup_launchd_fixture()
  run_backup_launchd_installer(fixture, "install")

  result <- system2(
    file.path(fixture$runtime, "scripts", "run_backup_workflow.sh"),
    "paths",
    env = direct_runtime_env(fixture),
    stdout = TRUE
  )

  testthat::expect_true(any(grepl(
    paste0("config\t", fixture$config),
    result,
    fixed = TRUE
  )))
  testthat::expect_true(any(grepl(
    paste0("data\t", fixture$data),
    result,
    fixed = TRUE
  )))
  testthat::expect_true(any(grepl(
    paste0("logs\t", fixture$logs),
    result,
    fixed = TRUE
  )))
})

testthat::test_that("direct health and mocked backup use canonical config and data", {
  fixture <- backup_launchd_fixture()
  run_backup_launchd_installer(fixture, "install")
  prefix <- write_direct_runtime_health_artifact(fixture)
  workflow <- file.path(fixture$runtime, "scripts", "run_backup_workflow.sh")

  health <- system2(
    workflow,
    "health",
    env = direct_runtime_env(fixture),
    stdout = TRUE,
    stderr = TRUE
  )
  testthat::expect_equal(attr(health, "status") %||% 0L, 0L)

  mock_backup <- file.path(fixture$root, "mock-backup.sh")
  writeLines(c(
    "#!/usr/bin/env bash",
    '[[ "$MARIADB_HOST" == "fixture-host" ]] || exit 31',
    paste0('[[ "$BACKUP_DIR" == "', fixture$data, '" ]] || exit 32'),
    paste0("printf '%s\\n' '", prefix, "' > \"$BACKUP_PHYSICAL_SUCCESS_MARKER\""),
    "exit 0"
  ), mock_backup)
  Sys.chmod(mock_backup, "0755")

  backup <- system2(
    workflow,
    "backup",
    env = direct_runtime_env(
      fixture,
      paste0("BACKUP_COMMAND=", shQuote(mock_backup))
    ),
    stdout = TRUE,
    stderr = TRUE
  )
  testthat::expect_equal(attr(backup, "status") %||% 0L, 0L)
  testthat::expect_false(dir.exists(file.path(fixture$runtime, "backups")))
  testthat::expect_false(file.exists(file.path(fixture$runtime, "backup.env")))
})

testthat::test_that("direct backup reports its missing canonical config", {
  fixture <- backup_launchd_fixture()
  run_backup_launchd_installer(fixture, "install")
  unlink(fixture$config)

  result <- suppressWarnings(system2(
    file.path(fixture$runtime, "scripts", "run_backup_workflow.sh"),
    "backup",
    env = direct_runtime_env(fixture),
    stdout = TRUE,
    stderr = TRUE
  ))

  testthat::expect_true((attr(result, "status") %||% 0L) != 0L)
  testthat::expect_true(any(grepl(
    "Backup configuration not found:",
    result,
    fixed = TRUE
  )))
  testthat::expect_true(any(grepl(fixture$config, result, fixed = TRUE)))
})

testthat::test_that("verify detects runtime drift", {
  fixture <- backup_launchd_fixture()
  run_backup_launchd_installer(fixture, "install")
  write("# drift", file.path(fixture$runtime, "scripts", "run_backup_workflow.sh"), append = TRUE)

  result <- run_backup_launchd_installer(fixture, "verify")

  testthat::expect_true((attr(result, "status") %||% 0L) != 0L)
  testthat::expect_true(any(grepl("drift detected", result, ignore.case = TRUE)))
})

testthat::test_that("failed update leaves the active runtime untouched", {
  fixture <- backup_launchd_fixture()
  run_backup_launchd_installer(fixture, "install")
  marker <- file.path(fixture$runtime, "active-marker")
  writeLines("active", marker)

  failed <- run_backup_launchd_installer(
    fixture,
    "install",
    "BACKUP_INSTALL_FAIL_AFTER_RENDER=1"
  )

  testthat::expect_true((attr(failed, "status") %||% 0L) != 0L)
  testthat::expect_true(file.exists(marker))
})

testthat::test_that("uninstall preserves config data and logs", {
  fixture <- backup_launchd_fixture()
  run_backup_launchd_installer(fixture, "install")
  writeLines("archive", file.path(fixture$data, "keep.sql.gz"))
  writeLines("log", file.path(fixture$logs, "keep.log"))

  result <- run_backup_launchd_installer(fixture, "uninstall")

  testthat::expect_equal(attr(result, "status") %||% 0L, 0L)
  testthat::expect_false(dir.exists(fixture$runtime))
  testthat::expect_true(file.exists(fixture$config))
  testthat::expect_true(file.exists(file.path(fixture$data, "keep.sql.gz")))
  testthat::expect_true(file.exists(file.path(fixture$logs, "keep.log")))
})

testthat::test_that("status does not reveal backup secrets", {
  fixture <- backup_launchd_fixture()
  run_backup_launchd_installer(fixture, "install")

  result <- run_backup_launchd_installer(fixture, "status")

  testthat::expect_false(any(grepl("fixture-secret", result, fixed = TRUE)))
  testthat::expect_false(any(grepl("fixture-topic", result, fixed = TRUE)))
})

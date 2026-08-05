find_migration_project_root <- function() {
  candidates <- c(".", "../..")
  candidate <- candidates[
    file.exists(file.path(candidates, "bootstrap.R"))
  ][1]

  normalizePath(candidate, mustWork = TRUE)
}

source(file.path(
  find_migration_project_root(),
  "R",
  "database",
  "run_schema_migrations.R"
))
source(file.path(
  find_migration_project_root(),
  "R",
  "database",
  "bootstrap_platform_schema.R"
))

write_test_migration <- function(directory, filename, sql = "SELECT 1;") {
  writeLines(sql, file.path(directory, filename))
}

testthat::test_that("migration discovery is deterministic and checksummed", {
  migration_dir <- tempfile("migrations-")
  dir.create(migration_dir)

  write_test_migration(migration_dir, "010_tenth.sql", "SELECT 10;")
  write_test_migration(migration_dir, "002_second.sql", "SELECT 2;")
  write_test_migration(migration_dir, "001_first.sql", "SELECT 1;")

  manifest <- discover_schema_migrations(migration_dir)

  testthat::expect_equal(
    manifest$migration_version,
    c("001", "002", "010")
  )
  testthat::expect_true(all(nchar(manifest$migration_checksum) == 64L))
})

testthat::test_that("migration 001 retains its rehearsed immutable checksum", {
  project_root <- find_migration_project_root()
  manifest <- discover_schema_migrations(
    file.path(project_root, "sql", "migrations")
  )
  migration_001 <- manifest[
    manifest$migration_version == "001",
    ,
    drop = FALSE
  ]

  testthat::expect_equal(nrow(migration_001), 1L)
  testthat::expect_identical(
    migration_001$migration_filename[[1]],
    "001_enforce_canonical_collation.sql"
  )
  testthat::expect_identical(
    migration_001$migration_checksum[[1]],
    "d21cd9713ed4a9736626f41575d10fa762945a58400b40de80f36b4a5fe55224"
  )
})

testthat::test_that("migration 006 removes only the obsolete Silver staging table", {
  project_root <- find_migration_project_root()
  migration_file <- file.path(
    project_root,
    "sql",
    "migrations",
    "006_drop_obsolete_silver_activity_streams_staging.sql"
  )
  migration_lines <- readLines(migration_file)
  migration_sql <- paste(migration_lines, collapse = "\n")

  testthat::expect_match(
    migration_sql,
    "DROP TABLE IF EXISTS cycling_platform_silver.activity_streams_staging",
    fixed = TRUE
  )
  executable_sql <- paste(
    migration_lines[!grepl("^\\s*--", migration_lines)],
    collapse = "\n"
  )
  testthat::expect_false(grepl(
    "cycling_platform_stage.activity_streams_build",
    executable_sql,
    fixed = TRUE
  ))
})

testthat::test_that("duplicate migration versions fail before execution", {
  migration_dir <- tempfile("migrations-")
  dir.create(migration_dir)

  write_test_migration(migration_dir, "001_first.sql")
  write_test_migration(migration_dir, "001_duplicate.sql")

  executed <- character()

  testthat::expect_error(
    run_schema_migrations(
      connection = NULL,
      migration_dir = migration_dir,
      ledger_sql_file = "ledger.sql",
      execute_sql = function(sql_file, connection) {
        executed <<- c(executed, sql_file)
      },
      query_database = function(...) data.frame(),
      execute_database = function(...) 1L
    ),
    "Duplicate schema migration version"
  )

  testthat::expect_length(executed, 0L)
})

testthat::test_that("invalid migration filenames fail clearly", {
  migration_dir <- tempfile("migrations-")
  dir.create(migration_dir)
  write_test_migration(migration_dir, "1_not_fixed_width.sql")

  testthat::expect_error(
    discover_schema_migrations(migration_dir),
    "Expected NNN_description.sql"
  )
})

testthat::test_that("applied migrations require filename and checksum match", {
  migration_dir <- tempfile("migrations-")
  dir.create(migration_dir)
  write_test_migration(migration_dir, "001_first.sql")
  manifest <- discover_schema_migrations(migration_dir)

  run_with_ledger <- function(filename, checksum) {
    run_schema_migrations(
      connection = NULL,
      migration_dir = migration_dir,
      ledger_sql_file = "ledger.sql",
      execute_sql = function(...) invisible(NULL),
      query_database = function(...) {
        data.frame(
          migration_filename = filename,
          migration_checksum = checksum
        )
      },
      execute_database = function(...) 1L
    )
  }

  testthat::expect_error(
    run_with_ledger(
      "001_renamed.sql",
      manifest$migration_checksum[[1]]
    ),
    "immutable ledger record"
  )
  testthat::expect_error(
    run_with_ledger(
      manifest$migration_filename[[1]],
      paste0(rep("0", 64L), collapse = "")
    ),
    "immutable ledger record"
  )
})

testthat::test_that("an applied migration is not reapplied", {
  migration_dir <- tempfile("migrations-")
  dir.create(migration_dir)
  write_test_migration(migration_dir, "001_first.sql")
  manifest <- discover_schema_migrations(migration_dir)
  executed <- character()

  applied <- run_schema_migrations(
    connection = NULL,
    migration_dir = migration_dir,
    ledger_sql_file = "ledger.sql",
    execute_sql = function(sql_file, connection) {
      executed <<- c(executed, sql_file)
    },
    query_database = function(...) {
      manifest[c("migration_filename", "migration_checksum")]
    },
    execute_database = function(...) {
      testthat::fail("Ledger insert should not occur")
    }
  )

  testthat::expect_length(applied, 0L)
  testthat::expect_equal(executed, "ledger.sql")
})

testthat::test_that("failed migration SQL is never recorded", {
  migration_dir <- tempfile("migrations-")
  dir.create(migration_dir)
  write_test_migration(migration_dir, "001_first.sql")
  ledger_inserts <- 0L

  testthat::expect_error(
    run_schema_migrations(
      connection = NULL,
      migration_dir = migration_dir,
      ledger_sql_file = "ledger.sql",
      execute_sql = function(sql_file, connection) {
        if (grepl("001_first", sql_file, fixed = TRUE)) {
          stop("simulated DDL failure")
        }
      },
      query_database = function(...) data.frame(),
      execute_database = function(...) {
        ledger_inserts <<- ledger_inserts + 1L
      }
    ),
    "simulated DDL failure"
  )

  testthat::expect_equal(ledger_inserts, 0L)
})

testthat::test_that("all ledger checks complete before migration SQL", {
  migration_dir <- tempfile("migrations-")
  dir.create(migration_dir)
  write_test_migration(migration_dir, "001_first.sql", "SELECT 1;")
  write_test_migration(migration_dir, "002_second.sql", "SELECT 2;")
  manifest <- discover_schema_migrations(migration_dir)
  executed <- character()

  query_database <- function(connection, statement, params) {
    version <- params[[1]]

    if (identical(version, "001")) {
      return(data.frame())
    }

    data.frame(
      migration_filename = manifest$migration_filename[2],
      migration_checksum = paste0(rep("0", 64L), collapse = "")
    )
  }

  testthat::expect_error(
    run_schema_migrations(
      connection = NULL,
      migration_dir = migration_dir,
      ledger_sql_file = "ledger.sql",
      execute_sql = function(sql_file, connection) {
        executed <<- c(executed, sql_file)
      },
      query_database = query_database,
      execute_database = function(...) 1L
    ),
    "immutable ledger record"
  )

  testthat::expect_equal(executed, "ledger.sql")
})

testthat::test_that("bootstrap file ordering and reruns are deterministic", {
  project_root <- find_migration_project_root()
  first <- list_platform_bootstrap_sql_files(project_root)
  second <- list_platform_bootstrap_sql_files(project_root)

  testthat::expect_identical(first, second)
  testthat::expect_false(any(grepl("sql/install/", first, fixed = TRUE)))
  derived_files <- first[
    grepl("/sql/(reference|silver|gold)/", first)
  ]
  testthat::expect_true(
    all(grepl("^[0-9]+_create_", basename(derived_files)))
  )

  executed_runs <- list()
  migration_runs <- 0L

  execute_sql <- function(sql_file, connection) {
    executed_runs[[length(executed_runs) + 1L]] <<- sql_file
  }
  migrate <- function(...) {
    migration_runs <<- migration_runs + 1L
    character()
  }

  bootstrap_platform_schema(
    connection = NULL,
    project_root = project_root,
    execute_sql = execute_sql,
    migrate = migrate,
    database_access_findings = function(...) data.frame()
  )
  first_run <- unlist(executed_runs, use.names = FALSE)
  executed_runs <- list()
  bootstrap_platform_schema(
    connection = NULL,
    project_root = project_root,
    execute_sql = execute_sql,
    migrate = migrate,
    database_access_findings = function(...) data.frame()
  )
  second_run <- unlist(executed_runs, use.names = FALSE)

  testthat::expect_identical(first_run, second_run)
  testthat::expect_identical(migration_runs, 2L)
})

testthat::test_that("bootstrap stops before object DDL when infrastructure is not ready", {
  executed <- character()
  migrations_run <- 0L
  findings <- data.frame(
    database_name = "cycling_platform_reference",
    issue = "missing_database",
    error = "Unknown database 'cycling_platform_reference'"
  )

  testthat::expect_error(
    bootstrap_platform_schema(
      connection = NULL,
      project_root = find_migration_project_root(),
      execute_sql = function(sql_file, connection) {
        executed <<- c(executed, sql_file)
      },
      migrate = function(...) {
        migrations_run <<- migrations_run + 1L
      },
      database_access_findings = function(...) findings
    ),
    "cycling-infrastructure must create all required databases"
  )

  testthat::expect_length(executed, 0L)
  testthat::expect_identical(migrations_run, 0L)
})

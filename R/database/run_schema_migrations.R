#' Discover Versioned Platform Schema Migrations
#'
#' Migration filenames use a fixed-width numeric version so lexical and numeric
#' ordering are identical. Duplicate versions are rejected before any migration
#' SQL is executed.
#'
#' @param migration_dir Directory containing ordered SQL migrations.
#'
#' @return Data frame describing migrations in execution order.
discover_schema_migrations <- function(migration_dir) {
  if (!dir.exists(migration_dir)) {
    return(data.frame(
      migration_version = character(),
      migration_filename = character(),
      migration_file = character(),
      migration_checksum = character()
    ))
  }

  sql_files <- list.files(
    migration_dir,
    pattern = "[.]sql$",
    full.names = TRUE
  )

  if (length(sql_files) == 0L) {
    return(data.frame(
      migration_version = character(),
      migration_filename = character(),
      migration_file = character(),
      migration_checksum = character()
    ))
  }

  migration_filenames <- basename(sql_files)
  valid_filename <- grepl(
    "^[0-9]{3}_[A-Za-z0-9_-]+[.]sql$",
    migration_filenames
  )

  if (any(!valid_filename)) {
    stop(
      "Invalid schema migration filename(s): ",
      paste(migration_filenames[!valid_filename], collapse = ", "),
      ". Expected NNN_description.sql.",
      call. = FALSE
    )
  }

  migration_versions <- sub("_.*$", "", migration_filenames)
  duplicate_versions <- unique(
    migration_versions[duplicated(migration_versions)]
  )

  if (length(duplicate_versions) > 0L) {
    stop(
      "Duplicate schema migration version(s): ",
      paste(duplicate_versions, collapse = ", "),
      ". Each version must identify exactly one file.",
      call. = FALSE
    )
  }

  execution_order <- order(migration_versions, migration_filenames)
  sql_files <- sql_files[execution_order]
  migration_filenames <- migration_filenames[execution_order]
  migration_versions <- migration_versions[execution_order]

  data.frame(
    migration_version = migration_versions,
    migration_filename = migration_filenames,
    migration_file = sql_files,
    migration_checksum = vapply(
      sql_files,
      function(migration_file) {
        digest::digest(
          readr::read_file(migration_file),
          algo = "sha256",
          serialize = FALSE
        )
      },
      character(1)
    ),
    stringsAsFactors = FALSE
  )
}

#' Run Versioned Platform Schema Migrations
#'
#' Apply each immutable SQL migration once and record its checksum.
#' MariaDB DDL auto-commits, so a failed migration is deliberately left
#' unrecorded and is safe to retry after the cause is corrected.
#'
#' @param connection DBI connection with access to all platform databases.
#' @param migration_dir Directory containing ordered SQL migrations.
#' @param ledger_sql_file Idempotent migration-ledger DDL file.
#' @param execute_sql SQL-file executor, injectable for tests.
#' @param query_database Database-query function, injectable for tests.
#' @param execute_database Database-statement function, injectable for tests.
#'
#' @return Invisibly returns applied migration versions.
run_schema_migrations <- function(
  connection,
  migration_dir = file.path("sql", "migrations"),
  ledger_sql_file = file.path(
    "sql",
    "admin",
    "005_create_schema_migration.sql"
  ),
  execute_sql = execute_sql_file,
  query_database = DBI::dbGetQuery,
  execute_database = DBI::dbExecute
) {
  migrations <- discover_schema_migrations(migration_dir)

  execute_sql(
    ledger_sql_file,
    connection
  )

  if (nrow(migrations) == 0L) {
    message("Schema migrations: no migration files found.")
    return(invisible(character()))
  }

  already_applied <- logical(nrow(migrations))

  for (migration_index in seq_len(nrow(migrations))) {
    migration <- migrations[migration_index, , drop = FALSE]

    existing <- query_database(
      connection,
      "
        SELECT
          migration_filename,
          migration_checksum
        FROM cycling_platform_admin.schema_migration
        WHERE migration_version = ?
      ",
      params = list(migration$migration_version[[1]])
    )

    if (nrow(existing) > 1L) {
      stop(
        "Migration ledger contains duplicate version ",
        migration$migration_version[[1]],
        ". Repair the ledger before bootstrap.",
        call. = FALSE
      )
    }

    if (nrow(existing) == 1L) {
      filename_matches <- identical(
        as.character(existing$migration_filename[[1]]),
        migration$migration_filename[[1]]
      )
      checksum_matches <- identical(
        as.character(existing$migration_checksum[[1]]),
        migration$migration_checksum[[1]]
      )

      if (!filename_matches || !checksum_matches) {
        stop(
          "Applied schema migration ",
          migration$migration_version[[1]],
          " does not match its immutable ledger record. Expected file/checksum ",
          existing$migration_filename[[1]],
          "/",
          existing$migration_checksum[[1]],
          "; found ",
          migration$migration_filename[[1]],
          "/",
          migration$migration_checksum[[1]],
          ". Restore the applied file or create a new migration.",
          call. = FALSE
        )
      }

      already_applied[[migration_index]] <- TRUE
    }
  }

  applied_now <- character()

  for (migration_index in seq_len(nrow(migrations))) {
    if (already_applied[[migration_index]]) {
      message(
        "Schema migration already applied: ",
        migrations$migration_filename[[migration_index]]
      )
      next
    }

    migration <- migrations[migration_index, , drop = FALSE]

    message(
      "Applying schema migration: ",
      migration$migration_filename[[1]],
      " (sha256 ",
      migration$migration_checksum[[1]],
      ")"
    )
    execute_sql(migration$migration_file[[1]], connection)

    execute_database(
      connection,
      "
        INSERT INTO cycling_platform_admin.schema_migration (
          migration_version,
          migration_filename,
          migration_checksum
        )
        VALUES (?, ?, ?)
      ",
      params = list(
        migration$migration_version[[1]],
        migration$migration_filename[[1]],
        migration$migration_checksum[[1]]
      )
    )

    applied_now <- c(
      applied_now,
      migration$migration_version[[1]]
    )
  }

  message(
    "Schema migrations complete: ",
    length(applied_now),
    " applied, ",
    sum(already_applied),
    " already current."
  )

  invisible(applied_now)
}

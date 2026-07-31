#' Run Versioned Platform Schema Migrations
#'
#' Apply each immutable SQL migration once and record its checksum.
#' MariaDB DDL auto-commits, so a failed migration is deliberately left
#' unrecorded and is safe to retry after the cause is corrected.
#'
#' @param connection DBI connection with access to all platform databases.
#' @param migration_dir Directory containing ordered SQL migrations.
#'
#' @return Invisibly returns applied migration versions.
run_schema_migrations <- function(
  connection,
  migration_dir = file.path("sql", "migrations")
) {
  execute_sql_file(
    file.path("sql", "admin", "005_create_schema_migration.sql"),
    connection
  )

  if (!dir.exists(migration_dir)) {
    return(invisible(character()))
  }

  migration_files <- list.files(
    migration_dir,
    pattern = "^[0-9]+_[A-Za-z0-9_-]+[.]sql$",
    full.names = TRUE
  ) |>
    sort()

  applied_now <- character()

  for (migration_file in migration_files) {
    migration_filename <- basename(migration_file)
    migration_version <- sub("_.*$", "", migration_filename)
    migration_checksum <- digest::digest(
      readr::read_file(migration_file),
      algo = "sha256",
      serialize = FALSE
    )

    existing <- DBI::dbGetQuery(
      connection,
      "
        SELECT migration_checksum
        FROM cycling_platform_admin.schema_migration
        WHERE migration_version = ?
      ",
      params = list(migration_version)
    )

    if (nrow(existing) == 1L) {
      if (!identical(existing$migration_checksum[[1]], migration_checksum)) {
        stop(
          "Applied schema migration ",
          migration_version,
          " has been modified: ",
          migration_filename,
          ". Create a new migration instead.",
          call. = FALSE
        )
      }

      next
    }

    message("Applying schema migration: ", migration_filename)
    execute_sql_file(migration_file, connection)

    DBI::dbExecute(
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
        migration_version,
        migration_filename,
        migration_checksum
      )
    )

    applied_now <- c(applied_now, migration_version)
  }

  invisible(applied_now)
}

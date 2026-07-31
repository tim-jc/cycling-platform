#' List Platform Bootstrap SQL Files
#'
#' Return persistent object-creation scripts in deterministic layer and
#' filename order. Transformation SQL is intentionally excluded.
#'
#' @param project_root Repository root.
#'
#' @return Character vector of SQL file paths.
list_platform_bootstrap_sql_files <- function(project_root = ".") {
  list_sql_files <- function(directory, pattern = "[.]sql$") {
    path <- file.path(project_root, "sql", directory)

    if (!dir.exists(path)) {
      return(character())
    }

    sort(
      list.files(
        path = path,
        pattern = pattern,
        full.names = TRUE
      )
    )
  }

  unlist(
    list(
      list_sql_files("install"),
      list_sql_files("admin"),
      list_sql_files("stage"),
      list_sql_files("raw"),
      list_sql_files("silver", "^[0-9]+_create_.*[.]sql$"),
      list_sql_files("gold", "^[0-9]+_create_.*[.]sql$")
    ),
    use.names = FALSE
  )
}

#' Bootstrap the Platform Schema
#'
#' Idempotently create platform objects, then validate and apply versioned
#' migrations.
#'
#' @param connection DBI connection.
#' @param project_root Repository root.
#' @param execute_sql SQL-file executor, injectable for tests.
#' @param migrate Migration runner, injectable for tests.
#'
#' @return Invisibly returns created-file and applied-migration details.
bootstrap_platform_schema <- function(
  connection,
  project_root = ".",
  execute_sql = execute_sql_file,
  migrate = run_schema_migrations
) {
  sql_files <- list_platform_bootstrap_sql_files(project_root)

  message(
    "Platform bootstrap: ensuring ",
    length(sql_files),
    " schema-definition files."
  )

  for (sql_file in sql_files) {
    execute_sql(sql_file, connection)
  }

  applied_migrations <- migrate(
    connection = connection,
    migration_dir = file.path(project_root, "sql", "migrations"),
    ledger_sql_file = file.path(
      project_root,
      "sql",
      "admin",
      "005_create_schema_migration.sql"
    )
  )

  message(
    "Platform bootstrap complete: schema definitions current; ",
    length(applied_migrations),
    " migration(s) applied."
  )

  invisible(list(
    sql_files = sql_files,
    applied_migrations = applied_migrations
  ))
}

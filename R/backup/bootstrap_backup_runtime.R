# Minimal bootstrap for the installed macOS backup runtime.
# The caller must run from the runtime root.

required_files <- c(
  file.path("R", "config", "platform_database_inventory.R"),
  file.path("R", "database", "get_connection.R"),
  file.path("R", "database", "execute_sql_file.R"),
  file.path("R", "utils", "backup_observability.R")
)

missing_files <- required_files[!file.exists(required_files)]

if (length(missing_files) > 0L) {
  stop(
    "Backup runtime is incomplete. Missing: ",
    paste(missing_files, collapse = ", "),
    call. = FALSE
  )
}

invisible(lapply(required_files, source, local = .GlobalEnv))

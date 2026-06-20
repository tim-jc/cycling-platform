# bootstrap_platform.R
source("bootstrap.R")

connection <- get_connection("mysql")

tryCatch(
  {
    sql_directories <- c(
      "install",
      "admin",
      "raw",
      "silver",
      "gold"
    )

    sql_files <- purrr::map(
      sql_directories,
      \(directory) {
        list.files(
          path = file.path("sql", directory),
          pattern = "\\.sql$",
          full.names = TRUE
        ) |>
          sort()
      }
    ) |>
      unlist(use.names = FALSE)

    purrr::walk(
      sql_files,
      execute_sql_file,
      connection = connection
    )

    message("Platform bootstrap complete.")
  },

  finally = {
    if (DBI::dbIsValid(connection)) {
      DBI::dbDisconnect(connection)
    }
  }
)

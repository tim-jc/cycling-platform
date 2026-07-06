# bootstrap_platform.R
source("bootstrap.R")

connection <- get_connection("mysql")

tryCatch(
  {
    list_sql_files <- function(directory, pattern = "\\.sql$") {
      path <- file.path("sql", directory)

      if (!dir.exists(path)) {
        return(character())
      }

      list.files(
        path = path,
        pattern = pattern,
        full.names = TRUE
      ) |>
        sort()
    }

    sql_files <- list(
      list_sql_files("install"),
      list_sql_files("admin"),
      list_sql_files("stage"),
      list_sql_files("raw"),
      list_sql_files("silver", "^[0-9]+_create_.*\\.sql$"),
      list_sql_files("gold", "^[0-9]+_create_.*\\.sql$")
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

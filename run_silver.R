# run_silver.R
source("bootstrap.R")

connection <- get_connection("mysql")

tryCatch(
  {
    run_silver_transformations(
      connection = connection
    )

    message("Silver transformations complete.")
  },

  finally = {
    if (DBI::dbIsValid(connection)) {
      DBI::dbDisconnect(connection)
    }
  }
)

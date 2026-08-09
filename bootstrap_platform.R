# bootstrap_platform.R
source("bootstrap.R")

message("Platform bootstrap starting.")

connection <- get_connection("cycling_platform_admin")

tryCatch(
  {
    bootstrap_platform_schema(connection)
  },

  finally = {
    connection_is_valid <- tryCatch(
      DBI::dbIsValid(connection),
      error = function(e) FALSE
    )

    if (isTRUE(connection_is_valid)) {
      DBI::dbDisconnect(connection)
    }
  }
)

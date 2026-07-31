#' Load MariaDB Connection Configuration
#'
#' Validate presence and basic shape without logging secret values.
#'
#' @param environment Named environment-variable vector.
#'
#' @return Validated connection configuration.
load_mariadb_connection_config <- function(environment = Sys.getenv()) {
  required_keys <- c(
    "MARIADB_HOST",
    "MARIADB_PORT",
    "MARIADB_USER",
    "MARIADB_PASSWORD"
  )
  values <- environment[required_keys]
  values[is.na(values)] <- ""
  missing_keys <- required_keys[!nzchar(trimws(values))]

  if (length(missing_keys) > 0L) {
    stop(
      "MariaDB configuration is incomplete. Missing runtime credential(s): ",
      paste(missing_keys, collapse = ", "),
      ". Check the active .Renviron or container secret mount.",
      call. = FALSE
    )
  }

  port <- suppressWarnings(as.integer(values[["MARIADB_PORT"]]))

  if (is.na(port) || port < 1L || port > 65535L) {
    stop(
      "MariaDB configuration is invalid: MARIADB_PORT must be an integer ",
      "between 1 and 65535.",
      call. = FALSE
    )
  }

  list(
    host = trimws(values[["MARIADB_HOST"]]),
    port = port,
    user = trimws(values[["MARIADB_USER"]]),
    password = values[["MARIADB_PASSWORD"]]
  )
}

#' Get Connection
#'
#' Establish a connection to MariaDB.
#'
#' @param database_name Name of database to connect to. Defaults to the
#'   platform Admin schema for control-plane and cross-schema operations.
#'
#' @return DBIConnection
get_connection <- function(
  database_name = "cycling_platform_admin"
) {
  if (
    length(database_name) != 1L ||
      is.na(database_name) ||
      !nzchar(trimws(database_name))
  ) {
    stop(
      "MariaDB connection configuration is invalid: database name is blank.",
      call. = FALSE
    )
  }

  connection_config <- load_mariadb_connection_config()

  tryCatch(
    {
      DBI::dbConnect(
        drv = RMariaDB::MariaDB(),

        host = connection_config$host,

        port = connection_config$port,

        dbname = database_name,

        user = connection_config$user,

        password = connection_config$password
      )
    },
    error = function(e) {
      stop(
        paste0(
          "MariaDB connection failed for database '",
          database_name,
          "' at ",
          connection_config$host,
          ":",
          connection_config$port,
          ". Runtime configuration was present, but the connection attempt ",
          "failed. Check host reachability, MariaDB service state, grants, ",
          "and whether the configured credentials are valid. ",
          "Original error: ",
          conditionMessage(e)
        ),
        call. = FALSE
      )
    }
  )
}

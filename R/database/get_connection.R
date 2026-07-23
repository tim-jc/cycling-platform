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
  host <- Sys.getenv("MARIADB_HOST")

  port <- Sys.getenv("MARIADB_PORT")

  user <- Sys.getenv("MARIADB_USER")

  if (!nzchar(host)) {
    stop(
      "MariaDB connection failed: MARIADB_HOST is not set.",
      call. = FALSE
    )
  }

  if (!nzchar(port)) {
    stop(
      "MariaDB connection failed: MARIADB_PORT is not set.",
      call. = FALSE
    )
  }

  if (!nzchar(user)) {
    stop(
      "MariaDB connection failed: MARIADB_USER is not set.",
      call. = FALSE
    )
  }

  tryCatch(
    {
      DBI::dbConnect(
        drv = RMariaDB::MariaDB(),

        host = host,

        port = as.integer(
          port
        ),

        dbname = database_name,

        user = user,

        password = Sys.getenv("MARIADB_PASSWORD")
      )
    },
    error = function(e) {
      stop(
        paste0(
          "MariaDB connection failed for database '",
          database_name,
          "' at ",
          host,
          ":",
          port,
          ". Check that the Raspberry Pi is reachable from this network, ",
          "MariaDB is running, port 3306 is open, and credentials are current. ",
          "Original error: ",
          conditionMessage(e)
        ),
        call. = FALSE
      )
    }
  )
}

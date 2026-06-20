#' Get Connection
#'
#' Establish a connection to MariaDB.
#'
#' @param database_name Name of database to connect to.
#'
#' @return DBIConnection
get_connection <- function(database_name) {
  DBI::dbConnect(
    drv = RMariaDB::MariaDB(),

    host = Sys.getenv("MARIADB_HOST"),

    port = as.integer(
      Sys.getenv("MARIADB_PORT")
    ),

    dbname = database_name,

    user = Sys.getenv("MARIADB_USER"),

    password = Sys.getenv("MARIADB_PASSWORD")
  )
}

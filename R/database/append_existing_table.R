#' Append Rows Without Implicit Schema Creation
#'
#' DBI implementations may create a missing table during dbWriteTable().
#' Platform loaders must only append to explicitly bootstrapped tables so no
#' persistent object can inherit a server default engine or collation.
#'
#' @param conn DBI connection.
#' @param name DBI table identifier.
#' @param value Rows to append.
#' @param append Must remain TRUE.
#' @param overwrite Must remain FALSE.
#' @param table_exists Table-existence function, injectable for tests.
#' @param write_table Table-write function, injectable for tests.
#' @param ... Additional dbWriteTable arguments.
#'
#' @return Result from DBI::dbWriteTable().
append_existing_table <- function(
  conn,
  name,
  value,
  append = TRUE,
  overwrite = FALSE,
  table_exists = DBI::dbExistsTable,
  write_table = DBI::dbWriteTable,
  ...
) {
  if (!isTRUE(append) || isTRUE(overwrite)) {
    stop(
      "append_existing_table() only supports append=TRUE and overwrite=FALSE.",
      call. = FALSE
    )
  }

  if (!table_exists(conn, name)) {
    stop(
      "Refusing to create a missing persistent table through dbWriteTable(). ",
      "Run bootstrap_platform.R and verify migrations first.",
      call. = FALSE
    )
  }

  write_table(
    conn = conn,
    name = name,
    value = value,
    append = TRUE,
    overwrite = FALSE,
    ...
  )
}

acquire_platform_run_lock <- function(connection, owner, timeout_seconds = 0L) {
  owner_lock <- paste0("cycling-platform-", gsub("[^a-z0-9]+", "-", tolower(owner)), "-run")
  result <- DBI::dbGetQuery(
    connection,
    "SELECT GET_LOCK('cycling-platform-exclusive-run', ?) AS acquired",
    params = list(as.integer(timeout_seconds))
  )
  if (nrow(result) != 1L || !identical(as.integer(result$acquired[[1]]), 1L)) {
    stop("Unable to acquire platform run lock for ", owner, "; another daily, hygiene, backfill, or repair run is active.", call. = FALSE)
  }
  owner_result <- DBI::dbGetQuery(connection, "SELECT GET_LOCK(?, 0) AS acquired", params = list(owner_lock))
  if (nrow(owner_result) != 1L || !identical(as.integer(owner_result$acquired[[1]]), 1L)) {
    DBI::dbGetQuery(connection, "SELECT RELEASE_LOCK('cycling-platform-exclusive-run') AS released")
    stop("Unable to acquire mode-specific platform lock: ", owner_lock, call. = FALSE)
  }
  message("Acquired platform run lock: ", owner)
  invisible(TRUE)
}

release_platform_run_lock <- function(connection, owner) {
  if (!DBI::dbIsValid(connection)) return(invisible(FALSE))
  owner_lock <- paste0("cycling-platform-", gsub("[^a-z0-9]+", "-", tolower(owner)), "-run")
  DBI::dbGetQuery(connection, "SELECT RELEASE_LOCK(?) AS released", params = list(owner_lock))
  DBI::dbGetQuery(connection, "SELECT RELEASE_LOCK('cycling-platform-exclusive-run') AS released")
  invisible(TRUE)
}

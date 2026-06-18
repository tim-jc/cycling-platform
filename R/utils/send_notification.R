#' Send notification
#'
#' Send NTFY notification
#' @param title Title of message.
#' @param message Body of message.
#' @param tags Optional character vector of ntfy tags.
#'
#' @return invisible(NULL)
send_notification <- function(
  run_id
) {
  message(
    "ETL run completed: ",
    run_id
  )
}

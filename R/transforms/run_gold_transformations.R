#' Run Gold Transformations
#'
#' Execute production Gold transformations that are safe for daily automation.
#' Historical backfills remain explicit manual operations.
#'
#' @param connection Database connection.
#' @param config Platform configuration.
#' @param mode Gold run mode. `daily` is the normal automation mode.
#'
#' @return Invisibly returns NULL.
run_gold_transformations <- function(
  connection,
  config = list(),
  mode = c(
    "daily",
    "repair"
  )
) {
  mode <- match.arg(mode)

  rebuild_gold_activity_best_efforts(
    connection = connection,
    config = config,
    mode = mode
  )

  rebuild_gold_activity_achievements(
    connection = connection,
    config = config,
    mode = mode
  )

  invisible(NULL)
}

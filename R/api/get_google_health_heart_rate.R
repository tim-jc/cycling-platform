#' Get Google Health Heart Rate
#'
#' Thin wrapper around Google Health data point retrieval for heart-rate.
#'
#' @param run_id Integer ETL run identifier.
#' @param source_id Integer source identifier.
#' @param start_datetime Inclusive UTC window start.
#' @param end_datetime Exclusive UTC window end.
#' @param config Platform configuration.
#'
#' @return Tibble of raw Google Health heart-rate data points.
get_google_health_heart_rate <- function(
  run_id,
  source_id,
  start_datetime,
  end_datetime,
  config
) {
  get_google_health_data_points(
    run_id = run_id,
    source_id = source_id,
    data_type = "heart-rate",
    start_datetime = start_datetime,
    end_datetime = end_datetime,
    config = config
  )
}

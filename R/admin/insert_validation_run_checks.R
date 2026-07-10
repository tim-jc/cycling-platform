#' Insert Validation Run Checks
#'
#' Persist validation check results for one validation run.
#'
#' @param connection Database connection.
#' @param validation_run_id Validation run identifier.
#' @param validation_results Tibble returned by validation functions.
#'
#' @return Invisibly returns NULL.
insert_validation_run_checks <- function(
  connection,
  validation_run_id,
  validation_results
) {
  if (nrow(validation_results) == 0) {
    return(invisible(NULL))
  }

  check_scope <- if ("check_scope" %in% names(validation_results)) {
    validation_results$check_scope
  } else {
    rep(
      NA_character_,
      nrow(validation_results)
    )
  }

  started_at <- if ("started_at" %in% names(validation_results)) {
    validation_results$started_at
  } else {
    rep(
      as.POSIXct(NA),
      nrow(validation_results)
    )
  }

  completed_at <- if ("completed_at" %in% names(validation_results)) {
    validation_results$completed_at
  } else {
    rep(
      as.POSIXct(NA),
      nrow(validation_results)
    )
  }

  elapsed_seconds <- if ("elapsed_seconds" %in% names(validation_results)) {
    validation_results$elapsed_seconds
  } else {
    rep(
      NA_real_,
      nrow(validation_results)
    )
  }

  query_text <- if ("query" %in% names(validation_results)) {
    validation_results$query
  } else {
    rep(
      NA_character_,
      nrow(validation_results)
    )
  }

  check_results <- data.frame(
    validation_run_id = rep(
      validation_run_id,
      nrow(validation_results)
    ),
    check_name = validation_results$check_name,
    check_scope = toupper(check_scope),
    severity = validation_results$severity,
    check_status = ifelse(
      validation_results$passed,
      "PASS",
      "FAIL"
    ),
    issue_count = validation_results$issue_count,
    started_at = started_at,
    completed_at = completed_at,
    elapsed_seconds = elapsed_seconds,
    query_text = query_text,
    error_message = NA_character_,
    stringsAsFactors = FALSE
  )

  DBI::dbAppendTable(
    conn = connection,
    name = DBI::Id(
      schema = "cycling_platform_admin",
      table = "validation_run_check"
    ),
    value = check_results
  )

  invisible(NULL)
}

#' Reconcile the reviewed pre-Phase-1A interrupted execution rows
#'
#' This is a one-time administrative repair for an exact, reviewed target set.
#' It deliberately does not implement general stale-run recovery.
#'
#' @param connection Admin database connection.
#' @param apply Whether to commit the reconciliation. The default is read-only.
#'
#' @return A list containing the inspected targets and, when applied, row counts.
reconcile_legacy_running_executions <- function(connection, apply = FALSE) {
  targets <- legacy_running_execution_targets()
  inspected <- read_legacy_running_execution_targets(connection, targets)

  validate_legacy_running_execution_targets(inspected, targets)

  active_count <- DBI::dbGetQuery(
    connection,
    "
      SELECT
        (SELECT COUNT(*) FROM cycling_platform_admin.pipeline_run
         WHERE run_status = 'RUNNING') +
        (SELECT COUNT(*) FROM cycling_platform_admin.etl_run
         WHERE run_status = 'RUNNING'
           AND started_at >= UTC_TIMESTAMP() - INTERVAL 6 HOUR) +
        (SELECT COUNT(*) FROM cycling_platform_admin.transform_run
         WHERE run_status = 'RUNNING'
           AND started_at >= UTC_TIMESTAMP() - INTERVAL 6 HOUR) +
        (SELECT COUNT(*) FROM cycling_platform_admin.validation_run
         WHERE run_status = 'RUNNING'
           AND started_at >= UTC_TIMESTAMP() - INTERVAL 6 HOUR) active_count
    "
  )$active_count[[1]]

  if (active_count != 0) {
    stop(
      "A current execution is active; retry the administrative reconciliation when the platform is idle.",
      call. = FALSE
    )
  }

  if (!isTRUE(apply)) {
    return(invisible(list(targets = inspected, applied = FALSE)))
  }

  explanation <- paste(
    "Legacy interrupted execution reconciled administratively.",
    "Actual termination time and duration are unknown; completed_at records",
    "the reconciliation time. A later successful execution exists."
  )

  DBI::dbBegin(connection)
  committed <- FALSE
  on.exit({
    if (!committed) {
      try(DBI::dbRollback(connection), silent = TRUE)
    }
  }, add = TRUE)

  # Re-read under the write transaction so changed preconditions cannot race
  # with the reviewed update.
  inspected_in_transaction <- read_legacy_running_execution_targets(
    connection,
    targets
  )
  validate_legacy_running_execution_targets(inspected_in_transaction, targets)

  updated <- c(
    etl_run = update_legacy_running_execution_table(
      connection, "etl_run", "run_id", targets$etl_run, explanation
    ),
    transform_run = update_legacy_running_execution_table(
      connection, "transform_run", "transform_run_id",
      targets$transform_run, explanation
    ),
    validation_run = update_legacy_running_execution_table(
      connection, "validation_run", "validation_run_id",
      targets$validation_run, explanation
    )
  )

  if (!identical(unname(updated), c(9L, 6L, 1L))) {
    stop(
      paste("Unexpected affected-row counts:", paste(names(updated), updated, collapse = ", ")),
      call. = FALSE
    )
  }

  DBI::dbCommit(connection)
  committed <- TRUE

  invisible(list(targets = inspected_in_transaction, applied = TRUE, updated = updated))
}

legacy_running_execution_targets <- function() {
  list(
    etl_run = c(17, 18, 19, 23, 24, 33, 46, 48, 49),
    transform_run = c(4, 6, 8, 40, 53, 54),
    validation_run = 27
  )
}

read_legacy_running_execution_targets <- function(connection, targets) {
  sql_ids <- function(ids) paste(as.integer(ids), collapse = ", ")

  DBI::dbGetQuery(
    connection,
    glue::glue("
      SELECT 'etl_run' execution_type, run.run_id execution_id,
             run.pipeline_run_id, run.run_status, run.started_at,
             run.completed_at, run.duration_seconds, run.error_message,
             EXISTS (
               SELECT 1 FROM cycling_platform_admin.etl_run later
               WHERE later.source_id = run.source_id
                 AND later.run_status = 'SUCCESS'
                 AND later.started_at > run.started_at
             ) later_success_exists
      FROM cycling_platform_admin.etl_run run
      WHERE run.run_id IN ({sql_ids(targets$etl_run)})
      UNION ALL
      SELECT 'transform_run', run.transform_run_id, run.pipeline_run_id,
             run.run_status, run.started_at, run.completed_at,
             run.duration_seconds, run.error_message,
             EXISTS (
               SELECT 1 FROM cycling_platform_admin.transform_run later
               WHERE later.layer_name = run.layer_name
                 AND later.entity_name = run.entity_name
                 AND later.run_status = 'SUCCESS'
                 AND later.started_at > run.started_at
             )
      FROM cycling_platform_admin.transform_run run
      WHERE run.transform_run_id IN ({sql_ids(targets$transform_run)})
      UNION ALL
      SELECT 'validation_run', run.validation_run_id, run.pipeline_run_id,
             run.run_status, run.started_at, run.completed_at,
             run.duration_seconds, run.error_message,
             EXISTS (
               SELECT 1 FROM cycling_platform_admin.validation_run later
               WHERE later.validation_scope = run.validation_scope
                 AND later.run_status = 'SUCCESS'
                 AND later.started_at > run.started_at
             )
      FROM cycling_platform_admin.validation_run run
      WHERE run.validation_run_id IN ({sql_ids(targets$validation_run)})
      ORDER BY started_at, execution_type, execution_id
    ")
  )
}

validate_legacy_running_execution_targets <- function(inspected, targets) {
  expected <- data.frame(
    execution_type = c(
      rep("etl_run", length(targets$etl_run)),
      rep("transform_run", length(targets$transform_run)),
      rep("validation_run", length(targets$validation_run))
    ),
    execution_id = c(
      targets$etl_run,
      targets$transform_run,
      targets$validation_run
    )
  )

  actual <- inspected[, c("execution_type", "execution_id"), drop = FALSE]
  actual$execution_id <- as.numeric(actual$execution_id)

  expected_key <- paste(expected$execution_type, expected$execution_id)
  actual_key <- paste(actual$execution_type, actual$execution_id)

  if (nrow(inspected) != 16L || !setequal(actual_key, expected_key)) {
    stop("The reviewed target set is not exactly the expected 16 rows.", call. = FALSE)
  }
  if (any(!is.na(inspected$pipeline_run_id))) {
    stop("A target has pipeline lineage and is not eligible for legacy reconciliation.", call. = FALSE)
  }
  if (any(inspected$run_status != "RUNNING")) {
    stop("A target is no longer RUNNING; no changes were applied.", call. = FALSE)
  }
  if (any(!is.na(inspected$completed_at))) {
    stop("A target already has completed_at; no changes were applied.", call. = FALSE)
  }
  if (any(inspected$later_success_exists != 1)) {
    stop("A target lacks a later successful execution; no changes were applied.", call. = FALSE)
  }

  invisible(TRUE)
}

update_legacy_running_execution_table <- function(
  connection,
  table_name,
  id_column,
  ids,
  explanation
) {
  allowed <- list(
    etl_run = "run_id",
    transform_run = "transform_run_id",
    validation_run = "validation_run_id"
  )
  if (!identical(allowed[[table_name]], id_column)) {
    stop("Unsupported administrative reconciliation target.", call. = FALSE)
  }

  id_sql <- paste(as.integer(ids), collapse = ", ")
  DBI::dbExecute(
    connection,
    glue::glue("
      UPDATE cycling_platform_admin.{`table_name`}
      SET run_status = 'FAILED',
          completed_at = UTC_TIMESTAMP(),
          duration_seconds = NULL,
          error_message = ?
      WHERE {`id_column`} IN ({id_sql})
        AND pipeline_run_id IS NULL
        AND run_status = 'RUNNING'
        AND completed_at IS NULL
    "),
    params = list(explanation)
  )
}

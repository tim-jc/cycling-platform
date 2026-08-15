#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) {
  stop(
    "Usage: report_backup_runtime_health.R <status_file> <stale_hours> <critical_hours>",
    call. = FALSE
  )
}

source(file.path("R", "backup", "bootstrap_backup_runtime.R"))

status_file <- args[[1]]
stale_hours <- as.numeric(args[[2]])
critical_hours <- as.numeric(args[[3]])
read_result <- read_backup_success_artifact(status_file)

physical_status <- read_result$status
age_hours <- NA_real_
run_prefix <- "none"

if (identical(read_result$status, "VALID")) {
  artifact <- read_result$artifact
  run_prefix <- artifact$run_prefix
  physical_status <- if (
    backup_success_artifact_files_available(artifact, status_file)
  ) {
    freshness <- backup_freshness_status(
      as.POSIXct(
        artifact$completed_at,
        format = "%Y-%m-%dT%H:%M:%SZ",
        tz = "UTC"
      ),
      stale_hours = stale_hours,
      critical_hours = critical_hours
    )
    age_hours <- freshness$age_hours
    freshness$status
  } else {
    "INCOMPLETE"
  }
}

admin_status <- "UNAVAILABLE"
retention_status <- "UNAVAILABLE"
connection <- NULL

tryCatch(
  {
    connection <- get_connection("cycling_platform_admin")
    health <- get_backup_health(
      connection = connection,
      stale_hours = stale_hours,
      critical_hours = critical_hours
    )
    admin_status <- health$freshness_status
    if (nrow(health$latest_reconciliation) > 0L) {
      retention_status <- health$latest_reconciliation$status[[1]]
    } else {
      retention_status <- "MISSING"
    }
  },
  error = function(e) {
    invisible(NULL)
  },
  finally = {
    if (!is.null(connection) && DBI::dbIsValid(connection)) {
      DBI::dbDisconnect(connection)
    }
  }
)

cat(
  physical_status,
  if (is.na(age_hours)) "NA" else sprintf("%.1f", age_hours),
  run_prefix,
  admin_status,
  retention_status,
  sep = "\t"
)
cat("\n")

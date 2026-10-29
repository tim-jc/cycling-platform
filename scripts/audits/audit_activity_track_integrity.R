#!/usr/bin/env Rscript

source("bootstrap.R")

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) == 0L || any(arguments %in% c("-h", "--help"))) {
  stop(
    paste(
      "Usage: Rscript scripts/audits/audit_activity_track_integrity.R",
      "<activity_id> [activity_id ...]",
      "\nThe audit is read-only and accepts at most 50 explicit numeric IDs."
    ),
    call. = FALSE
  )
}

activity_ids <- validate_track_audit_activity_ids(arguments)
started_at <- proc.time()[["elapsed"]]

connection <- get_connection("cycling_platform_admin")
on.exit({
  if (DBI::dbIsValid(connection)) DBI::dbDisconnect(connection)
}, add = TRUE)

samples <- fetch_activity_track_samples(connection, activity_ids)
loaded_bytes <- as.numeric(utils::object.size(samples))

returned_ids <- unique(as.character(samples$activity_id))
missing_ids <- setdiff(activity_ids, returned_ids)
if (length(missing_ids) > 0L) {
  warning(
    "No Silver stream samples were returned for activity ID(s): ",
    paste(missing_ids, collapse = ", "),
    call. = FALSE
  )
}

results <- lapply(activity_ids, function(activity_id) {
  rows <- samples[as.character(samples$activity_id) == activity_id, , drop = FALSE]
  if (nrow(rows) == 0L) {
    result <- profile_activity_track_integrity(rows)
    result$summary$activity_id <- activity_id
    return(result)
  }
  profile_activity_track_integrity(rows)
})

summary_rows <- do.call(rbind, lapply(results, track_integrity_summary_row))
diagnostics <- do.call(rbind, lapply(results, `[[`, "diagnostics"))
if (is.null(diagnostics)) diagnostics <- empty_track_diagnostics()
rownames(summary_rows) <- NULL
rownames(diagnostics) <- NULL

message("GPS track-integrity activity summary:")
print(summary_rows, row.names = FALSE)

message("Bounded diagnostics (maximum five rows per activity/category):")
if (nrow(diagnostics) == 0L) {
  message("<none>")
} else {
  print(diagnostics, row.names = FALSE)
}

elapsed_seconds <- proc.time()[["elapsed"]] - started_at
result_bytes <- as.numeric(utils::object.size(results))
message(sprintf(
  "Audit complete: activities_requested=%d activities_returned=%d rows=%d elapsed=%.3fs input_memory=%.2fMiB result_memory=%.2fMiB",
  length(activity_ids), length(returned_ids), nrow(samples), elapsed_seconds,
  loaded_bytes / 1024^2, result_bytes / 1024^2
))

#!/usr/bin/env Rscript

source("bootstrap.R")

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 6L || any(arguments %in% c("-h", "--help"))) {
  stop(
    paste(
      "Usage: Rscript scripts/audits/extract_gps_qualification_stage2c.R",
      "<request-registry.csv> <activity-manifest.csv>",
      "<confirmed-reconciliation.csv> <contextual-findings.csv>",
      "<output-directory> --execute-authorised-read-only"
    ),
    call. = FALSE
  )
}

request_path <- normalizePath(arguments[[1L]], mustWork = TRUE)
manifest_path <- normalizePath(arguments[[2L]], mustWork = TRUE)
reconciliation_path <- normalizePath(arguments[[3L]], mustWork = TRUE)
findings_path <- normalizePath(arguments[[4L]], mustWork = TRUE)
output_directory <- arguments[[5L]]
execution_gate <- arguments[[6L]]
if (execution_gate != "--execute-authorised-read-only") {
  stop("Stage 2C extraction requires the explicit authorised read-only execution flag.", call. = FALSE)
}

requests <- read_gps_stage2c_request_registry(request_path)
activity_manifest <- utils::read.csv(
  manifest_path, colClasses = c(activity_id = "character"), stringsAsFactors = FALSE
)
requests <- validate_gps_stage2c_request_registry(requests, activity_manifest)
prior_decisions <- utils::read.csv(
  reconciliation_path, colClasses = c(activity_id = "character"), stringsAsFactors = FALSE
)
contextual_findings <- utils::read.csv(
  findings_path, colClasses = c(activity_id = "character"), stringsAsFactors = FALSE
)

validate_gps_stage2c_destinations(requests, output_directory)
results <- with_gps_stage2c_read_connection(function(connection) {
  extract_gps_stage2c(
    connection, requests, prior_decisions, contextual_findings
  )
})
repository_commit_sha <- system2(
  "git", c("rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE
)[[1L]]
write_gps_stage2c_results(
  results, requests, output_directory,
  c(request_path, manifest_path, reconciliation_path, findings_path),
  repository_commit_sha
)
message(sprintf(
  "GPS qualification Stage 2C extraction complete: requests=%d output=%s",
  nrow(requests), resolve_track_evidence_output_path(output_directory)
))

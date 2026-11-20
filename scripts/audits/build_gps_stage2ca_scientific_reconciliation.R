#!/usr/bin/env Rscript

source("bootstrap.R")

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 9L || any(arguments %in% c("-h", "--help"))) {
  stop(
    paste(
      "Usage: Rscript scripts/audits/build_gps_stage2ca_scientific_reconciliation.R",
      "<prior-decisions.csv> <prior-context.csv> <stage2c-registry.csv>",
      "<stage2c-evidence-directory> <governed-snapshot.csv> <supplementary-evidence-directory>",
      "<prior-reconciliation-directory>",
      "<output-directory> --build-local-reconciliation"
    ),
    call. = FALSE
  )
}
if (arguments[[9L]] != "--build-local-reconciliation") {
  stop("G3B.2A package creation requires the explicit local-build flag.", call. = FALSE)
}

revision <- system2("git", c("rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE)[[1L]]
result <- write_stage2ca_package(
  output_directory = arguments[[6L]],
  prior_decisions_path = arguments[[1L]],
  prior_context_path = arguments[[2L]],
  stage2c_registry_path = arguments[[3L]],
  stage2c_evidence_root = arguments[[4L]],
  governed_snapshot_path = arguments[[5L]],
  repository_revision = revision,
  supplementary_root = arguments[[7L]],
  prior_reconciliation_root = arguments[[8L]]
)
message(sprintf(
  "G3B.2A local reconciliation complete: decisions=%d claims=%d output=%s",
  nrow(result$decisions), nrow(result$quantitative),
  resolve_track_evidence_output_path(arguments[[6L]])
))

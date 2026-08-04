# Temporary compatibility wrapper.
warning(
  "platform.R is deprecated; use run_raw_ingestion.R instead.",
  call. = FALSE,
  immediate. = TRUE
)

source("run_raw_ingestion.R")

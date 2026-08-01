# run_silver.R
source("bootstrap.R")

config <- load_config()

args <- commandArgs(
  trailingOnly = TRUE
)

stream_rebuild_mode <- if (length(args) > 0L) args[[1]] else "full"
run_silver_job(stream_rebuild_mode = stream_rebuild_mode, config = config)

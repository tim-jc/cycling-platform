config <- load_config()

run_id <- create_etl_run(
  source_id = 1,
  run_mode = "MANUAL"
)

ingest_activities(
  run_id = run_id,
  refresh_days = config$ingestion$activity_refresh_days
)

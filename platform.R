#load all functions
source("bootstrap.R")

config <- load_config()

connection <- get_connection(
  database_name = "cycling_platform_raw"
)

run_id <- create_etl_run(
  connection = connection,
  source_id = 1L,
  run_mode = "MANUAL"
)

tryCatch(
  {
    ingest_activities(
      connection = connection,
      run_id = run_id,
      source_id = 1L,
      refresh_days = config$ingestion$activity_refresh_days,
      config = config
    )

    activity_ids <- DBI::dbGetQuery(
      connection,
      "
      SELECT activity_id
      FROM cycling_platform_raw.activities
      WHERE run_id = ?
      ",
      params = list(run_id)
    )$activity_id

    ingest_streams(
      connection = connection,
      run_id = run_id,
      source_id = 1L,
      activity_ids = activity_ids,
      config = config
    )

    update_etl_run(
      connection = connection,
      run_id = run_id,
      run_status = "SUCCESS"
    )
  },

  error = function(e) {
    update_etl_run(
      connection = connection,
      run_id = run_id,
      run_status = "FAILED",
      error_message = conditionMessage(e)
    )

    stop(e)
  },

  finally = {
    DBI::dbDisconnect(connection)
  }
)

send_notification(
  run_id = run_id
)

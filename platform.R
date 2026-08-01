#load all functions
source("bootstrap.R")

config <- load_config()

args <- commandArgs(
  trailingOnly = TRUE
)

send_run_notification <- TRUE

if ("--no-notification" %in% args) {
  send_run_notification <- FALSE
  args <- setdiff(
    args,
    "--no-notification"
  )
}

execution_mode <- "manual"

if (length(args) > 0) {
  execution_mode <- tolower(args[[1]])
}

if (!execution_mode %in% c("manual", "scheduled", "hygiene", "activity_backfill", "backfill", "streams_only")) {
  stop(
    "Unknown execution mode. Use 'manual', 'scheduled', 'hygiene', 'activity_backfill', 'backfill', or 'streams_only'.",
    call. = FALSE
  )
}

mode_specification <- activity_ingestion_mode(config, execution_mode)
run_mode <- mode_specification$run_mode
activity_refresh_days <- mode_specification$refresh_days

google_health_enabled <- !is.null(config$sources$google_health$enabled) &&
  isTRUE(config$sources$google_health$enabled)
activity_maintenance_mode <- execution_mode %in% c("hygiene", "activity_backfill")
raw_lock_connection <- NULL
if (!identical(Sys.getenv("CYCLING_PLATFORM_PARENT_LOCK"), "1")) {
  raw_lock_connection <- get_connection("cycling_platform_admin")
  acquire_platform_run_lock(raw_lock_connection, execution_mode)
}

if (
  execution_mode != "streams_only" &&
    !activity_maintenance_mode &&
    isTRUE(google_health_enabled)
) {
  message("Checking Google Health OAuth token before ingestion.")
  get_google_health_access_token()
  message("Google Health OAuth token refresh check succeeded.")
}

connection <- get_connection(
  database_name = "cycling_platform_raw"
)

run_id <- create_etl_run(
  connection = connection,
  source_id = 1L,
  run_mode = run_mode
)

platform_error <- NULL

tryCatch(
  {
    if (execution_mode != "streams_only") {
      ingest_activities(
        connection = connection,
        run_id = run_id,
        source_id = 1L,
        refresh_days = activity_refresh_days,
        config = config
      )

      if (!activity_maintenance_mode) {
        ingest_gear(
          connection = connection,
          run_id = run_id,
          source_id = 1L,
          config = config
        )
      }
    }

    stream_activity_ids <- get_pending_stream_activity_ids(
      connection = connection
    )

    pending_stream_count <- length(stream_activity_ids)

    stream_recovery_limit <- config$ingestion$streams_only_activity_limit

    if (is.null(stream_recovery_limit)) {
      stream_recovery_limit <- 900L
    }

    if (execution_mode == "streams_only") {
      stream_activity_ids <- head(
        stream_activity_ids,
        stream_recovery_limit
      )

      message(glue::glue(
        "Streams-only mode: {pending_stream_count} pending stream activities; ",
        "attempting {length(stream_activity_ids)}."
      ))
    }

    if (length(stream_activity_ids) == 0) {
      message(
        "No activities require stream ingestion."
      )
    } else {
      ingest_streams(
        connection = connection,
        run_id = run_id,
        source_id = 1L,
        activity_ids = stream_activity_ids,
        config = config
      )
    }

    if (execution_mode != "streams_only") {
      detail_activity_ids <- get_pending_detail_activity_ids(
        connection = connection
      )

      if (length(detail_activity_ids) == 0) {
        message(
          "No activities require detail ingestion."
        )
      } else {
        ingest_activity_details(
          connection = connection,
          run_id = run_id,
          source_id = 1L,
          activity_ids = detail_activity_ids,
          config = config
        )
      }

      lap_activity_ids <- get_pending_lap_activity_ids(
        connection = connection
      )

      if (length(lap_activity_ids) == 0) {
        message(
          "No activities require lap ingestion."
        )
      } else {
        ingest_activity_laps(
          connection = connection,
          run_id = run_id,
          source_id = 1L,
          activity_ids = lap_activity_ids,
          config = config
        )
      }

      if (
        isTRUE(google_health_enabled) && !activity_maintenance_mode
      ) {
        google_health_data_types <- config$sources$google_health$data_types

        if (is.null(google_health_data_types)) {
          google_health_data_types <- character()
        }

        if (execution_mode == "backfill") {
          google_health_refresh_days <- config$ingestion$google_health_backfill_days
        } else {
          google_health_refresh_days <- config$ingestion$google_health_refresh_days
        }

        if (is.null(google_health_refresh_days)) {
          google_health_refresh_days <- 7L
        }

        ingest_google_health_heart_rate(
          connection = connection,
          run_id = run_id,
          source_id = 2L,
          config = config,
          start_date = Sys.Date() - as.integer(google_health_refresh_days),
          end_date = Sys.Date()
        )

        if (execution_mode == "backfill") {
          google_health_sleep_refresh_days <- config$ingestion$google_health_sleep_backfill_days
        } else {
          google_health_sleep_refresh_days <- config$ingestion$google_health_sleep_refresh_days
        }

        if (is.null(google_health_sleep_refresh_days)) {
          google_health_sleep_refresh_days <- 7L
        }

        ingest_google_health_sleep_logs(
          connection = connection,
          run_id = run_id,
          source_id = 2L,
          config = config,
          start_date = Sys.Date() - as.integer(google_health_sleep_refresh_days),
          end_date = Sys.Date()
        )

        if ("daily-resting-heart-rate" %in% google_health_data_types) {
          if (execution_mode == "backfill") {
            google_health_rhr_refresh_days <- config$ingestion$google_health_daily_resting_heart_rate_backfill_days
          } else {
            google_health_rhr_refresh_days <- config$ingestion$google_health_daily_resting_heart_rate_refresh_days
          }

          if (is.null(google_health_rhr_refresh_days)) {
            google_health_rhr_refresh_days <- 14L
          }

          ingest_google_health_daily_resting_heart_rate(
            connection = connection,
            run_id = run_id,
            source_id = 2L,
            config = config,
            start_date = Sys.Date() - as.integer(google_health_rhr_refresh_days),
            end_date = Sys.Date()
          )
        }

        if ("daily-heart-rate-variability" %in% google_health_data_types) {
          if (execution_mode == "backfill") {
            google_health_hrv_refresh_days <- config$ingestion$google_health_daily_heart_rate_variability_backfill_days
          } else {
            google_health_hrv_refresh_days <- config$ingestion$google_health_daily_heart_rate_variability_refresh_days
          }

          if (is.null(google_health_hrv_refresh_days)) {
            google_health_hrv_refresh_days <- 14L
          }

          ingest_google_health_daily_heart_rate_variability(
            connection = connection,
            run_id = run_id,
            source_id = 2L,
            config = config,
            start_date = Sys.Date() - as.integer(google_health_hrv_refresh_days),
            end_date = Sys.Date()
          )
        }

        if ("daily-respiratory-rate" %in% google_health_data_types) {
          if (execution_mode == "backfill") {
            google_health_respiratory_rate_refresh_days <- config$ingestion$google_health_daily_respiratory_rate_backfill_days
          } else {
            google_health_respiratory_rate_refresh_days <- config$ingestion$google_health_daily_respiratory_rate_refresh_days
          }

          if (is.null(google_health_respiratory_rate_refresh_days)) {
            google_health_respiratory_rate_refresh_days <- 14L
          }

          ingest_google_health_daily_respiratory_rate(
            connection = connection,
            run_id = run_id,
            source_id = 2L,
            config = config,
            start_date = Sys.Date() - as.integer(google_health_respiratory_rate_refresh_days),
            end_date = Sys.Date()
          )
        }
      }
    }

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

    platform_error <<- e
  },

  finally = {
    DBI::dbDisconnect(connection)
  }
)

if (isTRUE(send_run_notification)) {
  send_notification(
    run_id = run_id,
    config = config
  )
}

if (!is.null(raw_lock_connection)) {
  release_platform_run_lock(raw_lock_connection, execution_mode)
  DBI::dbDisconnect(raw_lock_connection)
}

if (!is.null(platform_error)) {
  stop(platform_error)
}

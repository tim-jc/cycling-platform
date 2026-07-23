# run_silver.R
source("bootstrap.R")

config <- load_config()

args <- commandArgs(
  trailingOnly = TRUE
)

stream_rebuild_mode <- "full"

if (length(args) > 0) {
  stream_rebuild_mode <- tolower(args[[1]])
}

if (stream_rebuild_mode == "resume") {
  stream_rebuild_mode <- "repair"
}

if (!stream_rebuild_mode %in% c("full", "repair")) {
  stop(
    "Unknown silver stream rebuild mode. Use 'full' or 'repair'.",
    call. = FALSE
  )
}

connection <- get_connection("cycling_platform_admin")

tryCatch(
  {
    run_silver_transformations(
      connection = connection,
      config = config,
      stream_rebuild_mode = stream_rebuild_mode
    )

    message("Silver transformations complete.")
  },

  finally = {
    if (DBI::dbIsValid(connection)) {
      DBI::dbDisconnect(connection)
    }
  }
)

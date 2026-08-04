source("bootstrap.R")

args <- commandArgs(
  trailingOnly = TRUE
)

output_path <- if (length(args) > 0 && nzchar(args[[1]])) {
  args[[1]]
} else {
  NULL
}

connection <- get_connection("cycling_platform_admin")

tryCatch(
  {
    classification_report <- report_power_source_classification(
      connection = connection,
      output_path = output_path
    )

    message("Power source classification summary:")
    print(
      aggregate(
        activity_id ~ power_source_type + power_source_status +
          is_power_record_eligible,
        data = classification_report,
        FUN = length
      )
    )

    message("Power record reconciliation:")
    print(
      report_power_record_reconciliation(
        connection = connection
      )
    )

    if (!is.null(output_path)) {
      message("Wrote power source classification audit CSV: ", output_path)
    }
  },
  finally = {
    if (DBI::dbIsValid(connection)) {
      DBI::dbDisconnect(connection)
    }
  }
)

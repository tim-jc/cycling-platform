source("bootstrap.R")

args <- commandArgs(trailingOnly = TRUE)
apply <- identical(args, "--apply")
if (length(args) > 1L || (length(args) == 1L && !apply)) {
  stop("Usage: Rscript scripts/operations/reconcile_legacy_running_executions.R [--apply]", call. = FALSE)
}

connection <- get_connection("cycling_platform_admin")
on.exit(DBI::dbDisconnect(connection), add = TRUE)

result <- reconcile_legacy_running_executions(connection, apply = apply)

message("Reviewed legacy interrupted executions")
print(result$targets, row.names = FALSE)

if (isTRUE(result$applied)) {
  message(
    "Reconciliation committed: ",
    paste(names(result$updated), result$updated, collapse = "; ")
  )
} else {
  message("Read-only preflight passed. Re-run with --apply to commit the exact reviewed target set.")
}

#!/usr/bin/env Rscript
source("bootstrap.R")
connection <- get_connection("cycling_platform_admin")
on.exit(DBI::dbDisconnect(connection), add = TRUE)
audit <- report_silver_activity_population(connection)
print(audit, row.names = FALSE)

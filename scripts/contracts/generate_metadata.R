#!/usr/bin/env Rscript
source("R/contracts/data_contract_utils.R")
paths <- unlist(lapply(contract_managed_domains("."), function(layer) list.files(file.path("metadata", layer), "\\.json$", full.names = TRUE)))
if (!length(paths)) stop("No data-contract metadata documents found.")
for (path in paths) {
  metadata <- read_contract_json(path)
  metadata$physical_schema <- contract_physical_schema_metadata(
    metadata$object$ddl_path
  )
  jsonlite::write_json(metadata, path, pretty = TRUE, auto_unbox = TRUE, null = "null")
  message("Updated physical metadata: ", path)
}

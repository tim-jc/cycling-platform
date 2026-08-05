#!/usr/bin/env Rscript
source("R/contracts/data_contract_utils.R")
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments)) stop("Unknown argument(s): ", paste(arguments, collapse = " "))
result <- validate_data_contract_project(".", write_report = TRUE)
codes <- vapply(result$errors, `[[`, character(1), "code")
count_code <- function(code) sum(codes == code)
cat("Data contract validation: ", if (result$passed) "PASSED" else "FAILED", "\n",
    "Managed objects: ", result$counts$silver + result$counts$gold + result$counts$reference, " (Silver ", result$counts$silver, ", Gold ", result$counts$gold, ", Reference ", result$counts$reference, ")\n",
    "Contracts missing: ", count_code("missing_contract"), "\nMetadata missing: ", count_code("missing_metadata"),
    "\nSchema mismatches: ", count_code("schema_mismatch"), "\nOpen blocking TODOs: ", result$counts$open_blocking,
    "\nSee reports/data-contract-validation.md\n", sep = "")
if (!result$passed) quit(status = 1L)

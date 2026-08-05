platform_database_inventory_path <- function(project_root = ".") {
  candidates <- unique(c(project_root, file.path(project_root, "..", "..")))
  paths <- file.path(candidates, "config", "platform_databases.tsv")
  existing <- paths[file.exists(paths)]
  if (length(existing) == 0L) {
    stop("Platform database inventory not found from: ", project_root, call. = FALSE)
  }
  existing[[1]]
}

load_platform_database_inventory <- function(project_root = ".") {
  path <- platform_database_inventory_path(project_root)
  inventory <- utils::read.delim(
    path,
    colClasses = "character",
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  required <- c(
    "database_name", "domain", "durability", "backup_included",
    "contract_governed", "character_set", "collation"
  )
  if (!identical(names(inventory), required)) {
    stop("Platform database inventory columns are invalid: ", path, call. = FALSE)
  }
  if (any(!nzchar(trimws(as.matrix(inventory)))) || anyDuplicated(inventory$database_name) ||
      anyDuplicated(inventory$domain)) {
    stop("Platform database inventory contains blank or duplicate values.", call. = FALSE)
  }
  for (column in c("backup_included", "contract_governed")) {
    if (any(!inventory[[column]] %in% c("TRUE", "FALSE"))) {
      stop("Platform database inventory has an invalid logical value in ", column, ".", call. = FALSE)
    }
    inventory[[column]] <- inventory[[column]] == "TRUE"
  }
  inventory
}

platform_required_databases <- function(inventory = load_platform_database_inventory()) {
  inventory$database_name
}

platform_backup_databases <- function(inventory = load_platform_database_inventory()) {
  inventory$database_name[inventory$backup_included]
}

platform_contract_domains <- function(inventory = load_platform_database_inventory()) {
  inventory$domain[inventory$contract_governed]
}

platform_canonical_character_set <- function(inventory = load_platform_database_inventory()) {
  values <- unique(inventory$character_set)
  if (length(values) != 1L) stop("Platform databases do not share one canonical character set.", call. = FALSE)
  values[[1]]
}

platform_canonical_collation <- function(inventory = load_platform_database_inventory()) {
  values <- unique(inventory$collation)
  if (length(values) != 1L) stop("Platform databases do not share one canonical collation.", call. = FALSE)
  values[[1]]
}

platform_database_access_findings <- function(
  connection,
  database_names = platform_required_databases(),
  use_database = function(connection, database_name) {
    DBI::dbExecute(connection, paste0("USE `", database_name, "`"))
  }
) {
  findings <- lapply(database_names, function(database_name) {
    error <- tryCatch(
      {
        use_database(connection, database_name)
        NULL
      },
      error = identity
    )
    if (is.null(error)) return(NULL)
    message <- conditionMessage(error)
    issue <- if (grepl("unknown database", message, ignore.case = TRUE)) {
      "missing_database"
    } else if (grepl("access denied|permission", message, ignore.case = TRUE)) {
      "inaccessible_database"
    } else {
      "database_access_failed"
    }
    data.frame(database_name = database_name, issue = issue, error = message)
  })
  dplyr::bind_rows(findings)
}

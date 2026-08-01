contract_required_sections <- c(
  "Purpose", "Business definition", "Grain", "Canonical claim",
  "Primary key and uniqueness", "Source and lineage",
  "Date and timezone semantics", "Transformations and business rules",
  "Data quality expectations", "Known limitations", "Consumers",
  "Human review TODOs", "Architectural notes", "Generated metadata"
)

contract_lifecycle_values <- c(
  "draft", "implemented", "semantically_reviewed", "certified", "deprecated"
)
contract_review_values <- c("not_started", "in_review", "reviewed")
contract_todo_severities <- c("blocking", "non_blocking", "future")
contract_todo_statuses <- c("open", "resolved", "accepted")

normalise_contract_type <- function(value) {
  value <- tolower(trimws(value))
  value <- sub("\\s+unsigned$", "", value)
  value <- sub("\\(.*$", "", value)
  switch(
    value,
    int =, integer = "integer",
    tinyint =, bool =, boolean = "boolean",
    double =, real =, "double precision" = "double",
    bigint = "bigint", varchar = "varchar", char = "char", text = "text",
    date = "date", time = "time", datetime = "datetime",
    timestamp = "timestamp", json = "json", decimal = "decimal",
    value
  )
}

extract_create_body <- function(sql) {
  start <- regexpr("CREATE[[:space:]]+(?:TABLE|VIEW).*?\\(", sql, perl = TRUE)
  if (start[[1]] < 0L) stop("No CREATE TABLE/VIEW statement found")
  open <- start[[1]] + attr(start, "match.length") - 1L
  depth <- 0L
  quote <- ""
  chars <- strsplit(sql, "", fixed = TRUE)[[1]]
  for (index in seq.int(open, length(chars))) {
    char <- chars[[index]]
    if (nzchar(quote)) {
      if (char == quote && chars[[index - 1L]] != "\\") quote <- ""
    } else if (char %in% c("'", "\"", "`")) {
      quote <- char
    } else if (char == "(") {
      depth <- depth + 1L
    } else if (char == ")") {
      depth <- depth - 1L
      if (depth == 0L) return(substr(sql, open + 1L, index - 1L))
    }
  }
  stop("Unterminated CREATE statement")
}

split_sql_definitions <- function(body) {
  chars <- strsplit(body, "", fixed = TRUE)[[1]]
  parts <- character()
  start <- 1L
  depth <- 0L
  quote <- ""
  for (index in seq_along(chars)) {
    char <- chars[[index]]
    previous <- if (index > 1L) chars[[index - 1L]] else ""
    if (nzchar(quote)) {
      if (char == quote && previous != "\\") quote <- ""
    } else if (char %in% c("'", "\"", "`")) {
      quote <- char
    } else if (char == "(") {
      depth <- depth + 1L
    } else if (char == ")") {
      depth <- depth - 1L
    } else if (char == "," && depth == 0L) {
      parts <- c(parts, trimws(paste(chars[start:(index - 1L)], collapse = "")))
      start <- index + 1L
    }
  }
  c(parts, trimws(paste(chars[start:length(chars)], collapse = "")))
}

constraint_columns <- function(definitions, pattern) {
  hits <- grep(pattern, definitions, value = TRUE, ignore.case = TRUE)
  unique(unlist(lapply(hits, function(definition) {
    match <- regexec("\\(([^)]+)\\)", definition, perl = TRUE)
    parts <- regmatches(definition, match)[[1]]
    if (length(parts) < 2L) return(character())
    trimws(gsub("`", "", strsplit(parts[[2]], ",", fixed = TRUE)[[1]]))
  })))
}

parse_contract_ddl <- function(path) {
  sql <- paste(readLines(path, warn = FALSE), collapse = "\n")
  body <- extract_create_body(sql)
  definitions <- split_sql_definitions(body)
  constraint <- grepl(
    "^(PRIMARY|UNIQUE|KEY|INDEX|CONSTRAINT|FOREIGN|CHECK)\\b",
    definitions,
    ignore.case = TRUE
  )
  column_definitions <- definitions[!constraint]
  primary <- constraint_columns(definitions, "PRIMARY[[:space:]]+KEY")
  unique_columns <- constraint_columns(definitions, "UNIQUE(?:[[:space:]]+KEY)?")

  columns <- lapply(seq_along(column_definitions), function(index) {
    definition <- gsub("[[:space:]]+", " ", trimws(column_definitions[[index]]))
    match <- regexec("^`?([a-zA-Z0-9_]+)`?[[:space:]]+([^[:space:]]+(?:[[:space:]]+PRECISION)?)(.*)$", definition, perl = TRUE)
    parts <- regmatches(definition, match)[[1]]
    if (length(parts) < 4L) stop("Cannot parse DDL column: ", definition)
    name <- parts[[2]]
    raw_type <- toupper(parts[[3]])
    remainder <- parts[[4]]
    inline_pk <- grepl("PRIMARY[[:space:]]+KEY", remainder, ignore.case = TRUE)
    default_match <- regexec(
      "DEFAULT[[:space:]]+((?:'[^']*')|(?:[^[:space:],]+))",
      remainder,
      perl = TRUE,
      ignore.case = TRUE
    )
    default_parts <- regmatches(remainder, default_match)[[1]]
    list(
      name = name,
      ordinal_position = index,
      data_type = normalise_contract_type(raw_type),
      raw_data_type = raw_type,
      nullable = !grepl("NOT[[:space:]]+NULL|PRIMARY[[:space:]]+KEY", remainder, ignore.case = TRUE),
      default = if (length(default_parts) > 1L) default_parts[[2]] else NULL,
      primary_key = inline_pk || name %in% primary,
      unique = inline_pk || name %in% primary || name %in% unique_columns
    )
  })
  list(
    columns = columns,
    primary_key = vapply(Filter(function(x) isTRUE(x$primary_key), columns), `[[`, character(1), "name"),
    unique_constraints = lapply(grep("UNIQUE(?:[[:space:]]+KEY)?", definitions, value = TRUE, ignore.case = TRUE), function(definition) {
      list(name = sub(".*UNIQUE(?:[[:space:]]+KEY)?[[:space:]]+`?([a-zA-Z0-9_]+)`?.*", "\\1", definition, perl = TRUE), columns = constraint_columns(definition, ".*"))
    })
  )
}

discover_managed_objects <- function(root) {
  result <- list()
  for (layer in c("silver", "gold")) {
    files <- list.files(file.path(root, "sql", layer), "\\.sql$", full.names = TRUE)
    for (path in files) {
      sql <- paste(readLines(path, warn = FALSE), collapse = "\n")
      match <- regexec(
        "CREATE[[:space:]]+(TABLE|VIEW)[[:space:]]+(?:IF[[:space:]]+NOT[[:space:]]+EXISTS[[:space:]]+)?(cycling_platform_(silver|gold))[.]`?([a-zA-Z0-9_]+)`?",
        sql, perl = TRUE, ignore.case = TRUE
      )
      parts <- regmatches(sql, match)[[1]]
      if (length(parts) > 0L) {
        key <- paste0(tolower(parts[[4]]), ".", parts[[5]])
        result[[key]] <- list(
          schema = tolower(parts[[4]]), database_schema = parts[[3]],
          name = parts[[5]], type = tolower(parts[[2]]),
          ddl_path = sub(paste0("^", root, "/?"), "", path)
        )
      }
    }
  }
  result
}

contract_issue <- function(code, message, object = NULL) {
  list(code = code, message = message, object = object)
}

read_contract_json <- function(path) {
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

validate_metadata_structure <- function(metadata, path) {
  errors <- list()
  add <- function(code, message) errors <<- c(errors, list(contract_issue(code, paste0(path, ": ", message))))
  required <- c("metadata_version", "object", "governance", "physical_schema", "lineage", "data_quality", "human_todos")
  for (field in required) if (is.null(metadata[[field]])) add("invalid_metadata", paste("missing", field))
  if (length(errors)) return(errors)
  if (!grepl("^[0-9]+\\.[0-9]+\\.[0-9]+$", metadata$metadata_version)) add("invalid_metadata", "metadata_version must be semantic-version shaped")
  for (field in c("schema", "database_schema", "name", "type", "ddl_path")) if (is.null(metadata$object[[field]])) add("invalid_metadata", paste("object missing", field))
  if (!metadata$object$type %in% c("table", "view")) add("invalid_enum", "invalid object type")
  for (field in c("owner", "lifecycle", "contract_path", "semantic_review_status", "last_verified_date")) if (is.null(metadata$governance[[field]])) add("invalid_metadata", paste("governance missing", field))
  if (!metadata$governance$lifecycle %in% contract_lifecycle_values) add("invalid_enum", "invalid lifecycle")
  if (!metadata$governance$semantic_review_status %in% contract_review_values) add("invalid_enum", "invalid semantic review status")
  if (is.null(metadata$physical_schema$columns)) add("invalid_metadata", "physical_schema missing columns")
  for (column in metadata$physical_schema$columns) {
    required_column <- c("name", "ordinal_position", "data_type", "raw_data_type", "nullable", "default", "primary_key", "unique")
    if (!all(required_column %in% names(column))) add("invalid_metadata", "physical column missing required fields")
  }
  required_lineage <- c("source_objects", "source_columns", "transformation_files", "transformation_functions", "transformation_description", "authorship", "confidence", "review_required")
  if (!all(required_lineage %in% names(metadata$lineage))) add("invalid_metadata", "lineage missing required fields")
  if (!is.null(metadata$lineage$authorship) && !metadata$lineage$authorship %in% c("generated", "human_authored", "generated_and_human_reviewed")) add("invalid_enum", "invalid lineage authorship")
  if (!is.null(metadata$lineage$confidence) && !metadata$lineage$confidence %in% c("high", "medium", "low", "unknown")) add("invalid_enum", "invalid lineage confidence")
  required_quality <- c("uniqueness_expectations", "not_null_expectations", "referential_integrity_expectations", "accepted_values", "implemented_validations")
  if (!all(required_quality %in% names(metadata$data_quality))) add("invalid_metadata", "data_quality missing required fields")
  for (todo in metadata$human_todos) {
    if (!all(c("id", "field", "severity", "status", "text", "resolution") %in% names(todo))) add("invalid_todo", "TODO missing required fields")
    if (!is.null(todo$id) && !grepl("^(SILVER|GOLD)-[A-Z0-9_]+-[0-9]{3}$", todo$id)) add("invalid_todo", paste("invalid TODO ID", todo$id))
    if (!is.null(todo$severity) && !todo$severity %in% contract_todo_severities) add("invalid_enum", paste("invalid TODO severity", todo$severity))
    if (!is.null(todo$status) && !todo$status %in% contract_todo_statuses) add("invalid_enum", paste("invalid TODO status", todo$status))
    if (!is.null(todo$status) && todo$status %in% c("resolved", "accepted") && (is.null(todo$resolution) || !nzchar(trimws(todo$resolution)))) add("invalid_todo", paste(todo$id, "requires a resolution or rationale"))
  }
  errors
}

validate_data_contract_project <- function(root = ".", write_report = TRUE) {
  root <- normalizePath(root, mustWork = TRUE)
  errors <- list(); warnings <- list()
  add_error <- function(code, message, object = NULL) errors <<- c(errors, list(contract_issue(code, message, object)))
  add_warning <- function(code, message, object = NULL) warnings <<- c(warnings, list(contract_issue(code, message, object)))
  managed <- discover_managed_objects(root)
  schema_path <- file.path(root, "metadata", "schema", "data-contract.schema.json")
  if (!file.exists(schema_path)) add_error("missing_json_schema", "Missing metadata/schema/data-contract.schema.json") else tryCatch(read_contract_json(schema_path), error = function(e) add_error("invalid_json_schema", conditionMessage(e)))
  exclusions_path <- file.path(root, "metadata", "exclusions.json")
  exclusions <- if (file.exists(exclusions_path)) read_contract_json(exclusions_path) else list(objects = list(), supporting_contract_documents = list())
  excluded_objects <- vapply(exclusions$objects, function(x) x$object, character(1))
  managed <- managed[!names(managed) %in% excluded_objects]
  supporting_docs <- unlist(exclusions$supporting_contract_documents, use.names = FALSE)
  metadata_by_object <- list(); metadata_paths <- character(); contract_paths <- character()

  for (layer in c("silver", "gold")) {
    metadata_paths <- c(metadata_paths, list.files(file.path(root, "metadata", layer), "\\.json$", full.names = TRUE))
    contract_paths <- c(contract_paths, list.files(file.path(root, "docs", "data-contracts", layer), "\\.md$", full.names = TRUE))
  }
  rel <- function(paths) substring(paths, nchar(root) + 2L)
  for (path in metadata_paths) {
    metadata <- tryCatch(read_contract_json(path), error = function(e) e)
    if (inherits(metadata, "error")) { add_error("invalid_json", paste(rel(path), conditionMessage(metadata))); next }
    errors <- c(errors, validate_metadata_structure(metadata, rel(path)))
    if (is.null(metadata$object$schema) || is.null(metadata$object$name)) next
    key <- paste0(metadata$object$schema, ".", metadata$object$name)
    if (!is.null(metadata_by_object[[key]])) add_error("duplicate_metadata", paste("Multiple metadata documents for", key), key)
    metadata_by_object[[key]] <- metadata
  }

  for (key in names(managed)) {
    expected_metadata <- file.path(root, "metadata", managed[[key]]$schema, paste0(managed[[key]]$name, ".json"))
    expected_contract <- file.path(root, "docs", "data-contracts", managed[[key]]$schema, paste0(managed[[key]]$name, ".md"))
    if (!file.exists(expected_metadata)) add_error("missing_metadata", paste("Missing metadata for", key), key)
    if (!file.exists(expected_contract)) add_error("missing_contract", paste("Missing contract for", key), key)
  }
  for (key in setdiff(names(metadata_by_object), names(managed))) add_error("orphan_metadata", paste("Metadata has no managed DDL object:", key), key)
  expected_contracts <- vapply(managed, function(x) file.path("docs", "data-contracts", x$schema, paste0(x$name, ".md")), character(1))
  for (path in setdiff(rel(contract_paths), c(expected_contracts, supporting_docs))) add_error("orphan_contract", paste("Contract has no managed object or explicit supporting-document exclusion:", path))

  todo_ids <- character()
  for (key in intersect(names(managed), names(metadata_by_object))) {
    metadata <- metadata_by_object[[key]]; object <- managed[[key]]
    if (!identical(metadata$object$ddl_path, object$ddl_path)) add_error("ddl_reference", paste(key, "references incorrect DDL path"), key)
    contract_path <- file.path(root, metadata$governance$contract_path)
    expected_contract <- file.path("docs", "data-contracts", object$schema, paste0(object$name, ".md"))
    if (!identical(metadata$governance$contract_path, expected_contract) || !file.exists(contract_path)) add_error("contract_reference", paste(key, "references a missing or incorrect contract"), key)
    for (path in unique(c(metadata$object$ddl_path, unlist(metadata$lineage$transformation_files, use.names = FALSE)))) if (!file.exists(file.path(root, path))) add_error("broken_reference", paste(key, "references missing implementation file", path), key)
    ddl <- tryCatch(parse_contract_ddl(file.path(root, object$ddl_path)), error = function(e) e)
    if (inherits(ddl, "error")) add_error("ddl_parse", paste(key, conditionMessage(ddl)), key) else {
      actual <- ddl$columns; documented <- metadata$physical_schema$columns
      actual_names <- vapply(actual, `[[`, character(1), "name"); documented_names <- vapply(documented, `[[`, character(1), "name")
      for (name in setdiff(actual_names, documented_names)) add_error("schema_mismatch", paste(key, "DDL column absent from metadata:", name), key)
      for (name in setdiff(documented_names, actual_names)) add_error("schema_mismatch", paste(key, "metadata column absent from DDL:", name), key)
      for (name in intersect(actual_names, documented_names)) {
        a <- actual[[match(name, actual_names)]]; d <- documented[[match(name, documented_names)]]
        for (field in c("ordinal_position", "data_type", "nullable", "primary_key", "unique")) if (!identical(a[[field]], d[[field]])) add_error("schema_mismatch", paste(key, name, field, "metadata=", d[[field]], "DDL=", a[[field]]), key)
      }
    }
    if (file.exists(contract_path)) {
      lines <- readLines(contract_path, warn = FALSE)
      headings <- sub("^##[[:space:]]+", "", grep("^##[[:space:]]+", lines, value = TRUE))
      for (section in setdiff(contract_required_sections, headings)) add_error("missing_section", paste(key, "contract missing section:", section), key)
    }
    todos <- metadata$human_todos
    ids <- vapply(todos, function(x) x$id, character(1)); todo_ids <- c(todo_ids, ids)
    if (metadata$governance$lifecycle == "certified" && any(vapply(todos, function(x) x$status == "open" && x$severity == "blocking", logical(1)))) add_error("lifecycle_todo", paste(key, "is certified with an open blocking TODO"), key)
    if (metadata$governance$lifecycle %in% c("semantically_reviewed", "certified") && metadata$governance$semantic_review_status != "reviewed") add_error("lifecycle_review", paste(key, "lifecycle requires semantic_review_status=reviewed"), key)
    for (source in metadata$lineage$source_objects) {
      source_key <- sub("^cycling_platform_", "", source)
      if (grepl("^(silver|gold)[.]", source_key) && !source_key %in% names(managed)) add_error("broken_source_reference", paste(key, "references unmanaged Silver/Gold source", source), key)
    }
  }
  duplicates <- unique(todo_ids[duplicated(todo_ids)])
  for (id in duplicates) add_error("duplicate_todo", paste("Duplicate TODO ID:", id))

  standards_path <- file.path(root, "metadata", "standards", "shared-columns.json")
  if (file.exists(standards_path)) {
    standards <- read_contract_json(standards_path)$standards
    for (key in intersect(names(managed), names(metadata_by_object))) for (standard in standards) {
      columns <- metadata_by_object[[key]]$physical_schema$columns
      names_ <- vapply(columns, `[[`, character(1), "name")
      if (standard$preferred_name %in% names_) {
        type <- columns[[match(standard$preferred_name, names_)]]$data_type
        if (!type %in% unlist(standard$allowed_physical_types)) add_warning("shared_column_deviation", paste(key, standard$preferred_name, "uses", type))
      }
    }
  }
  lifecycle <- table(vapply(metadata_by_object, function(x) x$governance$lifecycle, character(1)))
  todos <- unlist(lapply(metadata_by_object, `[[`, "human_todos"), recursive = FALSE)
  count_todos <- function(severity = NULL, status = NULL) sum(vapply(todos, function(x) (is.null(severity) || x$severity == severity) && (is.null(status) || x$status == status), logical(1)))
  result <- list(
    passed = length(errors) == 0L, errors = errors, warnings = warnings,
    managed = managed, metadata = metadata_by_object, lifecycle = lifecycle,
    counts = list(
      silver = sum(vapply(managed, function(x) x$schema == "silver", logical(1))),
      gold = sum(vapply(managed, function(x) x$schema == "gold", logical(1))),
      open_blocking = count_todos("blocking", "open"),
      open_non_blocking = count_todos("non_blocking", "open"),
      accepted = count_todos(status = "accepted")
    )
  )
  if (write_report) write_contract_report(result, file.path(root, "reports", "data-contract-validation.md"))
  result
}

write_contract_report <- function(result, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  issue_lines <- function(items) if (!length(items)) "- None" else vapply(items, function(x) paste0("- `", x$code, "`: ", x$message), character(1))
  lifecycle_lines <- if (!length(result$lifecycle)) "- None" else paste0("- ", names(result$lifecycle), ": ", as.integer(result$lifecycle))
  codes <- vapply(result$errors, `[[`, character(1), "code")
  count_codes <- function(values) sum(codes %in% values)
  todos <- unlist(lapply(result$metadata, `[[`, "human_todos"), recursive = FALSE)
  todo_lines <- function(severity = NULL, status = NULL) {
    selected <- Filter(function(x) (is.null(severity) || x$severity == severity) && (is.null(status) || x$status == status), todos)
    if (!length(selected)) "- None" else vapply(selected, function(x) paste0("- `", x$id, "` (", x$severity, "): ", x$text), character(1))
  }
  lines <- c(
    "# Data contract validation", "",
    paste0("- Validation timestamp: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    paste0("- Overall result: **", if (result$passed) "PASSED" else "FAILED", "**"),
    paste0("- Managed Silver objects: ", result$counts$silver),
    paste0("- Managed Gold objects: ", result$counts$gold),
    paste0("- Missing contracts: ", count_codes("missing_contract")),
    paste0("- Missing metadata: ", count_codes("missing_metadata")),
    paste0("- Schema mismatches: ", count_codes("schema_mismatch")),
    paste0("- Broken references: ", count_codes(c("broken_reference", "broken_source_reference", "contract_reference", "ddl_reference"))),
    paste0("- Open blocking TODOs: ", result$counts$open_blocking),
    paste0("- Open non-blocking TODOs: ", result$counts$open_non_blocking),
    paste0("- Accepted limitations: ", result$counts$accepted), "",
    "## Objects by lifecycle status", "", lifecycle_lines, "",
    "## Open blocking TODOs", "", todo_lines("blocking", "open"), "",
    "## Open non-blocking TODOs", "", todo_lines("non_blocking", "open"), "",
    "## Accepted limitations", "", todo_lines(status = "accepted"), "",
    "## Failures", "", issue_lines(result$errors), "",
    "## Warnings", "", issue_lines(result$warnings), ""
  )
  writeLines(lines, path)
}

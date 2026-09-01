contract_project_root <- if (file.exists("R/contracts/data_contract_utils.R")) "." else file.path("..", "..")
source(file.path(contract_project_root, "R/contracts/data_contract_utils.R"))

fixture_contract <- function() paste(c("# Contract", "", paste0("## ", contract_required_sections, "\n\nFixture content.")), collapse = "\n")

make_contract_fixture <- function() {
  root <- tempfile("contract-fixture-")
  paths <- c("sql/silver", "sql/gold", "sql/reference", "metadata/silver", "metadata/gold", "metadata/reference", "metadata/schema", "metadata/standards", "docs/data-contracts/silver", "docs/data-contracts/gold", "docs/data-contracts/reference", "reports", "R/transforms")
  invisible(vapply(file.path(root, paths), dir.create, logical(1), recursive = TRUE))
  ddl_path <- file.path(root, "sql/silver/010_create_widget.sql")
  writeLines(c("CREATE TABLE IF NOT EXISTS cycling_platform_silver.widget (", "  widget_id BIGINT NOT NULL,", "  label VARCHAR(50) NULL,", "  PRIMARY KEY (widget_id)", ") ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 DEFAULT COLLATE utf8mb4_general_ci;"), ddl_path)
  writeLines("fixture <- function() NULL", file.path(root, "R/transforms/widget.R"))
  writeLines(fixture_contract(), file.path(root, "docs/data-contracts/silver/widget.md"))
  writeLines('{"objects":[],"supporting_contract_documents":[]}', file.path(root, "metadata/exclusions.json"))
  file.copy(
    file.path(contract_project_root, "metadata/schema/data-contract.schema.json"),
    file.path(root, "metadata/schema/data-contract.schema.json"),
    overwrite = TRUE
  )
  writeLines('{"standards":[]}', file.path(root, "metadata/standards/shared-columns.json"))
  metadata <- list(
    metadata_version="1.0.0", object=list(schema="silver",database_schema="cycling_platform_silver",name="widget",type="table",ddl_path="sql/silver/010_create_widget.sql"),
    governance=list(owner="fixture",lifecycle="implemented",contract_path="docs/data-contracts/silver/widget.md",semantic_review_status="in_review",last_verified_date="2026-08-01"),
    physical_schema=contract_physical_schema_metadata(ddl_path),
    lineage=list(source_objects=list(),source_columns=list(),transformation_files=list("R/transforms/widget.R"),transformation_functions=list("fixture"),transformation_description="Fixture",authorship="generated",confidence="high",review_required=FALSE),
    data_quality=list(uniqueness_expectations=list("widget_id"),not_null_expectations=list("widget_id"),referential_integrity_expectations=list(),accepted_values=list(),implemented_validations=list()), human_todos=list())
  metadata_path <- file.path(root,"metadata/silver/widget.json")
  jsonlite::write_json(metadata,metadata_path,pretty=TRUE,auto_unbox=TRUE,null="null")
  list(root=root,metadata_path=metadata_path,contract_path=file.path(root,"docs/data-contracts/silver/widget.md"),ddl_path=ddl_path)
}

make_reference_contract_fixture <- function() {
  f <- make_contract_fixture()
  unlink(f$metadata_path)
  unlink(f$contract_path)
  unlink(f$ddl_path)
  ddl_path <- file.path(f$root, "sql/reference/010_create_widget.sql")
  contract_path <- file.path(f$root, "docs/data-contracts/reference/widget.md")
  metadata_path <- file.path(f$root, "metadata/reference/widget.json")
  writeLines(c("CREATE TABLE IF NOT EXISTS cycling_platform_reference.widget (", "  widget_id BIGINT NOT NULL,", "  PRIMARY KEY (widget_id)", ") ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 DEFAULT COLLATE utf8mb4_general_ci;"), ddl_path)
  writeLines(fixture_contract(), contract_path)
  metadata <- list(
    metadata_version="1.0.0", object=list(schema="reference",database_schema="cycling_platform_reference",name="widget",type="table",ddl_path="sql/reference/010_create_widget.sql"),
    governance=list(owner="fixture",lifecycle="implemented",contract_path="docs/data-contracts/reference/widget.md",semantic_review_status="in_review",last_verified_date="2026-08-05"),
    physical_schema=contract_physical_schema_metadata(ddl_path),
    lineage=list(source_objects=list(),source_columns=list(),transformation_files=list("R/transforms/widget.R"),transformation_functions=list("fixture"),transformation_description="Curated fixture",authorship="human_authored",confidence="high",review_required=FALSE),
    data_quality=list(uniqueness_expectations=list("widget_id"),not_null_expectations=list("widget_id"),referential_integrity_expectations=list(),accepted_values=list(),implemented_validations=list()),
    human_todos=list(list(id="REFERENCE-WIDGET-001",field="curation",severity="future",status="open",text="Review curation process.",resolution=NULL))
  )
  jsonlite::write_json(metadata,metadata_path,pretty=TRUE,auto_unbox=TRUE,null="null")
  list(root=f$root,metadata_path=metadata_path,contract_path=contract_path,ddl_path=ddl_path)
}
error_codes <- function(result) vapply(result$errors, `[[`, character(1), "code")

testthat::test_that("a complete fixture passes", { f <- make_contract_fixture(); testthat::expect_true(validate_data_contract_project(f$root,FALSE)$passed) })
testthat::test_that("missing metadata and contract are reported", {
  f <- make_contract_fixture(); unlink(f$metadata_path); testthat::expect_true("missing_metadata" %in% error_codes(validate_data_contract_project(f$root,FALSE)))
  f <- make_contract_fixture(); unlink(f$contract_path); testthat::expect_true("missing_contract" %in% error_codes(validate_data_contract_project(f$root,FALSE)))
})
testthat::test_that("DDL and metadata column drift is reported", {
  f <- make_contract_fixture(); writeLines(sub("label VARCHAR\\(50\\) NULL,","label VARCHAR(50) NULL,\n  extra_col INT NULL,",readLines(f$ddl_path)),f$ddl_path)
  testthat::expect_true("schema_mismatch" %in% error_codes(validate_data_contract_project(f$root,FALSE)))
  f <- make_contract_fixture(); m <- read_contract_json(f$metadata_path); m$physical_schema$columns <- c(m$physical_schema$columns,list(list(name="ghost",ordinal_position=3L,data_type="integer",raw_data_type="INT",nullable=TRUE,default=NULL,primary_key=FALSE,unique=FALSE))); jsonlite::write_json(m,f$metadata_path,auto_unbox=TRUE,null="null")
  testthat::expect_true("schema_mismatch" %in% error_codes(validate_data_contract_project(f$root,FALSE)))
})
testthat::test_that("type mismatch and missing section fail", {
  f <- make_contract_fixture(); m <- read_contract_json(f$metadata_path); m$physical_schema$columns[[1]]$data_type <- "varchar"; jsonlite::write_json(m,f$metadata_path,auto_unbox=TRUE,null="null")
  testthat::expect_true("schema_mismatch" %in% error_codes(validate_data_contract_project(f$root,FALSE)))
  f <- make_contract_fixture(); lines <- readLines(f$contract_path); writeLines(lines[lines != "## Purpose"],f$contract_path)
  testthat::expect_true("missing_section" %in% error_codes(validate_data_contract_project(f$root,FALSE)))
})
testthat::test_that("duplicate TODO and certified blocking TODO fail", {
  f <- make_contract_fixture(); m <- read_contract_json(f$metadata_path); todo <- list(id="SILVER-WIDGET-001",field="purpose",severity="blocking",status="open",text="Review",resolution=NULL); m$human_todos <- list(todo,todo); jsonlite::write_json(m,f$metadata_path,auto_unbox=TRUE,null="null")
  testthat::expect_true("duplicate_todo" %in% error_codes(validate_data_contract_project(f$root,FALSE)))
  m$human_todos <- list(todo); m$governance$lifecycle <- "certified"; m$governance$semantic_review_status <- "reviewed"; jsonlite::write_json(m,f$metadata_path,auto_unbox=TRUE,null="null")
  testthat::expect_true("lifecycle_todo" %in% error_codes(validate_data_contract_project(f$root,FALSE)))
})
testthat::test_that("orphan metadata and contract fail", {
  f <- make_contract_fixture(); m <- read_contract_json(f$metadata_path); m$object$name <- "orphan"; jsonlite::write_json(m,file.path(f$root,"metadata/silver/orphan.json"),auto_unbox=TRUE,null="null")
  testthat::expect_true("orphan_metadata" %in% error_codes(validate_data_contract_project(f$root,FALSE)))
  f <- make_contract_fixture(); writeLines(fixture_contract(),file.path(f$root,"docs/data-contracts/silver/orphan.md"))
  testthat::expect_true("orphan_contract" %in% error_codes(validate_data_contract_project(f$root,FALSE)))
})
testthat::test_that("repository contracts pass", { testthat::expect_true(validate_data_contract_project(contract_project_root,FALSE)$passed) })

testthat::test_that("Reference objects require contracts and metadata", {
  f <- make_reference_contract_fixture()
  result <- validate_data_contract_project(f$root, FALSE)
  testthat::expect_true(result$passed)
  testthat::expect_equal(result$counts$reference, 1L)

  unlink(f$metadata_path)
  testthat::expect_true("missing_metadata" %in% error_codes(validate_data_contract_project(f$root, FALSE)))
  f <- make_reference_contract_fixture()
  unlink(f$contract_path)
  testthat::expect_true("missing_contract" %in% error_codes(validate_data_contract_project(f$root, FALSE)))
})

testthat::test_that("orphan Reference governance files are detected", {
  f <- make_reference_contract_fixture()
  metadata <- read_contract_json(f$metadata_path)
  metadata$object$name <- "orphan"
  jsonlite::write_json(metadata,file.path(f$root,"metadata/reference/orphan.json"),auto_unbox=TRUE,null="null")
  testthat::expect_true("orphan_metadata" %in% error_codes(validate_data_contract_project(f$root,FALSE)))
  writeLines(fixture_contract(),file.path(f$root,"docs/data-contracts/reference/orphan.md"))
  testthat::expect_true("orphan_contract" %in% error_codes(validate_data_contract_project(f$root,FALSE)))
})

testthat::test_that("TODO categories and implementation alignment are governed", {
  f <- make_contract_fixture(); m <- read_contract_json(f$metadata_path)
  m$human_todos <- list(list(id="SILVER-WIDGET-001",field="mapping",category="not_a_category",severity="blocking",status="open",text="Review",resolution=NULL))
  jsonlite::write_json(m,f$metadata_path,auto_unbox=TRUE,null="null")
  testthat::expect_true("invalid_enum" %in% error_codes(validate_data_contract_project(f$root,FALSE)))

  f <- make_contract_fixture(); m <- read_contract_json(f$metadata_path)
  m$governance$lifecycle <- "certified"; m$governance$semantic_review_status <- "reviewed"; m$governance$alignment_status <- "review_required"
  m$human_todos <- list(list(id="SILVER-WIDGET-002",field="mapping",category="implementation_alignment",severity="blocking",status="open",text="Align implementation",resolution=NULL))
  jsonlite::write_json(m,f$metadata_path,auto_unbox=TRUE,null="null")
  codes <- error_codes(validate_data_contract_project(f$root,FALSE))
  testthat::expect_true(all(c("lifecycle_todo","lifecycle_alignment") %in% codes))
})

testthat::test_that("accepted and open future enhancements do not block certification", {
  f <- make_contract_fixture(); m <- read_contract_json(f$metadata_path)
  m$governance$lifecycle <- "certified"; m$governance$semantic_review_status <- "reviewed"; m$governance$alignment_status <- "aligned"
  m$human_todos <- list(
    list(id="SILVER-WIDGET-003",field="future",category="future_enhancement",severity="future",status="open",text="Future work",resolution=NULL),
    list(id="SILVER-WIDGET-004",field="limitation",category="future_enhancement",severity="future",status="accepted",text="Accepted future limitation",resolution="Deliberately deferred.")
  )
  jsonlite::write_json(m,f$metadata_path,auto_unbox=TRUE,null="null")
  testthat::expect_true(validate_data_contract_project(f$root,FALSE)$passed)
})

testthat::test_that("singleton column collections remain JSON arrays", {
  f <- make_contract_fixture()
  metadata <- read_contract_json(f$metadata_path)

  testthat::expect_type(metadata$physical_schema$primary_key, "list")
  testthat::expect_equal(
    unlist(metadata$physical_schema$primary_key, use.names = FALSE),
    "widget_id"
  )

  ddl <- c(
    "CREATE TABLE IF NOT EXISTS cycling_platform_silver.unique_widget (",
    "  widget_id BIGINT NOT NULL,",
    "  event_key VARCHAR(50) NOT NULL,",
    "  PRIMARY KEY (widget_id),",
    "  UNIQUE KEY uq_event_key (event_key)",
    ") ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 DEFAULT COLLATE utf8mb4_general_ci;"
  )
  ddl_path <- tempfile(fileext = ".sql")
  writeLines(ddl, ddl_path)
  physical <- contract_physical_schema_metadata(ddl_path)

  testthat::expect_type(physical$unique_constraints[[1]]$columns, "list")
  testthat::expect_equal(
    unlist(
      physical$unique_constraints[[1]]$columns,
      use.names = FALSE
    ),
    "event_key"
  )
})

testthat::test_that("declared JSON Schema rejects scalar column collections", {
  f <- make_contract_fixture()
  metadata <- read_contract_json(f$metadata_path)
  metadata$physical_schema$primary_key <- "widget_id"
  jsonlite::write_json(
    metadata,
    f$metadata_path,
    auto_unbox = TRUE,
    null = "null"
  )

  result <- validate_data_contract_project(f$root, FALSE)

  testthat::expect_false(result$passed)
  testthat::expect_true("json_schema_violation" %in% error_codes(result))
})

testthat::test_that("unsupported schema keywords fail visibly", {
  f <- make_contract_fixture()
  schema_path <- file.path(
    f$root,
    "metadata/schema/data-contract.schema.json"
  )
  schema <- read_contract_json(schema_path)
  schema$properties$metadata_version$future_keyword <- TRUE
  jsonlite::write_json(
    schema,
    schema_path,
    auto_unbox = TRUE,
    null = "null"
  )

  result <- validate_data_contract_project(f$root, FALSE)

  testthat::expect_false(result$passed)
  testthat::expect_true("unsupported_json_schema" %in% error_codes(result))
})

testthat::test_that("physical metadata generation is stable", {
  f <- make_contract_fixture()
  first <- contract_physical_schema_metadata(f$ddl_path)
  second <- contract_physical_schema_metadata(f$ddl_path)

  testthat::expect_identical(first, second)
})

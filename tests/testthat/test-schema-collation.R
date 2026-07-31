find_project_root <- function() {
  candidates <- c(".", "../..")
  candidate <- candidates[
    file.exists(file.path(candidates, "bootstrap.R"))
  ][1]

  normalizePath(candidate, mustWork = TRUE)
}

source(
  file.path(
    find_project_root(),
    "R",
    "validation",
    "validate_platform_completeness.R"
  )
)

testthat::test_that("all persistent CREATE TABLE DDL is deterministic", {
  project_root <- find_project_root()
  create_files <- list.files(
    file.path(project_root, "sql"),
    pattern = "create.*[.]sql$",
    recursive = TRUE,
    full.names = TRUE,
    ignore.case = TRUE
  )

  for (file in create_files) {
    sql <- paste(readLines(file, warn = FALSE), collapse = "\n")
    table_count <- lengths(
      gregexpr(
        "CREATE[[:space:]]+TABLE",
        sql,
        ignore.case = TRUE,
        perl = TRUE
      )
    )

    testthat::expect_equal(
      lengths(gregexpr("ENGINE=InnoDB", sql, fixed = TRUE)),
      table_count,
      info = file
    )
    testthat::expect_equal(
      lengths(gregexpr("DEFAULT CHARACTER SET utf8mb4", sql, fixed = TRUE)),
      table_count,
      info = file
    )
    testthat::expect_equal(
      lengths(gregexpr("DEFAULT COLLATE utf8mb4_general_ci", sql, fixed = TRUE)),
      table_count,
      info = file
    )
  }

  staging_source <- paste(
    readLines(
      file.path(
        project_root,
        "R",
        "transforms",
        "backfill_silver_activity_streams_local.R"
      ),
      warn = FALSE
    ),
    collapse = "\n"
  )

  testthat::expect_match(staging_source, "ENGINE=InnoDB", fixed = TRUE)
  testthat::expect_match(
    staging_source,
    "DEFAULT CHARACTER SET utf8mb4",
    fixed = TRUE
  )
  testthat::expect_match(
    staging_source,
    "DEFAULT COLLATE utf8mb4_general_ci",
    fixed = TRUE
  )
})

testthat::test_that("loaders cannot create persistent tables implicitly", {
  project_root <- find_project_root()
  r_files <- list.files(
    file.path(project_root, "R"),
    pattern = "[.][Rr]$",
    recursive = TRUE,
    full.names = TRUE
  )
  allowed_file <- normalizePath(
    file.path(
      project_root,
      "R",
      "database",
      "append_existing_table.R"
    )
  )

  direct_writers <- r_files[vapply(
    r_files,
    function(file) {
      text <- paste(readLines(file, warn = FALSE), collapse = "\n")
      grepl("DBI::dbWriteTable(", text, fixed = TRUE)
    },
    logical(1)
  )]

  testthat::expect_identical(
    normalizePath(direct_writers),
    allowed_file
  )
})

testthat::test_that("canonical migration covers databases and created tables", {
  project_root <- find_project_root()
  migration <- paste(
    readLines(
      file.path(
        project_root,
        "sql",
        "migrations",
        "001_enforce_canonical_collation.sql"
      ),
      warn = FALSE
    ),
    collapse = "\n"
  )

  for (schema in platform_database_schemas()) {
    testthat::expect_match(
      migration,
      paste("ALTER DATABASE", schema),
      fixed = TRUE
    )
  }

  create_files <- list.files(
    file.path(project_root, "sql"),
    pattern = "create.*[.]sql$",
    recursive = TRUE,
    full.names = TRUE,
    ignore.case = TRUE
  )
  create_sql <- paste(
    unlist(lapply(create_files, readLines, warn = FALSE)),
    collapse = "\n"
  )
  matches <- regmatches(
    create_sql,
    gregexpr(
      "cycling_platform_[a-z]+[.][a-z0-9_]+",
      create_sql,
      perl = TRUE
    )
  )[[1]]
  created_tables <- sort(unique(matches))

  for (table_name in created_tables) {
    testthat::expect_match(
      migration,
      paste("ALTER TABLE", table_name),
      fixed = TRUE
    )
  }
})

testthat::test_that("collation validation covers platform metadata", {
  testthat::expect_identical(
    platform_canonical_character_set(),
    "utf8mb4"
  )
  testthat::expect_identical(
    platform_canonical_collation(),
    "utf8mb4_general_ci"
  )

  query <- platform_collation_validation_query()

  testthat::expect_match(query, "information_schema.schemata", fixed = TRUE)
  testthat::expect_match(query, "information_schema.tables", fixed = TRUE)
  testthat::expect_match(query, "information_schema.columns", fixed = TRUE)
  testthat::expect_match(query, "information_schema.collations", fixed = TRUE)
  testthat::expect_match(
    query,
    paste(
      "table_collations.collation_name =",
      "tables.table_collation"
    ),
    fixed = TRUE
  )
  testthat::expect_false(
    grepl("character_set_name(", query, fixed = TRUE)
  )
  testthat::expect_match(query, "utf8mb4_general_ci", fixed = TRUE)
  testthat::expect_match(
    query,
    "WHERE schemata.schema_name IS NULL",
    fixed = TRUE
  )

  for (schema in platform_database_schemas()) {
    testthat::expect_match(query, schema, fixed = TRUE)
  }

  json_columns <- platform_json_columns()
  testthat::expect_equal(nrow(json_columns), 12L)
  testthat::expect_equal(nrow(unique(json_columns)), 12L)

  for (column_name in json_columns$column_name) {
    testthat::expect_match(query, column_name, fixed = TRUE)
  }
  testthat::expect_match(query, "utf8mb4_bin", fixed = TRUE)
  testthat::expect_match(
    query,
    "daily_respiratory_rate_payload",
    fixed = TRUE
  )
})

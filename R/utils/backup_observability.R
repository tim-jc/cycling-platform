backup_expected_databases <- function() {
  c(
    "cycling_platform_admin",
    "cycling_platform_raw",
    "cycling_platform_silver",
    "cycling_platform_gold"
  )
}

backup_freshness_status <- function(
  completed_at,
  now = Sys.time(),
  stale_hours = 30,
  critical_hours = 48
) {
  if (length(completed_at) == 0 || is.na(completed_at)) {
    return(list(status = "MISSING", age_hours = NA_real_))
  }

  age_hours <- as.numeric(
    difftime(now, completed_at, units = "hours")
  )

  status <- if (age_hours > critical_hours) {
    "CRITICAL"
  } else if (age_hours > stale_hours) {
    "STALE"
  } else {
    "HEALTHY"
  }

  list(
    status = status,
    age_hours = age_hours
  )
}

validate_backup_manifest <- function(manifest) {
  required_columns <- c(
    "database_name",
    "filename",
    "compressed_bytes",
    "uncompressed_bytes",
    "verified_at"
  )

  missing_columns <- setdiff(required_columns, names(manifest$files))

  if (length(missing_columns) > 0) {
    stop(
      "Backup manifest is missing columns: ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }

  expected <- sort(backup_expected_databases())
  actual <- sort(as.character(manifest$files$database_name))

  if (!identical(actual, expected)) {
    stop(
      "Backup manifest database coverage is invalid. Expected: ",
      paste(expected, collapse = ", "),
      "; received: ",
      paste(actual, collapse = ", "),
      call. = FALSE
    )
  }

  if (
    any(as.numeric(manifest$files$compressed_bytes) <= 0) ||
      any(as.numeric(manifest$files$uncompressed_bytes) <= 0)
  ) {
    stop("Backup manifest contains an empty dump file.", call. = FALSE)
  }

  invisible(manifest)
}

backup_run_metadata <- function(manifest) {
  validate_backup_manifest(manifest)

  list(
    status = "SUCCESS",
    started_at = manifest$started_at,
    completed_at = manifest$completed_at,
    backup_host = manifest$backup_host,
    source_host = manifest$source_host,
    run_prefix = manifest$run_prefix,
    expected_database_count = length(backup_expected_databases()),
    successful_database_count = nrow(manifest$files),
    duration_seconds = as.integer(difftime(
      manifest$completed_at,
      manifest$started_at,
      units = "secs"
    )),
    total_compressed_bytes = sum(
      as.numeric(manifest$files$compressed_bytes)
    )
  )
}

write_backup_success_artifact <- function(manifest, path) {
  validate_backup_manifest(manifest)

  artifact <- list(
    status = "SUCCESS",
    started_at = format(
      as.POSIXct(manifest$started_at, tz = "UTC"),
      "%Y-%m-%dT%H:%M:%SZ",
      tz = "UTC"
    ),
    completed_at = format(
      as.POSIXct(manifest$completed_at, tz = "UTC"),
      "%Y-%m-%dT%H:%M:%SZ",
      tz = "UTC"
    ),
    backup_host = manifest$backup_host,
    source_host = manifest$source_host,
    run_prefix = manifest$run_prefix,
    databases = as.character(manifest$files$database_name),
    files = purrr::pmap(
      manifest$files[
        c(
          "database_name",
          "filename",
          "compressed_bytes",
          "uncompressed_bytes",
          "verified_at"
        )
      ],
      \(database_name,
        filename,
        compressed_bytes,
        uncompressed_bytes,
        verified_at) {
        list(
          database_name = database_name,
          filename = basename(filename),
          compressed_bytes = as.numeric(compressed_bytes),
          uncompressed_bytes = as.numeric(uncompressed_bytes),
          verified_at = format(
            as.POSIXct(verified_at, tz = "UTC"),
            "%Y-%m-%dT%H:%M:%SZ",
            tz = "UTC"
          )
        )
      }
    )
  )

  temporary_path <- paste0(path, ".tmp")

  jsonlite::write_json(
    artifact,
    path = temporary_path,
    auto_unbox = TRUE,
    pretty = TRUE
  )

  if (!file.rename(temporary_path, path)) {
    unlink(temporary_path)
    stop("Unable to atomically update backup success artefact.", call. = FALSE)
  }

  invisible(path)
}

read_backup_success_artifact <- function(path) {
  if (!file.exists(path)) {
    return(list(status = "MISSING", artifact = NULL))
  }

  tryCatch(
    {
      artifact <- jsonlite::read_json(path, simplifyVector = TRUE)

      if (
        !identical(artifact$status, "SUCCESS") ||
          !identical(
            sort(as.character(artifact$databases)),
            sort(backup_expected_databases())
          )
      ) {
        stop("Backup success artefact has invalid content.")
      }

      list(status = "VALID", artifact = artifact)
    },
    error = function(e) {
      list(
        status = "MALFORMED",
        artifact = NULL,
        error = conditionMessage(e)
      )
    }
  )
}

ensure_backup_observability_tables <- function(
  connection,
  sql_dir = file.path("sql", "admin")
) {
  purrr::walk(
    file.path(
      sql_dir,
      c(
        "080_create_backup_run.sql",
        "081_create_backup_run_file.sql",
        "082_create_backup_reconciliation_run.sql"
      )
    ),
    execute_sql_file,
    connection = connection
  )

  invisible(NULL)
}

record_successful_backup_run <- function(connection, manifest) {
  run <- backup_run_metadata(manifest)

  DBI::dbWithTransaction(
    connection,
    {
      DBI::dbExecute(
        connection,
        "
          INSERT INTO cycling_platform_admin.backup_run (
            started_at,
            completed_at,
            status,
            backup_host,
            source_host,
            run_prefix,
            expected_database_count,
            successful_database_count,
            duration_seconds,
            total_compressed_bytes
          )
          VALUES (?, ?, 'SUCCESS', ?, ?, ?, ?, ?, ?, ?)
        ",
        params = list(
          manifest$started_at,
          manifest$completed_at,
          manifest$backup_host,
          manifest$source_host,
          manifest$run_prefix,
          run$expected_database_count,
          run$successful_database_count,
          run$duration_seconds,
          run$total_compressed_bytes
        )
      )

      backup_run_id <- DBI::dbGetQuery(
        connection,
        "SELECT LAST_INSERT_ID() AS backup_run_id"
      )$backup_run_id[[1]]

      purrr::pwalk(
        manifest$files,
        \(database_name,
          filename,
          compressed_bytes,
          uncompressed_bytes,
          verified_at,
          ...) {
          DBI::dbExecute(
            connection,
            "
              INSERT INTO cycling_platform_admin.backup_run_file (
                backup_run_id,
                database_name,
                filename,
                compressed_bytes,
                uncompressed_bytes,
                verified_at,
                status
              )
              VALUES (?, ?, ?, ?, ?, ?, 'VERIFIED')
            ",
            params = list(
              backup_run_id,
              database_name,
              basename(filename),
              as.numeric(compressed_bytes),
              as.numeric(uncompressed_bytes),
              verified_at
            )
          )
        }
      )

      backup_run_id
    }
  )
}

scan_backup_directory <- function(backup_dir) {
  paths <- list.files(
    backup_dir,
    pattern = "\\.sql\\.gz$",
    full.names = TRUE
  )

  if (length(paths) == 0) {
    return(data.frame(
      filename = character(),
      modified_at = as.POSIXct(character()),
      compressed_bytes = numeric()
    ))
  }

  info <- file.info(paths)

  data.frame(
    filename = basename(paths),
    modified_at = info$mtime,
    compressed_bytes = as.numeric(info$size),
    stringsAsFactors = FALSE
  )
}

reconcile_backup_inventory <- function(
  backup_runs,
  backup_run_files,
  disk_files,
  now = Sys.time(),
  retention_days = 30,
  managed_since = NULL
) {
  cutoff <- now - as.difftime(retention_days, units = "days")

  retained_runs <- backup_runs[
    backup_runs$status == "SUCCESS" &
      backup_runs$completed_at >= cutoff,
    ,
    drop = FALSE
  ]

  expected <- backup_expected_databases()

  expected_inventory <- merge(
    retained_runs[c("backup_run_id", "run_prefix")],
    data.frame(
      database_name = expected,
      stringsAsFactors = FALSE
    )
  )
  expected_inventory$filename <- if (nrow(expected_inventory) == 0) {
    character()
  } else {
    paste0(
      expected_inventory$run_prefix,
      "_",
      expected_inventory$database_name,
      ".sql.gz"
    )
  }

  missing_files <- setdiff(
    expected_inventory$filename,
    disk_files$filename
  )

  incomplete_run_ids <- unique(c(
    retained_runs$backup_run_id[
      vapply(
        retained_runs$backup_run_id,
        \(run_id) {
          schemas <- backup_run_files$database_name[
            backup_run_files$backup_run_id == run_id
          ]
          !identical(sort(schemas), sort(expected))
        },
        logical(1)
      )
    ],
    expected_inventory$backup_run_id[
      expected_inventory$filename %in% missing_files
    ]
  ))

  managed_disk_files <- disk_files

  if (!is.null(managed_since) && !is.na(managed_since)) {
    managed_disk_files <- managed_disk_files[
      managed_disk_files$modified_at >= managed_since,
      ,
      drop = FALSE
    ]
  }

  orphan_files <- setdiff(
    managed_disk_files$filename,
    backup_run_files$filename
  )

  expired_files <- disk_files$filename[
    disk_files$modified_at < cutoff
  ]

  expected_pattern <- paste(
    backup_expected_databases(),
    collapse = "|"
  )
  valid_pattern <- paste0(
    "^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{6}_(",
    expected_pattern,
    ")\\.sql\\.gz$"
  )
  unexpected_files <- managed_disk_files$filename[
    !grepl(valid_pattern, managed_disk_files$filename)
  ]

  issues <- list(
    missing_files = unname(missing_files),
    incomplete_backup_run_ids = as.character(incomplete_run_ids),
    orphan_files = unname(orphan_files),
    expired_files = unname(expired_files),
    unexpected_files = unname(unexpected_files)
  )

  issue_count <- sum(vapply(issues, length, integer(1)))

  list(
    status = if (issue_count == 0) "HEALTHY" else "WARNING",
    retained_run_count = nrow(retained_runs),
    retained_file_count = nrow(disk_files),
    missing_file_count = length(missing_files),
    incomplete_run_count = length(incomplete_run_ids),
    orphan_file_count = length(orphan_files),
    expired_file_count = length(expired_files),
    unexpected_file_count = length(unexpected_files),
    issues = issues
  )
}

record_backup_reconciliation <- function(
  connection,
  backup_dir,
  backup_host,
  retention_days,
  now = Sys.time()
) {
  started_at <- Sys.time()

  backup_runs <- DBI::dbGetQuery(
    connection,
    "
      SELECT
        backup_run_id,
        completed_at,
        status,
        run_prefix,
        created_at
      FROM cycling_platform_admin.backup_run
    "
  )

  backup_run_files <- DBI::dbGetQuery(
    connection,
    "
      SELECT
        backup_run_id,
        database_name,
        filename
      FROM cycling_platform_admin.backup_run_file
    "
  )

  managed_since <- if (nrow(backup_runs) == 0) {
    now
  } else {
    min(backup_runs$created_at)
  }

  result <- reconcile_backup_inventory(
    backup_runs = backup_runs,
    backup_run_files = backup_run_files,
    disk_files = scan_backup_directory(backup_dir),
    now = now,
    retention_days = retention_days,
    managed_since = managed_since
  )

  completed_at <- Sys.time()

  DBI::dbExecute(
    connection,
    "
      INSERT INTO cycling_platform_admin.backup_reconciliation_run (
        started_at,
        completed_at,
        status,
        backup_host,
        backup_directory,
        retention_days,
        retained_run_count,
        retained_file_count,
        missing_file_count,
        incomplete_run_count,
        orphan_file_count,
        expired_file_count,
        unexpected_file_count,
        issue_summary_json
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ",
    params = list(
      started_at,
      completed_at,
      result$status,
      backup_host,
      normalizePath(backup_dir, mustWork = FALSE),
      as.integer(retention_days),
      result$retained_run_count,
      result$retained_file_count,
      result$missing_file_count,
      result$incomplete_run_count,
      result$orphan_file_count,
      result$expired_file_count,
      result$unexpected_file_count,
      jsonlite::toJSON(result$issues, auto_unbox = TRUE)
    )
  )

  result
}

get_backup_health <- function(
  connection,
  now = Sys.time(),
  stale_hours = 30,
  critical_hours = 48
) {
  latest_success <- DBI::dbGetQuery(
    connection,
    "
      SELECT completed_at, source_host, run_prefix
      FROM cycling_platform_admin.backup_run
      WHERE status = 'SUCCESS'
      ORDER BY completed_at DESC, backup_run_id DESC
      LIMIT 1
    "
  )

  latest_reconciliation <- DBI::dbGetQuery(
    connection,
    "
      SELECT *
      FROM cycling_platform_admin.backup_reconciliation_run
      ORDER BY completed_at DESC, backup_reconciliation_run_id DESC
      LIMIT 1
    "
  )

  freshness <- backup_freshness_status(
    completed_at = if (nrow(latest_success) == 0) {
      as.POSIXct(NA)
    } else {
      latest_success$completed_at[[1]]
    },
    now = now,
    stale_hours = stale_hours,
    critical_hours = critical_hours
  )

  list(
    latest_success = latest_success,
    latest_reconciliation = latest_reconciliation,
    freshness_status = freshness$status,
    age_hours = freshness$age_hours
  )
}

format_backup_health_lines <- function(health, now = Sys.time()) {
  if (nrow(health$latest_success) == 0) {
    backup_line <- "Off-host backup: no successful backup recorded ⚠"
  } else {
    completed_at <- health$latest_success$completed_at[[1]]
    age_text <- if (health$age_hours < 1) {
      "<1h ago"
    } else {
      paste0(floor(health$age_hours), "h ago")
    }
    marker <- switch(
      health$freshness_status,
      HEALTHY = "✓",
      STALE = "⚠ STALE",
      CRITICAL = "⚠ CRITICAL",
      "⚠"
    )

    backup_line <- paste0(
      "Off-host backup: ",
      format(completed_at, "%d %b %H:%M"),
      " — ",
      age_text,
      " ",
      marker
    )
  }

  reconciliation <- health$latest_reconciliation

  retention_line <- if (nrow(reconciliation) == 0) {
    "Retention: no reconciliation recorded ⚠"
  } else if (identical(reconciliation$status[[1]], "HEALTHY")) {
    paste0(
      "Retention: ",
      reconciliation$retention_days[[1]],
      "-day set reconciled ✓"
    )
  } else {
    paste0(
      "Retention: WARNING — missing ",
      reconciliation$missing_file_count[[1]],
      ", incomplete ",
      reconciliation$incomplete_run_count[[1]],
      ", orphan ",
      reconciliation$orphan_file_count[[1]],
      ", expired ",
      reconciliation$expired_file_count[[1]],
      ", unexpected ",
      reconciliation$unexpected_file_count[[1]]
    )
  }

  c(backup_line, retention_line)
}

backup_health_notification_summary <- function(
  connection,
  config = list(),
  now = Sys.time()
) {
  stale_hours <- config$backups$freshness_stale_hours
  critical_hours <- config$backups$freshness_critical_hours

  if (is.null(stale_hours)) {
    stale_hours <- 30
  }

  if (is.null(critical_hours)) {
    critical_hours <- 48
  }

  tryCatch(
    {
      health <- get_backup_health(
        connection = connection,
        now = now,
        stale_hours = stale_hours,
        critical_hours = critical_hours
      )

      list(
        lines = format_backup_health_lines(health, now = now),
        freshness_status = health$freshness_status,
        reconciliation_status = if (
          nrow(health$latest_reconciliation) == 0
        ) {
          "MISSING"
        } else {
          health$latest_reconciliation$status[[1]]
        }
      )
    },
    error = function(e) {
      list(
        lines = paste0(
          "Backup observability: unavailable ⚠ — ",
          substr(conditionMessage(e), 1, 160)
        ),
        freshness_status = "UNKNOWN",
        reconciliation_status = "UNKNOWN"
      )
    }
  )
}

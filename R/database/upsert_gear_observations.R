#' Insert changed gear observations and touch identical observations
upsert_gear_observations <- function(connection, observations) {
  if (nrow(observations) == 0) {
    return(
      list(
        rows_inserted = 0L,
        rows_updated = 0L,
        rows_unchanged = 0L
      )
    )
  }

  existing <- DBI::dbGetQuery(
    connection,
    paste0(
      "SELECT gear_id, payload_hash ",
      "FROM cycling_platform_raw.gear_observations ",
      "WHERE (gear_id, payload_hash) IN (",
      paste(rep("(?, ?)", nrow(observations)), collapse = ", "),
      ")"
    ),
    params = as.list(as.vector(t(as.matrix(
      observations[c("gear_id", "payload_hash")]
    ))))
  )

  keys <- paste(observations$gear_id, observations$payload_hash, sep = "\r")
  existing_keys <- paste(existing$gear_id, existing$payload_hash, sep = "\r")
  is_existing <- keys %in% existing_keys

  if (any(!is_existing)) {
    DBI::dbWriteTable(
      connection,
      DBI::Id(schema = "cycling_platform_raw", table = "gear_observations"),
      observations[!is_existing, , drop = FALSE],
      append = TRUE
    )
  }

  if (any(is_existing)) {
    for (i in which(is_existing)) {
      DBI::dbExecute(
        connection,
        "
          UPDATE cycling_platform_raw.gear_observations
          SET
            run_id = ?,
            gear_type = CASE
              WHEN gear_type = 'unknown' THEN ?
              ELSE gear_type
            END,
            observed_in_current_collection = ?,
            last_observed_at = ?
          WHERE gear_id = ?
            AND payload_hash = ?
        ",
        params = list(
          observations$run_id[[i]],
          observations$gear_type[[i]],
          observations$observed_in_current_collection[[i]],
          observations$last_observed_at[[i]],
          observations$gear_id[[i]],
          observations$payload_hash[[i]]
        )
      )
    }
  }

  list(
    rows_inserted = sum(!is_existing),
    # Identical payloads only advance observation/control metadata. They are
    # reported separately rather than as source-record updates.
    rows_updated = 0L,
    rows_unchanged = sum(is_existing)
  )
}

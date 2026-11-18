canonical_geographic_activity_key <- function(activity_key) {
  if (inherits(activity_key, "integer64")) activity_key <- as.character(activity_key)
  if (is.integer(activity_key)) activity_key <- as.character(activity_key)
  if (!is.character(activity_key) || anyNA(activity_key) ||
      any(!grepl("^[1-9][0-9]*$", activity_key))) {
    stop(
      "activity_key must use integer64, integer, or canonical positive BIGINT text; ",
      "R doubles are not accepted.",
      call. = FALSE
    )
  }
  normalized <- as.character(bit64::as.integer64(activity_key))
  if (any(is.na(normalized)) || !identical(normalized, activity_key)) {
    stop("activity_key is outside the signed BIGINT range or non-canonical.", call. = FALSE)
  }
  normalized
}

empty_activity_tile_evidence <- function() {
  data.frame(
    activity_key = character(), tile_id = character(), zoom = integer(),
    tile_x = integer(), tile_y = integer(),
    qualifying_observation_count = integer(),
    qualifying_sample_references = character(),
    first_known_observed_at_utc = as.POSIXct(character(), tz = "UTC"),
    last_known_observed_at_utc = as.POSIXct(character(), tz = "UTC"),
    chronology_complete = logical(), stream_representation_id = character(),
    qualification_policy_version = character(), source_lineage = character(),
    representation_lineage = character(), stringsAsFactors = FALSE
  )
}

empty_lifetime_tile_visitation <- function() {
  data.frame(
    tile_id = character(), zoom = integer(), tile_x = integer(), tile_y = integer(),
    distinct_activity_count = integer(), activity_keys = character(),
    first_known_visit_at_utc = as.POSIXct(character(), tz = "UTC"),
    first_known_activity_key = character(),
    last_known_visit_at_utc = as.POSIXct(character(), tz = "UTC"),
    last_known_activity_key = character(), chronology_complete = logical(),
    qualification_policy_version = character(),
    stream_representation_ids = character(), stringsAsFactors = FALSE
  )
}

parse_geographic_observation_time <- function(value) {
  if (inherits(value, "POSIXct")) {
    return(as.POSIXct(as.numeric(value), origin = "1970-01-01", tz = "UTC"))
  }
  value <- as.character(value)
  missing <- is.na(value) | !nzchar(value)
  parsed <- as.POSIXct(rep(NA_character_, length(value)), tz = "UTC")
  if (any(!missing)) {
    parsed[!missing] <- as.POSIXct(
      value[!missing], format = "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC"
    )
  }
  if (any(!missing & is.na(parsed))) {
    stop("observed_at_utc must be missing or an explicit UTC timestamp.", call. = FALSE)
  }
  parsed
}

validate_geographic_observations <- function(observations) {
  required <- c(
    "activity_key", "stream_representation_id", "sample_index", "longitude",
    "latitude", "qualification_status", "full_resolution_eligible",
    "observed_at_utc", "qualification_policy_version", "source_lineage",
    "representation_lineage"
  )
  missing_columns <- setdiff(required, names(observations))
  if (length(missing_columns)) {
    stop(
      "Geographic observations are missing required columns: ",
      paste(missing_columns, collapse = ", "), ".", call. = FALSE
    )
  }
  observations <- observations[, required, drop = FALSE]
  observations$activity_key <- canonical_geographic_activity_key(
    observations$activity_key
  )
  character_columns <- c(
    "stream_representation_id", "qualification_status",
    "qualification_policy_version", "source_lineage", "representation_lineage"
  )
  for (column in character_columns) {
    observations[[column]] <- as.character(observations[[column]])
    if (anyNA(observations[[column]]) || any(!nzchar(observations[[column]]))) {
      stop(column, " must be non-missing and non-empty.", call. = FALSE)
    }
  }
  observations$qualification_status <- toupper(observations$qualification_status)
  if (any(!observations$qualification_status %in%
          c("ACCEPTED", "UNCERTAIN", "REJECTED"))) {
    stop("qualification_status contains an unsupported value.", call. = FALSE)
  }
  if (!is.logical(observations$full_resolution_eligible) ||
      anyNA(observations$full_resolution_eligible)) {
    stop("full_resolution_eligible must be non-missing logical evidence.", call. = FALSE)
  }
  if (!is.numeric(observations$sample_index) ||
      anyNA(observations$sample_index) ||
      any(!is.finite(observations$sample_index)) ||
      any(observations$sample_index < 0) ||
      any(observations$sample_index != floor(observations$sample_index))) {
    stop("sample_index must be a non-negative integer.", call. = FALSE)
  }
  observations$sample_index <- as.integer(observations$sample_index)
  observations$observed_at_utc <- parse_geographic_observation_time(
    observations$observed_at_utc
  )
  sample_key <- paste(
    observations$activity_key, observations$stream_representation_id,
    observations$sample_index, sep = "\r"
  )
  if (anyDuplicated(sample_key)) {
    stop("Geographic observation sample identity is duplicated.", call. = FALSE)
  }
  activity_groups <- split(seq_len(nrow(observations)), observations$activity_key)
  for (rows in activity_groups) {
    for (column in c(
      "stream_representation_id", "qualification_policy_version",
      "source_lineage", "representation_lineage"
    )) {
      if (length(unique(observations[[column]][rows])) != 1L) {
        stop(
          "One activity calculation cannot mix ", column,
          "; replace the activity representation as one unit.", call. = FALSE
        )
      }
    }
  }
  observations
}

classify_geographic_coordinate <- function(longitude, latitude) {
  if (length(longitude) != 1L || length(latitude) != 1L ||
      is.na(longitude) || is.na(latitude)) return("MISSING")
  if (!is.numeric(longitude) || !is.numeric(latitude) ||
      !is.finite(longitude) || !is.finite(latitude) ||
      longitude < -180 || longitude > 180 ||
      latitude <= -WEB_MERCATOR_LATITUDE_LIMIT ||
      latitude > WEB_MERCATOR_LATITUDE_LIMIT) return("MALFORMED")
  "VALID"
}

classify_geographic_observation <- function(coordinate_status, qualification,
                                            full_resolution) {
  if (identical(coordinate_status, "MISSING")) return("MISSING_COORDINATE")
  if (identical(coordinate_status, "MALFORMED")) return("MALFORMED_COORDINATE")
  if (!identical(qualification, "ACCEPTED")) return("NON_QUALIFYING_STATUS")
  if (!isTRUE(full_resolution)) return("NON_FULL_RESOLUTION")
  "QUALIFYING"
}

calculate_activity_tile_evidence <- function(observations) {
  observations <- validate_geographic_observations(observations)
  if (!nrow(observations)) {
    return(list(
      activity_tile_evidence = empty_activity_tile_evidence(),
      observation_outcomes = transform(
        observations,
        coordinate_status = character(),
        tile_evidence_eligible = logical(),
        evidence_outcome = character(),
        tile_id = character()
      )
    ))
  }
  coordinate_status <- vapply(seq_len(nrow(observations)), function(index) {
    classify_geographic_coordinate(
      observations$longitude[[index]], observations$latitude[[index]]
    )
  }, character(1))
  tile_evidence_eligible <- coordinate_status == "VALID" &
    observations$qualification_status == "ACCEPTED" &
    observations$full_resolution_eligible
  outcomes <- vapply(seq_len(nrow(observations)), function(index) {
    classify_geographic_observation(
      coordinate_status[[index]],
      observations$qualification_status[[index]],
      observations$full_resolution_eligible[[index]]
    )
  }, character(1))
  tile_id <- rep(NA_character_, nrow(observations))
  qualifying <- which(outcomes == "QUALIFYING")
  if (length(qualifying)) {
    tile_id[qualifying] <- vapply(qualifying, function(index) {
      longitude_latitude_to_explorer_tile(
        observations$longitude[[index]], observations$latitude[[index]]
      )$tile_id[[1L]]
    }, character(1))
  }
  observation_outcomes <- observations
  observation_outcomes$coordinate_status <- coordinate_status
  observation_outcomes$tile_evidence_eligible <- tile_evidence_eligible
  observation_outcomes$evidence_outcome <- outcomes
  observation_outcomes$tile_id <- tile_id
  if (!length(qualifying)) {
    return(list(
      activity_tile_evidence = empty_activity_tile_evidence(),
      observation_outcomes = observation_outcomes
    ))
  }

  accepted <- observation_outcomes[qualifying, , drop = FALSE]
  group_key <- paste(accepted$activity_key, accepted$tile_id, sep = "\r")
  groups <- split(seq_len(nrow(accepted)), group_key)
  rows <- lapply(groups, function(indexes) {
    group <- accepted[indexes, , drop = FALSE]
    group <- group[order(group$sample_index), , drop = FALSE]
    tile <- parse_explorer_tile_id(group$tile_id[[1L]])
    known_times <- group$observed_at_utc[!is.na(group$observed_at_utc)]
    data.frame(
      activity_key = group$activity_key[[1L]],
      tile_id = group$tile_id[[1L]],
      zoom = tile$zoom[[1L]], tile_x = tile$tile_x[[1L]], tile_y = tile$tile_y[[1L]],
      qualifying_observation_count = nrow(group),
      qualifying_sample_references = paste(group$sample_index, collapse = ","),
      first_known_observed_at_utc = if (length(known_times)) min(known_times) else as.POSIXct(NA, tz = "UTC"),
      last_known_observed_at_utc = if (length(known_times)) max(known_times) else as.POSIXct(NA, tz = "UTC"),
      chronology_complete = all(!is.na(group$observed_at_utc)),
      stream_representation_id = group$stream_representation_id[[1L]],
      qualification_policy_version = group$qualification_policy_version[[1L]],
      source_lineage = group$source_lineage[[1L]],
      representation_lineage = group$representation_lineage[[1L]],
      stringsAsFactors = FALSE
    )
  })
  evidence <- do.call(rbind, rows)
  evidence <- evidence[order(evidence$activity_key, evidence$tile_id), , drop = FALSE]
  rownames(evidence) <- NULL
  list(activity_tile_evidence = evidence, observation_outcomes = observation_outcomes)
}

validate_activity_tile_evidence <- function(activity_tile_evidence) {
  required <- names(empty_activity_tile_evidence())
  missing_columns <- setdiff(required, names(activity_tile_evidence))
  if (length(missing_columns)) {
    stop(
      "Activity tile evidence is missing required columns: ",
      paste(missing_columns, collapse = ", "), ".", call. = FALSE
    )
  }
  evidence <- activity_tile_evidence[, required, drop = FALSE]
  if (!nrow(evidence)) return(evidence)
  evidence$activity_key <- canonical_geographic_activity_key(evidence$activity_key)
  if (anyDuplicated(paste(evidence$activity_key, evidence$tile_id, sep = "\r"))) {
    stop("Activity tile evidence must be unique by activity and tile.", call. = FALSE)
  }
  parsed_tiles <- lapply(evidence$tile_id, parse_explorer_tile_id)
  parsed_zoom <- vapply(parsed_tiles, function(tile) tile$zoom[[1L]], integer(1))
  parsed_x <- vapply(parsed_tiles, function(tile) tile$tile_x[[1L]], integer(1))
  parsed_y <- vapply(parsed_tiles, function(tile) tile$tile_y[[1L]], integer(1))
  numeric_tile_columns <- c("zoom", "tile_x", "tile_y")
  if (any(!vapply(evidence[numeric_tile_columns], is.numeric, logical(1))) ||
      anyNA(evidence[numeric_tile_columns]) ||
      any(!is.finite(as.matrix(evidence[numeric_tile_columns]))) ||
      any(as.matrix(evidence[numeric_tile_columns]) !=
          floor(as.matrix(evidence[numeric_tile_columns])))) {
    stop("Stored tile components must be finite, non-missing integers.", call. = FALSE)
  }
  if (!identical(as.integer(evidence$zoom), parsed_zoom) ||
      !identical(as.integer(evidence$tile_x), parsed_x) ||
      !identical(as.integer(evidence$tile_y), parsed_y)) {
    stop("Stored zoom, tile_x and tile_y must agree with tile_id.", call. = FALSE)
  }
  counts <- evidence$qualifying_observation_count
  if (!is.numeric(counts) || anyNA(counts) || any(!is.finite(counts)) ||
      any(counts <= 0) || any(counts != floor(counts))) {
    stop("qualifying_observation_count must be a positive integer.", call. = FALSE)
  }
  references <- as.character(evidence$qualifying_sample_references)
  if (anyNA(references) || any(!grepl("^(0|[1-9][0-9]*)(,(0|[1-9][0-9]*))*$", references))) {
    stop("Qualifying sample references must be canonical non-negative indexes.", call. = FALSE)
  }
  reference_values <- strsplit(references, ",", fixed = TRUE)
  references_valid <- vapply(reference_values, function(values) {
    if (any(nchar(values) > 10L)) return(FALSE)
    indexes <- as.numeric(values)
    all(indexes <= .Machine$integer.max) &&
      !anyDuplicated(indexes) &&
      (length(indexes) == 1L || all(diff(indexes) > 0))
  }, logical(1))
  if (any(!references_valid) ||
      any(vapply(reference_values, length, integer(1)) != counts)) {
    stop(
      "Qualifying sample references must be unique, increasing and agree with the count.",
      call. = FALSE
    )
  }
  if (!inherits(evidence$first_known_observed_at_utc, "POSIXct") ||
      !inherits(evidence$last_known_observed_at_utc, "POSIXct")) {
    stop("Known activity-tile chronology must use POSIXct UTC instants.", call. = FALSE)
  }
  first_numeric <- as.numeric(evidence$first_known_observed_at_utc)
  last_numeric <- as.numeric(evidence$last_known_observed_at_utc)
  if (any(xor(is.na(first_numeric), is.na(last_numeric))) ||
      any(!is.na(first_numeric) & (!is.finite(first_numeric) |
          !is.finite(last_numeric) | first_numeric > last_numeric))) {
    stop("Known activity-tile chronology is missing, non-finite or out of order.", call. = FALSE)
  }
  if (!is.logical(evidence$chronology_complete) || anyNA(evidence$chronology_complete)) {
    stop("chronology_complete must be non-missing logical evidence.", call. = FALSE)
  }
  if (any(evidence$chronology_complete & is.na(first_numeric))) {
    stop("Complete chronology requires known first and last observation times.", call. = FALSE)
  }
  lineage_columns <- c(
    "stream_representation_id", "qualification_policy_version",
    "source_lineage", "representation_lineage"
  )
  for (column in lineage_columns) {
    evidence[[column]] <- as.character(evidence[[column]])
    if (anyNA(evidence[[column]]) || any(!nzchar(evidence[[column]]))) {
      stop(column, " must be non-missing and non-empty.", call. = FALSE)
    }
  }
  evidence$qualifying_observation_count <- as.integer(counts)
  evidence
}

aggregate_lifetime_tile_visitation <- function(activity_tile_evidence) {
  if (!nrow(activity_tile_evidence)) return(empty_lifetime_tile_visitation())
  evidence <- validate_activity_tile_evidence(activity_tile_evidence)
  policy_versions <- unique(evidence$qualification_policy_version)
  if (length(policy_versions) != 1L) {
    stop(
      "Lifetime tile visitation requires one coherent qualification policy; ",
      "mixed policy versions must be calculated separately.", call. = FALSE
    )
  }
  groups <- split(seq_len(nrow(evidence)), evidence$tile_id)
  rows <- lapply(groups, function(indexes) {
    group <- evidence[indexes, , drop = FALSE]
    tile <- parse_explorer_tile_id(group$tile_id[[1L]])
    known_first <- which(!is.na(group$first_known_observed_at_utc))
    known_last <- which(!is.na(group$last_known_observed_at_utc))
    first_index <- if (length(known_first)) known_first[order(
      group$first_known_observed_at_utc[known_first],
      bit64::as.integer64(group$activity_key[known_first])
    )][[1L]] else NA_integer_
    last_index <- if (length(known_last)) known_last[order(
      group$last_known_observed_at_utc[known_last],
      bit64::as.integer64(group$activity_key[known_last]), decreasing = TRUE
    )][[1L]] else NA_integer_
    sorted_keys <- as.character(sort(bit64::as.integer64(group$activity_key)))
    data.frame(
      tile_id = group$tile_id[[1L]], zoom = tile$zoom[[1L]],
      tile_x = tile$tile_x[[1L]], tile_y = tile$tile_y[[1L]],
      distinct_activity_count = length(unique(group$activity_key)),
      activity_keys = paste(sorted_keys, collapse = ","),
      first_known_visit_at_utc = if (!is.na(first_index)) group$first_known_observed_at_utc[[first_index]] else as.POSIXct(NA, tz = "UTC"),
      first_known_activity_key = if (!is.na(first_index)) group$activity_key[[first_index]] else NA_character_,
      last_known_visit_at_utc = if (!is.na(last_index)) group$last_known_observed_at_utc[[last_index]] else as.POSIXct(NA, tz = "UTC"),
      last_known_activity_key = if (!is.na(last_index)) group$activity_key[[last_index]] else NA_character_,
      chronology_complete = all(group$chronology_complete),
      qualification_policy_version = policy_versions[[1L]],
      stream_representation_ids = paste(sort(unique(group$stream_representation_id)), collapse = ","),
      stringsAsFactors = FALSE
    )
  })
  result <- do.call(rbind, rows)
  result <- result[order(result$tile_id), , drop = FALSE]
  rownames(result) <- NULL
  result
}

replace_activity_tile_evidence <- function(current_evidence, replacement_evidence,
                                           activity_key, withdraw = FALSE) {
  activity_key <- canonical_geographic_activity_key(activity_key)
  if (length(activity_key) != 1L) stop("One activity_key is required.", call. = FALSE)
  if (!is.logical(withdraw) || length(withdraw) != 1L || is.na(withdraw)) {
    stop("withdraw must be exactly one non-missing logical value.", call. = FALSE)
  }
  if (withdraw && nrow(replacement_evidence)) {
    stop("Withdrawal cannot include replacement evidence.", call. = FALSE)
  }
  if (nrow(current_evidence)) {
    current_evidence <- validate_activity_tile_evidence(current_evidence)
    current_evidence <- current_evidence[
      canonical_geographic_activity_key(current_evidence$activity_key) != activity_key,
      , drop = FALSE
    ]
  }
  if (!isTRUE(withdraw)) {
    if (nrow(replacement_evidence)) {
      replacement_evidence <- validate_activity_tile_evidence(replacement_evidence)
      if (any(replacement_evidence$activity_key != activity_key)) {
        stop("Replacement evidence must belong to the replaced activity.", call. = FALSE)
      }
    }
    current_evidence <- rbind(current_evidence, replacement_evidence)
  }
  if (!nrow(current_evidence)) return(empty_activity_tile_evidence())
  current_evidence <- current_evidence[
    order(current_evidence$activity_key, current_evidence$tile_id), , drop = FALSE
  ]
  rownames(current_evidence) <- NULL
  current_evidence
}

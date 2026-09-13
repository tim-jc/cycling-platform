operational_health_levels <- function() {
  c("HEALTHY", "UNKNOWN", "INFO", "WARNING", "CRITICAL")
}

operational_health_rank <- function(status) {
  match(toupper(status), operational_health_levels()) - 1L
}

roll_up_operational_health <- function(statuses) {
  statuses <- toupper(as.character(statuses))
  if (length(statuses) == 0L) return("UNKNOWN")
  if (any(!statuses %in% operational_health_levels())) {
    stop("Unsupported operational health status.", call. = FALSE)
  }
  operational_health_levels()[[max(operational_health_rank(statuses)) + 1L]]
}

classify_source_execution_health <- function(
  requirement, freshness_enabled, latest_status = NA_character_,
  success_age_hours = NA_real_, warning_after_hours = 30,
  critical_after_hours = 48
) {
  requirement <- toupper(requirement)
  if (!requirement %in% c("REQUIRED", "OPTIONAL")) {
    stop("Unsupported source entity requirement.", call. = FALSE)
  }
  if (is.na(latest_status)) {
    return(if (requirement == "REQUIRED" && isTRUE(freshness_enabled)) "UNKNOWN" else "INFO")
  }
  if (toupper(latest_status) != "SUCCESS") {
    return(if (requirement == "REQUIRED") "CRITICAL" else "WARNING")
  }
  if (!isTRUE(freshness_enabled)) return("HEALTHY")
  if (is.na(success_age_hours)) return("UNKNOWN")
  if (success_age_hours > critical_after_hours) {
    return(if (requirement == "REQUIRED") "CRITICAL" else "INFO")
  }
  if (success_age_hours > warning_after_hours) {
    return(if (requirement == "REQUIRED") "WARNING" else "INFO")
  }
  "HEALTHY"
}

classify_source_data_change <- function(current, previous) {
  if (is.na(current)) return("NO_SOURCE_DATA")
  if (is.na(previous)) return("FIRST_OBSERVATION")
  if (current > previous) return("ADVANCED")
  if (current == previous) return("UNCHANGED")
  "REGRESSED"
}

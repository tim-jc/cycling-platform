strava_activity_payload_object <- function(payload) {
  value <- jsonlite::fromJSON(payload, simplifyVector = FALSE)
  if (is.list(value) && is.null(names(value)) && length(value) == 1L && is.list(value[[1]])) value <- value[[1]]
  value
}

strava_activity_payload_boolean <- function(payload, field) {
  value <- strava_activity_payload_object(payload)[[field]]
  if (is.null(value) || length(value) != 1L || is.na(value)) return(NA)
  if (is.logical(value)) return(value)
  normalised <- tolower(as.character(value))
  if (normalised %in% c("true", "1")) return(TRUE)
  if (normalised %in% c("false", "0")) return(FALSE)
  NA
}

classify_lap_power_provenance <- function(
  average_power_watts,
  lap_is_device_watts,
  parent_power_source_type,
  parent_power_source_status,
  parent_is_measured_power,
  parent_is_power_record_eligible
) {
  input_lengths <- lengths(list(
    average_power_watts,
    lap_is_device_watts,
    parent_power_source_type,
    parent_power_source_status,
    parent_is_measured_power,
    parent_is_power_record_eligible
  ))
  output_length <- max(c(input_lengths, 1L))
  invalid_lengths <- input_lengths != 1L & input_lengths != output_length
  if (any(invalid_lengths)) {
    stop("Lap power provenance inputs must have length one or a common length.")
  }

  recycle <- function(value) rep_len(value, output_length)
  power <- recycle(average_power_watts)
  source_flag <- recycle(lap_is_device_watts)
  source_type <- recycle(parent_power_source_type)
  source_status <- recycle(parent_power_source_status)
  measured <- recycle(parent_is_measured_power)
  eligible <- recycle(parent_is_power_record_eligible)

  result <- rep("expected_agreement", output_length)
  result[is.na(power)] <- "no_lap_power"

  has_power <- !is.na(power)
  missing_context <- has_power & (
    is.na(source_type) | is.na(source_status) | is.na(measured) | is.na(eligible)
  )
  result[missing_context] <- "missing_canonical_context"

  governed_override <- has_power & !missing_context & !is.na(source_flag) &
    source_flag & (!measured | !eligible)
  result[governed_override] <- "governed_override"

  potential_inconsistency <- has_power & !missing_context & !is.na(source_flag) &
    !source_flag & measured
  result[potential_inconsistency] <- "potential_inconsistency"

  source_assertion_missing <- has_power & !missing_context & is.na(source_flag)
  result[source_assertion_missing] <- "source_assertion_missing"
  result
}

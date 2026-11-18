EXPLORER_TILE_ZOOM <- 14L
EXPLORER_TILE_COUNT <- 2L^EXPLORER_TILE_ZOOM
WEB_MERCATOR_LATITUDE_LIMIT <- 85.0511287798066
EXPLORER_TILE_SNAP_TOLERANCE <- 1e-9

geographic_scalar_number <- function(value, name) {
  if (length(value) != 1L || !is.numeric(value) || is.na(value)) {
    stop(name, " must be one non-missing numeric value.", call. = FALSE)
  }
  if (!is.finite(value)) {
    stop(name, " must be finite.", call. = FALSE)
  }
  as.numeric(value)
}

snap_projected_tile_boundary <- function(value) {
  nearest <- round(value)
  if (abs(value - nearest) <= EXPLORER_TILE_SNAP_TOLERANCE) nearest else value
}

validate_explorer_coordinate <- function(longitude, latitude) {
  longitude <- geographic_scalar_number(longitude, "longitude")
  latitude <- geographic_scalar_number(latitude, "latitude")
  if (longitude < -180 || longitude > 180) {
    stop("longitude must be within [-180, 180].", call. = FALSE)
  }
  if (latitude <= -WEB_MERCATOR_LATITUDE_LIMIT ||
      latitude > WEB_MERCATOR_LATITUDE_LIMIT) {
    stop(
      "latitude must be within the half-open Web Mercator range ",
      "(-85.0511287798066, 85.0511287798066].",
      call. = FALSE
    )
  }
  c(longitude = longitude, latitude = latitude)
}

longitude_latitude_to_explorer_tile <- function(longitude, latitude) {
  coordinate <- validate_explorer_coordinate(longitude, latitude)
  longitude <- coordinate[["longitude"]]
  latitude <- coordinate[["latitude"]]
  if (identical(longitude, 180)) longitude <- -180

  projected_x <- (longitude + 180) / 360 * EXPLORER_TILE_COUNT
  latitude_radians <- latitude * pi / 180
  projected_y <- (1 - asinh(tan(latitude_radians)) / pi) / 2 *
    EXPLORER_TILE_COUNT
  projected_x <- snap_projected_tile_boundary(projected_x)
  projected_y <- snap_projected_tile_boundary(projected_y)
  x <- as.integer(floor(projected_x))
  y <- as.integer(floor(projected_y))
  if (x == EXPLORER_TILE_COUNT) x <- 0L
  if (x < 0L || x >= EXPLORER_TILE_COUNT ||
      y < 0L || y >= EXPLORER_TILE_COUNT) {
    stop("coordinate does not resolve to a supported Explorer tile.", call. = FALSE)
  }
  data.frame(
    zoom = EXPLORER_TILE_ZOOM,
    tile_x = x,
    tile_y = y,
    tile_id = explorer_tile_id(x, y),
    stringsAsFactors = FALSE
  )
}

validate_explorer_tile_components <- function(zoom, tile_x, tile_y) {
  values <- list(zoom = zoom, tile_x = tile_x, tile_y = tile_y)
  values <- lapply(names(values), function(name) {
    value <- geographic_scalar_number(values[[name]], name)
    if (value != floor(value)) {
      stop(name, " must be an integer.", call. = FALSE)
    }
    value
  })
  names(values) <- c("zoom", "tile_x", "tile_y")
  if (values$zoom != EXPLORER_TILE_ZOOM ||
      values$tile_x < 0L || values$tile_x >= EXPLORER_TILE_COUNT ||
      values$tile_y < 0L || values$tile_y >= EXPLORER_TILE_COUNT) {
    stop("unsupported Explorer tile reference.", call. = FALSE)
  }
  values <- lapply(values, as.integer)
  values
}

explorer_tile_id <- function(tile_x, tile_y, zoom = EXPLORER_TILE_ZOOM) {
  tile <- validate_explorer_tile_components(zoom, tile_x, tile_y)
  paste(tile$zoom, tile$tile_x, tile$tile_y, sep = "/")
}

parse_explorer_tile_id <- function(tile_id) {
  if (length(tile_id) != 1L || !is.character(tile_id) || is.na(tile_id) ||
      !grepl("^[0-9]+/[0-9]+/[0-9]+$", tile_id)) {
    stop("tile_id must be a canonical z/x/y identifier.", call. = FALSE)
  }
  parts <- strsplit(tile_id, "/", fixed = TRUE)[[1L]]
  canonical_part <- function(value) {
    identical(value, "0") || grepl("^[1-9][0-9]*$", value)
  }
  if (!all(vapply(parts, canonical_part, logical(1)))) {
    stop("tile_id must use canonical integer formatting.", call. = FALSE)
  }
  if (!identical(parts[[1L]], as.character(EXPLORER_TILE_ZOOM)) ||
      nchar(parts[[2L]]) > 5L || nchar(parts[[3L]]) > 5L) {
    stop("unsupported Explorer tile reference.", call. = FALSE)
  }
  tile <- validate_explorer_tile_components(
    EXPLORER_TILE_ZOOM, as.integer(parts[[2L]]), as.integer(parts[[3L]])
  )
  canonical <- explorer_tile_id(tile$tile_x, tile$tile_y, tile$zoom)
  if (!identical(tile_id, canonical)) {
    stop("tile_id must use canonical integer formatting.", call. = FALSE)
  }
  data.frame(
    zoom = tile$zoom,
    tile_x = tile$tile_x,
    tile_y = tile$tile_y,
    tile_id = canonical,
    stringsAsFactors = FALSE
  )
}

validate_explorer_tile_id <- function(tile_id) {
  parse_explorer_tile_id(tile_id)
  invisible(TRUE)
}

explorer_tile_latitude_edge <- function(tile_y, zoom = EXPLORER_TILE_ZOOM) {
  atan(sinh(pi * (1 - 2 * tile_y / (2^zoom)))) * 180 / pi
}

explorer_tile_bounds <- function(tile_id) {
  tile <- parse_explorer_tile_id(tile_id)
  n <- 2^tile$zoom[[1L]]
  x <- tile$tile_x[[1L]]
  y <- tile$tile_y[[1L]]
  data.frame(
    west = x / n * 360 - 180,
    south = explorer_tile_latitude_edge(y + 1L, tile$zoom[[1L]]),
    east = (x + 1L) / n * 360 - 180,
    north = explorer_tile_latitude_edge(y, tile$zoom[[1L]]),
    stringsAsFactors = FALSE
  )
}

explorer_tile_centre <- function(tile_id) {
  tile <- parse_explorer_tile_id(tile_id)
  n <- 2^tile$zoom[[1L]]
  data.frame(
    longitude = (tile$tile_x[[1L]] + 0.5) / n * 360 - 180,
    latitude = explorer_tile_latitude_edge(
      tile$tile_y[[1L]] + 0.5, tile$zoom[[1L]]
    ),
    stringsAsFactors = FALSE
  )
}

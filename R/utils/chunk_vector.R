#' Chunk Vector
#'
#' Split a vector into ordered chunks.
#'
#' @param x Vector to split.
#' @param chunk_size Positive integer chunk size.
#'
#' @return List of vector chunks.
chunk_vector <- function(
  x,
  chunk_size
) {
  stopifnot(chunk_size > 0)

  if (length(x) == 0) {
    return(list())
  }

  chunk_index <- ceiling(
    seq_along(x) / chunk_size
  )

  split(
    x,
    chunk_index
  )
}

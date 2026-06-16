#' Load config
#'
#' Loads in configuration details specified in platform.yml
#' @return list parsed from config/platform.yml
load_config <- function() {
  yaml::read_yaml("config/platform.yml")
}

#' Load config
#'
#' Loads in configuration details specified in platform.yml
#' @param config_path File path of config yaml file.
#' @return List parsed from config/platform.yml.
load_config <- function(config_path = "config/platform.yml") {
  yaml::read_yaml(config_path)
}

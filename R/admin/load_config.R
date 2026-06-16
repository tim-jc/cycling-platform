#' Load config
load_config <- function() {
  yaml::read_yaml("config/platform.yml")
}

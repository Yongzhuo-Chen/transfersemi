# Shared helpers for repository-rooted simulation entry points.

simulation_repo_root <- function() {
  file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(file_arg) != 1L) {
    stop("Simulation entry points must be run with Rscript.", call. = FALSE)
  }

  script_path <- normalizePath(
    sub("^--file=", "", file_arg[[1L]]),
    winslash = "/",
    mustWork = TRUE
  )
  normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = TRUE)
}

source_transfersemi <- function(repo_root) {
  source_dir <- file.path(repo_root, "TransferSemi", "R")
  source_files <- sort(list.files(source_dir, pattern = "\\.[Rr]$", full.names = TRUE))
  if (length(source_files) == 0L) {
    stop("No TransferSemi R source files were found in ", source_dir, call. = FALSE)
  }
  invisible(lapply(source_files, sys.source, envir = .GlobalEnv))
}

simulation_output_root <- function(repo_root) {
  configured_root <- Sys.getenv("TRANSFERSEMI_OUTPUT_ROOT", unset = "")
  if (!nzchar(configured_root)) {
    return(ensure_output_dir(file.path(repo_root, "semi-transfer-learning")))
  }

  is_absolute <- grepl("^(/|[A-Za-z]:[/\\\\]|\\\\\\\\)", configured_root)
  resolved_root <- if (is_absolute) {
    path.expand(configured_root)
  } else {
    file.path(repo_root, configured_root)
  }
  ensure_output_dir(resolved_root)
}

parse_numeric_cli <- function(argument_names, usage) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) != length(argument_names)) {
    stop("Usage: ", usage, call. = FALSE)
  }

  values <- suppressWarnings(as.numeric(args))
  if (any(!is.finite(values))) {
    stop(
      "All arguments must be finite numeric values. Usage: ",
      usage,
      call. = FALSE
    )
  }
  stats::setNames(as.list(values), argument_names)
}

require_integer_argument <- function(value, name, minimum = 1L) {
  if (length(value) != 1L || value != floor(value) || value < minimum) {
    stop(
      sprintf("%s must be an integer greater than or equal to %d.", name, minimum),
      call. = FALSE
    )
  }
  invisible(value)
}

validate_common_simulation_args <- function(values, minimum_dim = 1L) {
  require_integer_argument(values$n, "n")
  require_integer_argument(values$seed, "seed")
  require_integer_argument(values$dim, "dim", minimum = minimum_dim)
  if (values$similarity < 0 || values$similarity > 1) {
    stop("similarity must lie in [0, 1].", call. = FALSE)
  }
  invisible(values)
}

ensure_output_dir <- function(path) {
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(path)) {
    stop("Could not create output directory: ", path, call. = FALSE)
  }
  path
}

seed_reproducibly <- function(seed) {
  seed <- as.integer(seed)
  set.seed(seed)
  torch::torch_manual_seed(seed)
  invisible(torch::torch_device("cpu"))
}

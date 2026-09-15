resolve_visualization_path <- function(repo_root, value) {
  expanded <- path.expand(value)
  is_absolute <- grepl("^(/|[A-Za-z]:[/\\\\]|\\\\\\\\)", expanded)
  if (is_absolute) expanded else file.path(repo_root, expanded)
}

visualization_config <- function(repo_root, notebook_name) {
  mode <- Sys.getenv("TRANSFERSEMI_VISUALIZATION_MODE", unset = "previous")
  if (!mode %in% c("previous", "simulated")) {
    stop(
      "TRANSFERSEMI_VISUALIZATION_MODE must be 'previous' or 'simulated'.",
      call. = FALSE
    )
  }

  default_figure_collection <- if (mode == "previous") {
    "figures_previous_results"
  } else {
    "figures"
  }
  figure_collection <- Sys.getenv(
    "TRANSFERSEMI_FIGURE_COLLECTION",
    unset = default_figure_collection
  )
  if (!grepl("^[A-Za-z0-9._-]+$", figure_collection)) {
    stop(
      "TRANSFERSEMI_FIGURE_COLLECTION must be a directory name, not a path.",
      call. = FALSE
    )
  }

  results_root <- resolve_visualization_path(
    repo_root,
    Sys.getenv("TRANSFERSEMI_RESULTS_ROOT", unset = "semi-transfer-learning")
  )

  visualization_data_file <- resolve_visualization_path(
    repo_root,
    Sys.getenv(
      "TRANSFERSEMI_MSE_VISUALIZATION_DATA",
      unset = file.path(results_root, "MSE_visualization_data.rds")
    )
  )

  list(
    mode = mode,
    figure_collection = figure_collection,
    results_root = results_root,
    visualization_data_file = visualization_data_file,
    derived_dir = file.path(
      repo_root, "outputs", "derived", figure_collection, notebook_name
    ),
    figure_dir = file.path(
      repo_root, "outputs", figure_collection, notebook_name
    )
  )
}

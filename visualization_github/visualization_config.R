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

visualization_grid <- function() {
  expand.grid(
    n = c(100L, 200L),
    similarity = seq(0, 1, by = 0.2),
    KEEP.OUT.ATTRS = FALSE
  )
}

require_result_directory <- function(path, label) {
  if (!dir.exists(path)) {
    stop("Missing ", label, " result directory: ", path, call. = FALSE)
  }
  path
}

read_plm_seed_directory <- function(path, n, similarity) {
  files <- list.files(
    path,
    pattern = "^mse_data_seed_[0-9]+[.]rds$",
    full.names = TRUE
  )
  if (!length(files)) {
    stop("No PLM seed-level result files found in: ", path, call. = FALSE)
  }

  rows <- lapply(files, function(file) {
    data <- as.data.frame(readRDS(file), check.names = FALSE)
    task_columns <- paste0("Task", 1:5)
    missing_columns <- setdiff(task_columns, names(data))
    if (length(missing_columns)) {
      stop(
        "Missing task columns in ", file, ": ",
        paste(missing_columns, collapse = ", "),
        call. = FALSE
      )
    }
    methods <- rownames(data)
    if (is.null(methods) || any(!nzchar(methods))) {
      stop("Missing method row names in: ", file, call. = FALSE)
    }
    seed <- as.integer(sub(
      "^mse_data_seed_([0-9]+)[.]rds$", "\\1", basename(file)
    ))
    tasks <- data[task_columns]
    data.frame(
      max_value = apply(tasks, 1L, max),
      mean_value = rowMeans(tasks),
      median_value = apply(tasks, 1L, median),
      task1 = tasks[[1L]], task2 = tasks[[2L]], task3 = tasks[[3L]],
      task4 = tasks[[4L]], task5 = tasks[[5L]],
      seed = seed,
      method = methods,
      n = n,
      similarity = similarity,
      stringsAsFactors = FALSE,
      row.names = NULL
    )
  })
  do.call(rbind, rows)
}

read_previous_plm_results <- function(results_root) {
  # Use the same saved aggregate MSE_Mean_combined_plot_sm.pdf's PLM panel
  # uses, rather than re-reading results_5_dim8 directly. The two are nearly
  # identical (11,997 vs 11,995 rows); the aggregate is preferred here so the
  # heatmap matches that panel's exact PLM source.
  aggregate_file <- file.path(results_root, "MSE_visualization_data.rds")
  if (!file.exists(aggregate_file)) {
    stop("Missing previous PLM aggregate: ", aggregate_file, call. = FALSE)
  }
  visualization_data <- readRDS(aggregate_file)
  if (!"plm" %in% names(visualization_data)) {
    stop(
      "MSE_visualization_data.rds does not contain a 'plm' component.",
      call. = FALSE
    )
  }
  result <- as.data.frame(visualization_data$plm, check.names = FALSE)
  rownames(result) <- NULL
  message(
    "Read previous PLM results from the saved aggregate ", aggregate_file,
    " (", nrow(result), " rows) -- the same source MSE_Mean_combined_plot_sm.pdf uses."
  )
  result
}

read_tabular_saved_result <- function(file, preferred_names) {
  environment <- new.env(parent = baseenv())
  loaded <- load(file, envir = environment)
  candidates <- c(intersect(preferred_names, loaded), setdiff(loaded, "seed"))
  for (name in unique(candidates)) {
    value <- environment[[name]]
    if (is.data.frame(value) || is.matrix(value)) {
      return(as.data.frame(value, check.names = FALSE))
    }
  }
  stop("No tabular result object found in: ", file, call. = FALSE)
}

read_previous_rdata_results <- function(
    root, directory_name, preferred_names, label) {
  require_result_directory(root, paste("previous", label))
  rows <- list()
  row_index <- 0L
  grid <- visualization_grid()
  for (index in seq_len(nrow(grid))) {
    setting <- grid[index, ]
    path <- file.path(root, directory_name(setting$n, setting$similarity))
    require_result_directory(path, paste("previous", label, "setting"))
    files <- list.files(path, pattern = "^[0-9]+[.]RData$", full.names = TRUE)
    if (!length(files)) {
      stop("No ", label, " seed-level result files found in: ", path, call. = FALSE)
    }
    for (file in files) {
      data <- read_tabular_saved_result(file, preferred_names)
      task_columns <- paste0("Task", 1:5)
      missing_columns <- setdiff(task_columns, names(data))
      if (length(missing_columns)) {
        stop(
          "Missing task columns in ", file, ": ",
          paste(missing_columns, collapse = ", "),
          call. = FALSE
        )
      }
      methods <- rownames(data)
      if (is.null(methods) || any(!nzchar(methods))) {
        stop("Missing method row names in: ", file, call. = FALSE)
      }
      seed <- as.integer(tools::file_path_sans_ext(basename(file)))
      row_index <- row_index + 1L
      rows[[row_index]] <- data.frame(
        Method = methods,
        data[task_columns],
        n = setting$n,
        similarity = setting$similarity,
        seed = seed,
        stringsAsFactors = FALSE,
        row.names = NULL,
        check.names = FALSE
      )
    }
  }
  result <- do.call(rbind, rows)
  rownames(result) <- NULL
  message(
    "Read previous ", label, " seed files directly from ", root,
    " (", nrow(result), " rows)."
  )
  result
}

read_previous_cate_results <- function(results_root) {
  # CATE_dim8 only has 10 seeds per setting. The historical, complete-seed
  # (100-199 per setting) CATE data was never shipped as raw per-seed files
  # in this checkout -- it only survives inside the precomputed aggregate,
  # which is the same source MSE_Mean_combined_plot_sm.pdf's CATE panel uses.
  # Read it from there instead of CATE_dim8 so the heatmap matches that panel.
  aggregate_file <- file.path(results_root, "MSE_visualization_data.rds")
  if (!file.exists(aggregate_file)) {
    stop("Missing previous CATE aggregate: ", aggregate_file, call. = FALSE)
  }
  visualization_data <- readRDS(aggregate_file)
  if (!"cate" %in% names(visualization_data)) {
    stop(
      "MSE_visualization_data.rds does not contain a 'cate' component.",
      call. = FALSE
    )
  }
  result <- as.data.frame(visualization_data$cate, check.names = FALSE)
  rownames(result) <- NULL
  message(
    "Read previous CATE results from the saved aggregate ", aggregate_file,
    " (", nrow(result), " rows) -- the same source MSE_Mean_combined_plot_sm.pdf uses."
  )
  result
}

read_previous_dr_results <- function(results_root) {
  read_previous_rdata_results(
    file.path(results_root, "DR_9_new"),
    function(n, similarity) paste0("mse_n_", n, "_simi_", similarity),
    c("result", "res"),
    "DR"
  )
}

read_previous_visualization_results <- function(config) {
  list(
    plm = read_previous_plm_results(config$results_root),
    cate = read_previous_cate_results(config$results_root),
    dr = read_previous_dr_results(config$results_root)
  )
}

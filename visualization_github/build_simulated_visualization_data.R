#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L || length(args) > 2L) {
  stop(
    "Usage: Rscript visualization_github/build_simulated_visualization_data.R ",
    "<simulation-results-root> [output-rds]",
    call. = FALSE
  )
}

results_root <- normalizePath(path.expand(args[[1L]]), mustWork = TRUE)
output_file <- if (length(args) == 2L) {
  path.expand(args[[2L]])
} else {
  file.path(results_root, "MSE_visualization_data.rds")
}

parse_setting <- function(name, pattern, label) {
  match <- regmatches(name, regexec(pattern, name, perl = TRUE))[[1L]]
  if (length(match) != 3L) {
    stop("Cannot parse ", label, " setting directory: ", name, call. = FALSE)
  }
  list(n = as.integer(match[[2L]]), similarity = as.numeric(match[[3L]]))
}

require_task_columns <- function(data, file) {
  task_columns <- paste0("Task", 1:5)
  missing <- setdiff(task_columns, names(data))
  if (length(missing)) {
    stop(
      "Missing task columns in ", file, ": ", paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  task_columns
}

require_method_names <- function(data, file) {
  methods <- rownames(data)
  if (is.null(methods) || any(!nzchar(methods))) {
    stop("Missing method row names in ", file, call. = FALSE)
  }
  methods
}

read_saved_object <- function(file, preferred_name) {
  environment <- new.env(parent = baseenv())
  loaded <- load(file, envir = environment)
  selected <- if (preferred_name %in% loaded) preferred_name else loaded[[1L]]
  value <- environment[[selected]]
  if (!is.data.frame(value) && !is.matrix(value)) {
    stop("No tabular result object found in ", file, call. = FALSE)
  }
  as.data.frame(value, check.names = FALSE)
}

collect_plm <- function(root) {
  if (!dir.exists(root)) stop("Missing simulated PLM results: ", root, call. = FALSE)
  setting_dirs <- list.dirs(root, recursive = FALSE, full.names = TRUE)
  setting_dirs <- setting_dirs[grepl(
    "^mse_n_[0-9]+_simi_[0-9.]+lambda_len100$", basename(setting_dirs)
  )]
  rows <- list()
  row_index <- 0L
  for (directory in setting_dirs) {
    setting <- parse_setting(
      basename(directory),
      "^mse_n_([0-9]+)_simi_([0-9.]+)lambda_len100$",
      "PLM"
    )
    files <- list.files(
      directory,
      pattern = "^mse_data_seed_[0-9]+[.]rds$",
      full.names = TRUE
    )
    for (file in files) {
      seed <- as.integer(sub("^mse_data_seed_([0-9]+)[.]rds$", "\\1", basename(file)))
      data <- as.data.frame(readRDS(file), check.names = FALSE)
      task_columns <- require_task_columns(data, file)
      methods <- require_method_names(data, file)
      tasks <- data[task_columns]
      row_index <- row_index + 1L
      rows[[row_index]] <- data.frame(
        max_value = apply(tasks, 1L, max, na.rm = TRUE),
        mean_value = rowMeans(tasks, na.rm = TRUE),
        median_value = apply(tasks, 1L, median, na.rm = TRUE),
        task1 = tasks[[1L]], task2 = tasks[[2L]], task3 = tasks[[3L]],
        task4 = tasks[[4L]], task5 = tasks[[5L]],
        seed = seed,
        method = methods,
        n = setting$n,
        similarity = setting$similarity,
        stringsAsFactors = FALSE,
        row.names = NULL
      )
    }
  }
  if (!length(rows)) stop("No simulated PLM result files found under ", root, call. = FALSE)
  do.call(rbind, rows)
}

collect_rdata_results <- function(root, directory_pattern, result_name, label) {
  if (!dir.exists(root)) stop("Missing simulated ", label, " results: ", root, call. = FALSE)
  setting_dirs <- list.dirs(root, recursive = FALSE, full.names = TRUE)
  setting_dirs <- setting_dirs[grepl(directory_pattern, basename(setting_dirs))]
  rows <- list()
  row_index <- 0L
  for (directory in setting_dirs) {
    setting <- parse_setting(basename(directory), directory_pattern, label)
    files <- list.files(directory, pattern = "^[0-9]+[.]RData$", full.names = TRUE)
    for (file in files) {
      seed <- as.integer(tools::file_path_sans_ext(basename(file)))
      data <- read_saved_object(file, result_name)
      task_columns <- require_task_columns(data, file)
      methods <- require_method_names(data, file)
      row_index <- row_index + 1L
      rows[[row_index]] <- data.frame(
        Method = methods,
        data[task_columns],
        seed = seed,
        n = setting$n,
        similarity = setting$similarity,
        stringsAsFactors = FALSE,
        row.names = NULL,
        check.names = FALSE
      )
    }
  }
  if (!length(rows)) stop("No simulated ", label, " result files found under ", root, call. = FALSE)
  do.call(rbind, rows)
}

validate_grid <- function(data, label) {
  expected <- expand.grid(
    n = c(100L, 200L),
    similarity = seq(0, 1, by = 0.2),
    KEEP.OUT.ATTRS = FALSE
  )
  observed <- unique(data[c("n", "similarity")])
  key <- function(x) paste(x$n, sprintf("%.1f", x$similarity), sep = ":")
  missing <- setdiff(key(expected), key(observed))
  if (length(missing)) {
    stop(
      "The simulated ", label, " grid is incomplete; missing n:similarity settings: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
}

visualization_data <- list(
  plm = collect_plm(file.path(results_root, "results_11_dim8")),
  cate = collect_rdata_results(
    file.path(results_root, "CATE_dim8"),
    "^CATE_([0-9]+)_([0-9.]+)$",
    "result",
    "CATE"
  ),
  dr = collect_rdata_results(
    file.path(results_root, "DR_9_new"),
    "^mse_n_([0-9]+)_simi_([0-9.]+)$",
    "res",
    "DR"
  )
)

for (label in names(visualization_data)) {
  validate_grid(visualization_data[[label]], toupper(label))
}

dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
saveRDS(visualization_data, output_file)
message("Created simulated-result visualization data: ", output_file)

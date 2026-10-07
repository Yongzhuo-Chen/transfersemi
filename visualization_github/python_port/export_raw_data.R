#!/usr/bin/env Rscript
# Exports the raw simulation/real-data inputs used by the previous-results
# notebooks into tidy CSVs, so the companion Jupyter notebook
# (regenerate_figures.ipynb) can reproduce the same figures in pure Python
# without needing to read R's .rds/.RData binary formats directly.
#
# Run with:  module load R/4.3 && Rscript visualization_github/python_port/export_raw_data.R

find_repo_root <- function(start = getwd()) {
  current <- normalizePath(start, mustWork = TRUE)
  repeat {
    if (file.exists(file.path(current, "TransferSemi", "DESCRIPTION")) &&
        dir.exists(file.path(current, "visualization_github"))) return(current)
    parent <- dirname(current)
    if (identical(parent, current)) break
    current <- parent
  }
  stop("Cannot locate the repository root.", call. = FALSE)
}

repo_root <- find_repo_root()
results_root <- file.path(repo_root, "semi-transfer-learning")
out_dir <- file.path(repo_root, "outputs", "python_notebook_data")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

cat("Repo root:", repo_root, "\n")
cat("Output dir:", out_dir, "\n\n")

read_saved_object <- function(file, preferred_name) {
  environment <- new.env(parent = baseenv())
  loaded <- load(file, envir = environment)
  selected <- if (preferred_name %in% loaded) preferred_name else loaded[[1L]]
  as.data.frame(environment[[selected]], check.names = FALSE)
}

## ---------------------------------------------------------------
## 1. PLM raw results (results_11_dim8) -> plm_raw.csv
## ---------------------------------------------------------------
export_plm <- function() {
  root <- file.path(results_root, "results_11_dim8")
  setting_dirs <- list.dirs(root, recursive = FALSE, full.names = TRUE)
  setting_dirs <- setting_dirs[grepl(
    "^mse_n_[0-9]+_simi_[0-9.]+lambda_len100$", basename(setting_dirs)
  )]
  rows <- list()
  for (directory in setting_dirs) {
    m <- regmatches(basename(directory), regexec(
      "^mse_n_([0-9]+)_simi_([0-9.]+)lambda_len100$", basename(directory)
    ))[[1L]]
    n <- as.integer(m[[2]]); similarity <- as.numeric(m[[3]])
    files <- list.files(directory, pattern = "^mse_data_seed_[0-9]+[.]rds$", full.names = TRUE)
    for (file in files) {
      seed <- as.integer(sub("^mse_data_seed_([0-9]+)[.]rds$", "\\1", basename(file)))
      d <- as.data.frame(readRDS(file), check.names = FALSE)
      tasks <- d[paste0("Task", 1:5)]
      rows[[length(rows) + 1L]] <- data.frame(
        n = n, similarity = similarity, seed = seed,
        method = rownames(d),
        task1 = tasks[[1]], task2 = tasks[[2]], task3 = tasks[[3]],
        task4 = tasks[[4]], task5 = tasks[[5]],
        mean_value = rowMeans(tasks, na.rm = TRUE),
        max_value = apply(tasks, 1L, max, na.rm = TRUE),
        median_value = apply(tasks, 1L, median, na.rm = TRUE),
        stringsAsFactors = FALSE, row.names = NULL
      )
    }
  }
  out <- do.call(rbind, rows)
  write.csv(out, file.path(out_dir, "plm_raw.csv"), row.names = FALSE)
  cat("plm_raw.csv:", nrow(out), "rows\n")
}

## ---------------------------------------------------------------
## 2/3. CATE (CATE_dim8) and DR (DR_9_new) raw results
## ---------------------------------------------------------------
export_rdata_results <- function(subdir, dir_pattern, preferred_name, out_name) {
  root <- file.path(results_root, subdir)
  setting_dirs <- list.dirs(root, recursive = FALSE, full.names = TRUE)
  setting_dirs <- setting_dirs[grepl(dir_pattern, basename(setting_dirs))]
  rows <- list()
  for (directory in setting_dirs) {
    m <- regmatches(basename(directory), regexec(dir_pattern, basename(directory)))[[1L]]
    n <- as.integer(m[[2]]); similarity <- as.numeric(m[[3]])
    files <- list.files(directory, pattern = "\\.RData$", full.names = TRUE)
    for (file in files) {
      seed <- as.integer(tools::file_path_sans_ext(basename(file)))
      d <- read_saved_object(file, preferred_name)
      tasks <- d[paste0("Task", 1:5)]
      rows[[length(rows) + 1L]] <- data.frame(
        n = n, similarity = similarity, seed = seed,
        Method = rownames(d),
        Task1 = tasks[[1]], Task2 = tasks[[2]], Task3 = tasks[[3]],
        Task4 = tasks[[4]], Task5 = tasks[[5]],
        stringsAsFactors = FALSE, row.names = NULL
      )
    }
  }
  out <- do.call(rbind, rows)
  write.csv(out, file.path(out_dir, out_name), row.names = FALSE)
  cat(out_name, ":", nrow(out), "rows\n")
}

## ---------------------------------------------------------------
## 4/5. Fine-tuning MSE collections (only the NonPara_Transfer_Tuned row)
## ---------------------------------------------------------------
export_finetune_mse <- function(root, dir_pattern, method_label, out_name) {
  files <- list.files(root, pattern = "^mse_data_seed_[0-9]+[.]rds$",
                       recursive = TRUE, full.names = TRUE)
  rows <- list()
  for (path in files) {
    setting <- basename(dirname(path))
    m <- regmatches(setting, regexec(dir_pattern, setting))[[1L]]
    if (length(m) != 3L) next
    n <- as.integer(m[[2]]); similarity <- as.numeric(m[[3]])
    value <- readRDS(path)
    row_idx <- match("NonPara_Transfer_Tuned", rownames(value))
    if (is.na(row_idx)) stop("Missing NonPara_Transfer_Tuned in ", path)
    task_cols <- grep("^Task[0-9]+$", names(value), value = TRUE)
    task_mse <- as.numeric(value[row_idx, task_cols])
    seed <- as.integer(sub("^mse_data_seed_([0-9]+)[.]rds$", "\\1", basename(path)))
    rows[[length(rows) + 1L]] <- data.frame(
      seed = seed, n = n, similarity = similarity, Method = method_label,
      mean_mse = mean(task_mse, na.rm = TRUE), maximum_mse = max(task_mse, na.rm = TRUE)
    )
  }
  out <- do.call(rbind, rows)
  out <- out[round(out$similarity, 1) %in% c(0, 0.2, 0.4, 0.6, 0.8, 1), ]
  out <- out[is.finite(out$mean_mse) & is.finite(out$maximum_mse), ]
  write.csv(out, file.path(out_dir, out_name), row.names = FALSE)
  cat(out_name, ":", nrow(out), "rows\n")
}

## ---------------------------------------------------------------
## 6/7. Fine-tuning runtime collections
## ---------------------------------------------------------------
export_finetune_runtime <- function(root, file_pattern, dir_pattern, runtime_col, seed_prefix, method_label, out_name) {
  files <- list.files(root, pattern = file_pattern, recursive = TRUE, full.names = TRUE)
  rows <- list()
  for (path in files) {
    setting <- basename(dirname(path))
    m <- regmatches(setting, regexec(dir_pattern, setting))[[1L]]
    if (length(m) != 3L) next
    n <- as.integer(m[[2]]); similarity <- as.numeric(m[[3]])
    value <- read.csv(path, stringsAsFactors = FALSE)
    seed <- as.integer(sub(paste0("^", seed_prefix, "_([0-9]+).*$"), "\\1", basename(path)))
    rows[[length(rows) + 1L]] <- data.frame(
      seed = seed, n = n, similarity = similarity, Method = method_label,
      runtime_minutes = as.numeric(value[[runtime_col]][[1]]) / 60
    )
  }
  out <- do.call(rbind, rows)
  out <- out[round(out$similarity, 1) %in% c(0, 0.2, 0.4, 0.6, 0.8, 1), ]
  out <- out[is.finite(out$runtime_minutes) & out$runtime_minutes > 0, ]
  write.csv(out, file.path(out_dir, out_name), row.names = FALSE)
  cat(out_name, ":", nrow(out), "rows\n")
}

## ---------------------------------------------------------------
## 8. Real-data pseudo-data results (real_data/result_real_data)
## ---------------------------------------------------------------
export_real_data <- function() {
  data_folder <- file.path(repo_root, "real_data", "result_real_data")
  files <- list.files(data_folder, pattern = "^[0-9]+\\.RData$", full.names = TRUE)
  rows <- list()
  for (file in files) {
    env <- new.env()
    load(file, envir = env)
    res <- env$res
    seed <- as.numeric(tools::file_path_sans_ext(basename(file)))
    model_names <- head(names(res), 9)
    for (model_name in model_names) {
      model_result <- res[[model_name]]
      n_subgroups <- if (model_name == "eval_pool") 1L else length(model_result)
      for (i in seq_len(n_subgroups)) {
        if (model_name == "eval_pool") {
          mse_list <- model_result$mse; value_list <- model_result$value_function
        } else {
          mse_list <- model_result[[i]]$mse; value_list <- model_result[[i]]$value_function
        }
        for (j in seq_along(mse_list)) {
          rows[[length(rows) + 1L]] <- data.frame(
            Model = model_name, Subgroup = i,
            MSE = mse_list[[j]][[1]], Value_Function = value_list[[j]][[1]],
            seed = seed
          )
        }
      }
    }
  }
  out <- do.call(rbind, rows)
  write.csv(out, file.path(out_dir, "real_data_raw.csv"), row.names = FALSE)
  cat("real_data_raw.csv:", nrow(out), "rows\n")
}

## ---------------------------------------------------------------
## 9. Real-data correlation inputs (real_data/corr)
## ---------------------------------------------------------------
export_real_corr <- function() {
  corr_dir <- file.path(repo_root, "real_data", "corr")
  X <- readRDS(file.path(corr_dir, "X.Rdata"))

  safe_cor <- function(x, y) {
    x <- suppressWarnings(as.numeric(x)); y <- suppressWarnings(as.numeric(y))
    n <- min(length(x), length(y)); if (n <= 1L) return(NA_real_)
    x <- x[seq_len(n)]; y <- y[seq_len(n)]
    ok <- is.finite(x) & is.finite(y); if (sum(ok) <= 1L) return(NA_real_)
    if (isTRUE(all.equal(sd(x[ok]), 0)) || isTRUE(all.equal(sd(y[ok]), 0))) return(NA_real_)
    suppressWarnings(cor(x[ok], y[ok], method = "pearson"))
  }

  models <- c("para_transfer_tuned", "no_transfer", "semipara_transfer_tuned",
              "Sai_transfer", "ARMUL", "pERM")
  rows_all <- list()      # ALL columns of X[[index]] per model/task (the "_con" block)
  rows_categorical <- list()  # only columns NOT in continuous_vars (the second block)
  continuous_vars <- c("bar1tot", "ben1tot", "se1tot", "sus1tot", "fear1tot", "fatal1tot", "know1tot")

  for (model in models) {
    for (index in 1:4) {
      a <- readRDS(file.path(corr_dir, paste0("eval_", model, "_w_race.Rdata")))
      target <- if (model == "Sai_transfer") a[[index]]$f_hat else {
        (a[[index]]$f_hat[[1]][[1]] + a[[index]]$f_hat[[2]][[1]]) / 2
      }
      cols_all <- X[[index]]
      corr_all <- vapply(seq_len(ncol(cols_all)), function(i) safe_cor(cols_all[, i], target), numeric(1))
      rows_all[[length(rows_all) + 1L]] <- data.frame(
        Variable = colnames(cols_all), Correlation = corr_all, n_task = index, model = model
      )

      cols_cat <- X[[index]][, setdiff(colnames(X[[index]]), continuous_vars), drop = FALSE]
      corr_cat <- vapply(seq_len(ncol(cols_cat)), function(i) safe_cor(cols_cat[, i], target), numeric(1))
      rows_categorical[[length(rows_categorical) + 1L]] <- data.frame(
        Variable = colnames(cols_cat), Correlation = corr_cat, n_task = index, model = model
      )
    }
  }

  b <- readRDS(file.path(corr_dir, "eval_pool_w_race.Rdata"))
  pool_target <- (b$f_hat[[1]][[1]] + b$f_hat[[2]][[1]]) / 2
  X_pool <- readRDS(file.path(corr_dir, "pool_X.Rdata"))
  corr_pool_all <- vapply(seq_len(ncol(X_pool)), function(i) safe_cor(X_pool[, i], pool_target), numeric(1))
  rows_all[[length(rows_all) + 1L]] <- data.frame(
    Variable = colnames(X_pool), Correlation = corr_pool_all, n_task = 0L, model = "pool"
  )
  cols_pool_cat <- X_pool[, setdiff(colnames(X_pool), continuous_vars), drop = FALSE]
  corr_pool_cat <- vapply(seq_len(ncol(cols_pool_cat)), function(i) safe_cor(cols_pool_cat[, i], pool_target), numeric(1))
  rows_categorical[[length(rows_categorical) + 1L]] <- data.frame(
    Variable = colnames(cols_pool_cat), Correlation = corr_pool_cat, n_task = 0L, model = "pool"
  )

  write.csv(do.call(rbind, rows_all), file.path(out_dir, "real_corr_all_columns.csv"), row.names = FALSE)
  write.csv(do.call(rbind, rows_categorical), file.path(out_dir, "real_corr_categorical_only.csv"), row.names = FALSE)
  cat("real_corr_all_columns.csv / real_corr_categorical_only.csv written\n")
}

export_plm()
export_rdata_results("CATE_dim8", "^CATE_([0-9]+)_([0-9.]+)$", "result", "cate_raw.csv")
export_rdata_results("DR_9_new", "^mse_n_([0-9]+)_simi_([0-9.]+)$", "res", "dr_raw.csv")

export_finetune_mse(
  file.path(results_root, "results_5_dim8"), "^mse_n_([0-9]+)_simi_([0-9.]+)$",
  "Late Fusion with Nuisance", "finetune_implemented_mse.csv"
)
export_finetune_mse(
  file.path(results_root, "results_finetune_new8"), "^mse_n_([0-9]+)_simi_([0-9.]+)$",
  "Global Fine-tuned Late Fusion with Nuisance", "finetune_global_mse.csv"
)
export_finetune_runtime(
  file.path(results_root, "results_11_dim8"), "^time_data_seed_[0-9]+[.]csv$",
  "^_n_([0-9]+)_simi_([0-9.]+)lambda_len100$", "time_nonpar_transfer", "time_data_seed",
  "Implemented", "finetune_implemented_runtime.csv"
)
export_finetune_runtime(
  file.path(results_root, "results_finetune_new_time8"), "^time_seed_[0-9]+[.]csv$",
  "^mse_n_([0-9]+)_simi_([0-9.]+)$", "runtime_sec", "time_seed",
  "Global Fine-tuned", "finetune_global_runtime.csv"
)

export_real_data()
export_real_corr()

cat("\nDone.\n")

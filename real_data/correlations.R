set.seed(1)

library(glmnet)
library(ggplot2)
library(reshape2)

############################################################
# Helpers
############################################################
convert_age_one_hot <- function(combined) {
  combined$age_category <- ifelse(combined$age <= 55, "Below_55", "Above_55")
  age_one_hot <- model.matrix(~ age_category - 1, data = combined)
  combined_one_hot <- cbind(
    combined[, !colnames(combined) %in% c("age", "age_category")],
    age_one_hot
  )
  combined_one_hot
}

drop_redundant_cols <- function(mat) {
  drop_cols <- c("age_categoryBelow_55", "yearmamsum0")
  keep_cols <- setdiff(colnames(mat), drop_cols)
  mat[, keep_cols, drop = FALSE]
}

plot_evaluation <- function(eval_input) {
  mse_values <- sapply(eval_input, function(x) {
    mse_obj <- x$mse
    if (!is.list(mse_obj)) mse_obj <- list(mse_obj)
    sapply(mse_obj, function(y) if (is.list(y)) y[[1]] else y)
  }) |> colMeans()

  value_function_values <- sapply(eval_input, function(x) {
    vf_obj <- x$value_function
    if (!is.list(vf_obj)) vf_obj <- list(vf_obj)
    sapply(vf_obj, function(y) if (is.list(y)) y[[1]] else y)
  }) |> colMeans()

  df <- data.frame(
    Index = rep(1:length(mse_values), times = 2),
    Type = c(rep("MSE", length(mse_values)),
             rep("Value Function", length(mse_values))),
    Value = c(mse_values, value_function_values)
  )

  df_mse <- df[df$Type == "MSE", ]
  df_value_function <- df[df$Type == "Value Function", ]
  scale_factor <- max(df_value_function$Value) / max(df_mse$Value)

  ggplot() +
    geom_line(data = df_mse, aes(x = Index, y = Value, color = "MSE"), linewidth = 1) +
    geom_point(data = df_mse, aes(x = Index, y = Value, color = "MSE"), size = 3) +
    geom_line(data = df_value_function,
              aes(x = Index, y = Value / scale_factor, color = "Value Function"),
              linewidth = 1, linetype = "dashed") +
    geom_point(data = df_value_function,
               aes(x = Index, y = Value / scale_factor, color = "Value Function"),
               size = 3, shape = 16) +
    scale_y_continuous(
      name = "MSE",
      sec.axis = sec_axis(~ . * scale_factor, name = "Value Function")
    ) +
    scale_color_manual(
      values = c("MSE" = "blue", "Value Function" = "green"),
      name = "Type"
    ) +
    labs(title = "MSE and Value Function", x = "Index") +
    theme_minimal() +
    theme(
      plot.title = element_text(hjust = 0.5),
      axis.title.y.left = element_text(color = "blue"),
      axis.title.y.right = element_text(color = "green"),
      legend.position = "top"
    )
}

format_result <- function(nested_list) {
  do.call(rbind, lapply(nested_list, function(item) {
    mse_values <- unlist(item$mse)
    value_function_values <- unlist(item$value_function)
    data.frame(
      mse_1 = mse_values[1],
      mse_2 = mse_values[2],
      value_function_1 = value_function_values[1],
      value_function_2 = value_function_values[2]
    )
  }))
}

format_list_to_df <- function(eval_list) {
  result_df <- data.frame(
    Model = character(),
    Subgroup = integer(),
    MSE = numeric(),
    Value_Function = numeric(),
    stringsAsFactors = FALSE
  )

  for (model_name in names(eval_list)) {
    for (i in seq_along(eval_list[[model_name]])) {
      mse_list <- eval_list[[model_name]][[i]]$mse
      value_list <- eval_list[[model_name]][[i]]$value_function

      if (!is.list(mse_list)) mse_list <- list(mse_list)
      if (!is.list(value_list)) value_list <- list(value_list)

      for (j in seq_along(mse_list)) {
        mse_value <- if (is.list(mse_list[[j]])) mse_list[[j]][[1]] else mse_list[[j]]
        value_function_value <- if (is.list(value_list[[j]])) value_list[[j]][[1]] else value_list[[j]]

        result_df <- rbind(result_df, data.frame(
          Model = model_name,
          Subgroup = i,
          MSE = mse_value,
          Value_Function = value_function_value
        ))
      }
    }
  }

  result_df
}

split_data <- function(data, train_ratio = 1.0) {
  train_indices <- seq_len(nrow(data))
  train_data <- data[train_indices, ]
  test_data <- train_data
  list(train = train_data, test = test_data)
}

split_into_tasks <- function(data, n_tasks = 5) {
  task_indices <- sample(rep(1:n_tasks, length.out = nrow(data)))
  lapply(1:n_tasks, function(t) data[task_indices == t, ])
}

normalize_min_max <- function(x, eps = 1e-12) {
  x <- as.numeric(x)
  if (all(is.na(x))) return(x)

  mn <- min(x, na.rm = TRUE)
  mx <- max(x, na.rm = TRUE)

  if (!is.finite(mn) || !is.finite(mx)) return(rep(NA_real_, length(x)))
  if (mx - mn < eps) {
    out <- rep(0, length(x))
    out[is.na(x)] <- NA_real_
    return(out)
  }

  (x - mn) / (mx - mn)
}

estimate_cate <- function(X_mat, beta_vec) {
  p <- ncol(X_mat)
  beta_D <- beta_vec[p + 1]
  gamma <- beta_vec[(p + 2):(2 * p + 1)]
  as.numeric(beta_D + X_mat %*% gamma)
}

safe_cor <- function(x, y) {
  x <- as.numeric(x)
  y <- as.numeric(y)
  min_len <- min(length(x), length(y))
  if (min_len <= 1) return(NA_real_)
  suppressWarnings(cor(x[1:min_len], y[1:min_len], use = "complete.obs"))
}

############################################################
# Source external code
############################################################
source("prediction_per_site.R")

original_wd <- getwd()
setwd("../TransferSemi/R")
files <- list.files(pattern = "\\.R$")
invisible(lapply(files, source))
setwd(original_wd)
############################################################
# Load data
############################################################
cape <- read.csv("cape_pseudo.csv")
ninr <- read.csv("ninr_pseudo.csv")

cape_copy <- cape[, colnames(cape)[-c(4, 5, 6, 7, 10, 11)]]
ninr_copy <- ninr[, colnames(cape)[-c(4, 5, 6, 7, 10, 11)]]

cape_train <- split_into_tasks(cape_copy, 2)
cape_test <- cape_train

ninr_train <- split_into_tasks(ninr_copy, 2)
ninr_test <- ninr_train

combined <- rbind(cape_copy, ninr_copy)
combined <- na.omit(combined)

############################################################
# Build per-task data
############################################################
X <- vector("list", 4)
D <- vector("list", 4)
Y <- vector("list", 4)
X_test <- vector("list", 4)
D_test <- vector("list", 4)
Y_test <- vector("list", 4)

ntask <- 4

for (index in 1:2) {
  cape_train[[index]] <- cape_train[[index]][apply(cape_train[[index]], 1, function(row) all(!is.na(row))), ]

  X_age <- convert_age_one_hot(cape_train[[index]][, c(5:19)])
  X_age$yearmamsum <- as.factor(X_age$yearmamsum)
  yearmamsum_one_hot <- model.matrix(~ yearmamsum - 1, data = X_age)

  X_tmp <- cbind(
    X_age[, !colnames(X_age) %in% c("yearmamsum")],
    yearmamsum_one_hot
  )
  X[[index]] <- drop_redundant_cols(X_tmp)

  D[[index]] <- cape_train[[index]][, 3]
  Y[[index]] <- cape_train[[index]][, 4]
}

for (index in 3:4) {
  ninr_train[[index - 2]] <- ninr_train[[index - 2]][apply(ninr_train[[index - 2]], 1, function(row) all(!is.na(row))), ]

  X_age <- convert_age_one_hot(ninr_train[[index - 2]][, c(5:19)])
  X_age$yearmamsum <- as.factor(X_age$yearmamsum)
  yearmamsum_one_hot <- model.matrix(~ yearmamsum - 1, data = X_age)

  X_tmp <- cbind(
    X_age[, !colnames(X_age) %in% c("yearmamsum")],
    yearmamsum_one_hot
  )
  X[[index]] <- drop_redundant_cols(X_tmp)

  D[[index]] <- as.numeric(ninr_train[[index - 2]][, 3])
  Y[[index]] <- as.numeric(ninr_train[[index - 2]][, 4])
}

for (index in 1:4) {
  X[[index]] <- as.matrix(X[[index]])
}
for (index in 1:4) {
  X_test[[index]] <- X[[index]]
  D_test[[index]] <- D[[index]]
  Y_test[[index]] <- Y[[index]]
}
############################################################
# Preprocess features
############################################################
split_index <- vector("list", ntask)
fit_each_site <- vector("list", ntask)

continuous_variables <- c("bar1tot", "ben1tot", "se1tot", "sus1tot", "fear1tot", "fatal1tot", "know1tot")



X_colnames <- colnames(X[[1]])
selected_colnames <- X_colnames[!X_colnames %in% c("married", "stage", "fdrhistory", "bar1tot")]
continuous_variables <- continuous_variables[!(continuous_variables %in% c("bar1tot"))]

for (index in 1:ntask) {
  X_test[[index]] <- X_test[[index]][, selected_colnames, drop = FALSE]
  X[[index]] <- X[[index]][, selected_colnames, drop = FALSE]
}

for (index in 1:ntask) {
  X[[index]][, continuous_variables] <- apply(
    X[[index]][, continuous_variables, drop = FALSE],
    2, normalize_min_max
  )


  fit_each_site[[index]] <- CATE_Per_Site(
    X[[index]], D[[index]], Y[[index]],
    split_index = split_index[[index]], dim = 1
  )
}
for (index in 1:ntask) {
  n_i <- nrow(X[[index]])
  split_index[[index]] <- sample(1:2, n_i, replace = TRUE)
  X_test[[index]][, continuous_variables] <- apply(
    X_test[[index]][, continuous_variables, drop = FALSE],
    2, normalize_min_max
  )
}
max.dim <- 1
p <- ncol(X[[1]])
out_dir <- "corr"
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
saveRDS(X, file = file.path(out_dir, "X.Rdata"))

############################################################
# Parametric transfer
############################################################
Para_transfer <- function() {
  fit <- NULL
  lambda <- NULL

  for (dr.dim in 1:max.dim) {
    fit[[dr.dim]] <- list()
    for (fold in 1:2) {
      gradient <- hessian <- NULL
      for (index in 1:ntask) {
        gradient[[index]] <- fit_each_site[[index]]$gradient[[fold]][[dr.dim]]
        hessian[[index]] <- fit_each_site[[index]]$hessian[[fold]][[dr.dim]]
      }

      initial_value <- list()
      for (index in 1:ntask) {
        initial_value[[index]] <- c(t(fit_each_site[[index]]$coef_estimate[[fold]][[dr.dim]][-(1:dr.dim), ]))
      }

      fit[[dr.dim]][[fold]] <- SemiTransfer_Par(gradient, hessian, initial_value, type = "DR")
      lambda <- c(lambda, fit[[dr.dim]][[fold]]$fit$gglasso.fit$lambda)
    }
  }

  lambda <- sort(unique(lambda))

  for (dr.dim in 1:max.dim) {
    fit[[dr.dim]] <- list()
    for (fold in 1:2) {
      gradient <- hessian <- NULL
      for (index in 1:ntask) {
        gradient[[index]] <- fit_each_site[[index]]$gradient[[fold]][[dr.dim]]
        hessian[[index]] <- fit_each_site[[index]]$hessian[[fold]][[dr.dim]]
      }

      initial_value <- list()
      for (index in 1:ntask) {
        initial_value[[index]] <- c(t(fit_each_site[[index]]$coef_estimate[[fold]][[dr.dim]][-(1:dr.dim), ]))
      }

      fit[[dr.dim]][[fold]] <- SemiTransfer_Par(
        gradient, hessian, initial_value,
        type = "CATE", lambda = lambda
      )
    }
  }

  coef_candidate <- list()
  for (index in 1:ntask) {
    coef_candidate[[index]] <- list()
    for (dr.dim in 1:max.dim) {
      coef_candidate[[index]][[dr.dim]] <- list()
      for (fold in 1:2) {
        ncoef <- dr.dim * p - dr.dim * dr.dim
        coef_candidate[[index]][[dr.dim]][[fold]] <- fit[[dr.dim]][[fold]]$fit$gglasso.fit$beta[
          ((index - 1) * ncoef + 1):(index * ncoef), ] +
          fit[[dr.dim]][[fold]]$fit$gglasso.fit$beta[
            (ntask * ncoef + 1):((ntask + 1) * ncoef), ]
      }
    }
  }

  fit_tuned <- coef_est <- NULL
  error <- array(0, c(ntask, length(lambda)))

  for (index in 1:ntask) {
    fit_tuned[[index]] <- CATE_tune_Per_Site(
      coef_candidate[[index]],
      X[[index]], D[[index]], Y[[index]],
      split_index = split_index[[index]],
      max.dim = max.dim,
      nfold = 2,
      lambda = lambda
    )
    error[index, ] <- fit_tuned[[index]]$error
  }

  error.all.task <- apply(error, 2, mean)

  for (index in 1:ntask) {
    coef_est[[index]] <- (
      coef_candidate[[index]][[1]][[1]][, which.min(error.all.task)] +
      coef_candidate[[index]][[1]][[2]][, which.min(error.all.task)]
    ) / 2
  }

  list(
    tuned = coef_est,
    untuned = (fit[[1]][[1]]$coef + fit[[1]][[2]]$coef) / 2
  )
}

coef_para <- Para_transfer()
coef_est <- coef_para$tuned
coef_est_untuned <- coef_para$untuned

split_index_test <- vector("list", ntask)
for (index in 1:ntask) {
  split_index_test[[index]] <- sample(1:2, nrow(X_test[[index]]), replace = TRUE)
}

eval_para_transfer_tuned <- vector("list", ntask)
for (index in 1:ntask) {
  eval_para_transfer_tuned[[index]] <- CATE_predict(
    X[[index]], D[[index]], Y[[index]],
    c(1, coef_est[[index]]) |> matrix(),
    nonpar_transfer = FALSE,
    number_split = 2,
    split_index = split_index_test[[index]],
    dim = 1, real_data=FALSE
  )
}
saveRDS(eval_para_transfer_tuned, file = file.path(out_dir, "eval_para_transfer_tuned_w_race.Rdata"))

eval_para_transfer_untuned <- vector("list", ntask)
for (index in 1:ntask) {
  eval_para_transfer_untuned[[index]] <- CATE_predict(
    X[[index]], D[[index]], Y[[index]],
    c(1, coef_est_untuned[, index]) |> matrix(),
    nonpar_transfer = FALSE,
    number_split = 2,
    split_index = split_index_test[[index]],
    dim = 1
  )
}
saveRDS(eval_para_transfer_untuned, file = file.path(out_dir, "eval_para_transfer_untuned_w_race.Rdata"))

############################################################
# Sai transfer
############################################################
ceof_sai <- list()
lambda_seq <- 10^seq(2, -2, by = -0.1)

for (index in 1:ntask) {
  X_aux <- do.call(rbind, X[-index])
  Y_aux <- do.call(c, Y[-index])
  D_aux <- do.call(c, D[-index])

  interaction_terms <- X_aux * D_aux
  lasso_X <- cbind(X_aux, D_aux, interaction_terms)

  lasso_fit <- cv.glmnet(
    lasso_X, Y_aux,
    alpha = 1,
    lambda = lambda_seq,
    intercept = FALSE
  )

  beta <- as.numeric(coef(lasso_fit, s = "lambda.min"))[-1]
  p_x <- ncol(X_aux)
  interaction_coef <- beta[(p_x + 2):(2 * p_x + 1)]

  Y_transfer <- Y[[index]]
  interaction_terms <- X[[index]] * D[[index]]
  X_transfer <- cbind(X[[index]], D[[index]], interaction_terms)

  cv_fit <- cv.glmnet(
    x = X_transfer,
    y = Y_transfer - X_transfer %*% beta,
    alpha = 1,
    lambda = lambda_seq,
    intercept = FALSE
  )

  best_lambda <- cv_fit$lambda.min
  best_coef <- as.numeric(coef(cv_fit, s = best_lambda))[-1]
  interaction_coef_delta <- best_coef[(p_x + 2):(2 * p_x + 1)]

  beta[(p_x + 2):(2 * p_x + 1)] <- interaction_coef + interaction_coef_delta
  ceof_sai[[index]] <- beta
}

print(ceof_sai)

eval_Sai <- vector("list", ntask)
for (index in 1:ntask) {
  X_aux <- X_test[[index]]
  Y_aux <- Y_test[[index]]
  D_aux <- D_test[[index]]

  interaction_terms <- X_aux * D_aux
  lasso_X <- cbind(X_aux, D_aux, interaction_terms)
  beta_sai <- ceof_sai[[index]]
  err_sai <- as.numeric(Y_aux - lasso_X %*% beta_sai)

  CATE_sai <- estimate_cate(X_aux, beta_sai)

  eval_Sai[[index]] <- list(
    mse = list(mean(err_sai^2)),
    value_function = list(mean(err_sai^2)),
    f_hat = CATE_sai
  )
}
saveRDS(eval_Sai, file = file.path(out_dir, "eval_Sai_transfer_w_race.Rdata"))

############################################################
# No transfer
############################################################
coef_est_no_transfer <- NULL
for (index in 1:ntask) {
  coef_est_no_transfer <- cbind(
    coef_est_no_transfer,
    0.5 * (
      fit_each_site[[index]]$coef_estimate[[1]][[1]] +
      fit_each_site[[index]]$coef_estimate[[2]][[1]]
    )
  )
}

eval_no_transfer <- vector("list", ntask)
for (index in 1:ntask) {
  eval_no_transfer[[index]] <- CATE_predict(
    X[[index]], D[[index]], Y[[index]],
    coef_est_no_transfer[, index],
    split_index = NULL,
    number_split = 2,
    nonpar_transfer = FALSE,
    propensity_score = NULL,
    mu0 = NULL,
    mu1 = NULL,
    dim = 1
  )
}
saveRDS(eval_no_transfer, file = file.path(out_dir, "eval_no_transfer_w_race.Rdata"))

############################################################
# ARMUL and pERM
############################################################
fit_ARMUL_beta <- function(X, D, Y, ntask, split_index, number_split = 2,
                           T_global_nuis = 1000, T_global_step2 = 2000,
                           spline_nuis = TRUE) {
  n_list <- sapply(1:ntask, function(t) nrow(X[[t]]))

  mu1_hat <- lapply(1:ntask, function(t) rep(NA_real_, n_list[t]))
  mu0_hat <- lapply(1:ntask, function(t) rep(NA_real_, n_list[t]))
  e_hat   <- lapply(1:ntask, function(t) rep(NA_real_, n_list[t]))

  for (fold in 1:number_split) {
    X1 <- Y1 <- X0 <- Y0 <- Xtr <- Dtr <- vector("list", ntask)
    Xte <- vector("list", ntask)

    for (t in 1:ntask) {
      idx_tr <- which(split_index[[t]] != fold)
      idx_te <- which(split_index[[t]] == fold)

      Xte[[t]] <- X[[t]][idx_te, , drop = FALSE]

      idx1 <- idx_tr[D[[t]][idx_tr] == 1]
      idx0 <- idx_tr[D[[t]][idx_tr] == 0]

      X1[[t]] <- X[[t]][idx1, , drop = FALSE]
      Y1[[t]] <- Y[[t]][idx1]
      X0[[t]] <- X[[t]][idx0, , drop = FALSE]
      Y0[[t]] <- Y[[t]][idx0]
      Xtr[[t]] <- X[[t]][idx_tr, , drop = FALSE]
      Dtr[[t]] <- D[[t]][idx_tr]
    }

    mu1_model <- vanilla_train(X1, Y1, link = "logistic", T_global = T_global_nuis, spline = spline_nuis)
    mu0_model <- vanilla_train(X0, Y0, link = "logistic", T_global = T_global_nuis, spline = spline_nuis)
    e_model   <- vanilla_train(Xtr, Dtr, link = "logistic", T_global = T_global_nuis, spline = spline_nuis)

    for (t in 1:ntask) {
      idx_te <- which(split_index[[t]] == fold)
      mu1_hat[[t]][idx_te] <- drop(vanilla_predict(mu1_model, Xte, task_id = t, link = "logistic"))
      mu0_hat[[t]][idx_te] <- drop(vanilla_predict(mu0_model, Xte, task_id = t, link = "logistic"))
      e_hat[[t]][idx_te]   <- drop(vanilla_predict(e_model,   Xte, task_id = t, link = "logistic"))
    }
  }

  clip01 <- function(p, eps = 1e-3) pmin(pmax(p, eps), 1 - eps)
  e_hat <- lapply(e_hat, clip01)

  coef_est <- vector("list", number_split)

  for (fold in 1:number_split) {
    pseudoY <- X_step2 <- vector("list", ntask)

    for (t in 1:ntask) {
      idx_tr <- which(split_index[[t]] != fold)

      Dt   <- D[[t]][idx_tr]
      Yt   <- Y[[t]][idx_tr]
      mu1t <- mu1_hat[[t]][idx_tr]
      mu0t <- mu0_hat[[t]][idx_tr]
      et   <- e_hat[[t]][idx_tr]

      pseudoY[[t]] <- (Dt == 1) / et * (Yt - mu1t) -
        (Dt == 0) / (1 - et) * (Yt - mu0t) +
        (mu1t - mu0t)

      X_step2[[t]] <- X[[t]][idx_tr, , drop = FALSE]
    }

    models <- vanilla_train(X_step2, pseudoY, link = "linear", T_global = T_global_step2, spline = FALSE)

    coef_est[[fold]] <- vector("list", ntask)
    for (t in 1:ntask) {
      b <- models$vanilla[, , 1][t, ]
      coef_est[[fold]][[t]] <- b / b[1]
    }
  }

  ARMUL_beta <- do.call(
    cbind,
    lapply(1:ntask, function(t) {
      Reduce("+", lapply(1:number_split, function(f) coef_est[[f]][[t]])) / number_split
    })
  )
  colnames(ARMUL_beta) <- paste0("task", 1:ntask)

  list(beta = ARMUL_beta, mu1 = mu1_hat, mu0 = mu0_hat, e = e_hat)
}

fit_pERM_beta <- function(X, D, Y, ntask, split_index, number_split = 2,
                          r_mu = 3, nbasis_mu = 10,
                          r_e = 3, nbasis_e = 10,
                          r_step2 = 2, nbasis_step2 = 1) {
  n_list <- sapply(1:ntask, function(t) nrow(X[[t]]))

  mu1_hat <- lapply(1:ntask, function(t) rep(NA_real_, n_list[t]))
  mu0_hat <- lapply(1:ntask, function(t) rep(NA_real_, n_list[t]))
  e_hat   <- lapply(1:ntask, function(t) rep(NA_real_, n_list[t]))

  for (fold in 1:number_split) {
    Xte <- vector("list", ntask)
    peRMdata <- vector("list", ntask)

    for (t in 1:ntask) {
      idx_tr <- which(split_index[[t]] != fold)
      idx_te <- which(split_index[[t]] == fold)

      Xte[[t]] <- X[[t]][idx_te, , drop = FALSE]

      idx1 <- idx_tr[D[[t]][idx_tr] == 1]
      X1 <- X[[t]][idx1, , drop = FALSE]
      Y1 <- Y[[t]][idx1]

      peRMdata[[t]] <- list(X = as.matrix(X1), y = as.matrix(Y1))
    }

    m1 <- pERM_torch(peRMdata, r = r_mu, nbasis = nbasis_mu,
                     info = TRUE, link = "logistic", X_test_list = Xte)

    for (t in 1:ntask) {
      idx_te <- which(split_index[[t]] == fold)
      mu1_hat[[t]][idx_te] <- as.numeric(m1$test_preds[[t]])
    }

    for (t in 1:ntask) {
      idx_tr <- which(split_index[[t]] != fold)
      idx0 <- idx_tr[D[[t]][idx_tr] == 0]
      X0 <- X[[t]][idx0, , drop = FALSE]
      Y0 <- Y[[t]][idx0]
      peRMdata[[t]] <- list(X = as.matrix(X0), y = as.matrix(Y0))
    }

    m0 <- pERM_torch(peRMdata, r = r_mu, nbasis = nbasis_mu,
                     info = TRUE, link = "logistic", X_test_list = Xte)

    for (t in 1:ntask) {
      idx_te <- which(split_index[[t]] == fold)
      mu0_hat[[t]][idx_te] <- as.numeric(m0$test_preds[[t]])
    }

    for (t in 1:ntask) {
      idx_tr <- which(split_index[[t]] != fold)
      Xtr <- X[[t]][idx_tr, , drop = FALSE]
      Dtr <- D[[t]][idx_tr]
      peRMdata[[t]] <- list(X = as.matrix(Xtr), y = as.matrix(Dtr))
    }

    me <- pERM_torch(peRMdata, r = r_e, nbasis = nbasis_e,
                     info = TRUE, link = "logistic", X_test_list = Xte)

    for (t in 1:ntask) {
      idx_te <- which(split_index[[t]] == fold)
      e_hat[[t]][idx_te] <- as.numeric(me$test_preds[[t]])
    }
  }

  clip01 <- function(p, eps = 1e-3) pmin(pmax(p, eps), 1 - eps)
  e_hat <- lapply(e_hat, clip01)

  coef_est <- vector("list", number_split)

  for (fold in 1:number_split) {
    peRMdata <- vector("list", ntask)

    for (t in 1:ntask) {
      idx_tr <- which(split_index[[t]] != fold)

      Dt   <- D[[t]][idx_tr]
      Yt   <- Y[[t]][idx_tr]
      mu1t <- mu1_hat[[t]][idx_tr]
      mu0t <- mu0_hat[[t]][idx_tr]
      et   <- e_hat[[t]][idx_tr]

      pseudoY <- (Dt == 1) / et * (Yt - mu1t) -
        (Dt == 0) / (1 - et) * (Yt - mu0t) +
        (mu1t - mu0t)

      Xtr <- X[[t]][idx_tr, , drop = FALSE]
      peRMdata[[t]] <- list(X = as.matrix(Xtr), y = as.matrix(pseudoY))
    }

    m2 <- pERM_torch(peRMdata, r = r_step2, nbasis = nbasis_step2,
                     info = TRUE, link = "linear")

    coef_est[[fold]] <- vector("list", ntask)
    for (t in 1:ntask) {
      b <- m2$step2[, t]
      coef_est[[fold]][[t]] <- b / b[1]
    }
  }

  pERM_beta <- do.call(
    cbind,
    lapply(1:ntask, function(t) {
      Reduce("+", lapply(1:number_split, function(f) coef_est[[f]][[t]])) / number_split
    })
  )
  colnames(pERM_beta) <- paste0("task", 1:ntask)

  list(beta = pERM_beta, mu1 = mu1_hat, mu0 = mu0_hat, e = e_hat)
}

fit_armul <- fit_ARMUL_beta(X, D, Y, ntask = ntask, split_index = split_index, number_split = 2)
fit_perm  <- fit_pERM_beta(X, D, Y, ntask = ntask, split_index = split_index, number_split = 2)

eval_ARMUL <- vector("list", ntask)
eval_pERM  <- vector("list", ntask)
eval_ARMUL_train <- vector("list", ntask)
eval_pERM_train <- vector("list", ntask)

for (t in 1:ntask) {
  eval_ARMUL[[t]] <- CATE_predict(
    X[[t]], D[[t]], Y[[t]],
    coef_estimate = c(fit_armul$beta[, t]) |> matrix(),
    nonpar_transfer = FALSE,
    number_split = 2,
    split_index = split_index_test[[t]],
    dim = 1,
    real_data = FALSE
  )

  eval_pERM[[t]] <- CATE_predict(
    X[[t]], D[[t]], Y[[t]],
    coef_estimate = c(fit_perm$beta[, t]) |> matrix(),
    nonpar_transfer = FALSE,
    number_split = 2,
    split_index = split_index_test[[t]],
    dim = 1,
    real_data = FALSE
  )

  eval_ARMUL_train[[t]] <- CATE_predict(
    X[[t]], D[[t]], Y[[t]],
    coef_estimate = c(fit_armul$beta[, t]) |> matrix(),
    nonpar_transfer = FALSE,
    number_split = 2,
    split_index = split_index[[t]],
    dim = 1,
    real_data = FALSE
  )

  eval_pERM_train[[t]] <- CATE_predict(
    X[[t]], D[[t]], Y[[t]],
    coef_estimate = c(fit_perm$beta[, t]) |> matrix(),
    nonpar_transfer = FALSE,
    number_split = 2,
    split_index = split_index[[t]],
    dim = 1,
    real_data = FALSE
  )
}

saveRDS(eval_ARMUL, file = file.path(out_dir, "eval_ARMUL_w_race.Rdata"))
saveRDS(eval_pERM, file = file.path(out_dir,"eval_pERM_w_race.Rdata"))
saveRDS(eval_ARMUL_train, file = "eval_ARMUL_train_w_race.Rdata")
saveRDS(eval_pERM_train, file = "eval_pERM_train_w_race.Rdata")

############################################################
# Pooled method
############################################################
pooled_X <- do.call(rbind, X)
saveRDS(pooled_X, file = file.path(out_dir,"pool_X.Rdata"))

pooled_D <- do.call(c, D)
pooled_Y <- do.call(c, Y)

pooled_fit <- CATE_Per_Site(
  pooled_X, pooled_D, pooled_Y,
  split_index = sample(1:2, nrow(pooled_X), replace = TRUE),
  dim = 1
)

pooled_coef <- 0.5 * (
  pooled_fit$coef_estimate[[1]][[1]] +
  pooled_fit$coef_estimate[[2]][[1]]
)

pooled_X_test <- do.call(rbind, X_test)
pooled_D_test <- do.call(c, D_test)
pooled_Y_test <- do.call(c, Y_test)

eval_pool <- CATE_predict(
  pooled_X_test, pooled_D_test, pooled_Y_test,
  pooled_coef,
  split_index = sample(1:2, nrow(pooled_X_test), replace = TRUE),
  number_split = 2,
  nonpar_transfer = FALSE,
  propensity_score = NULL,
  mu0 = NULL,
  mu1 = NULL,
  dim = 1
)

saveRDS(eval_pool, file = file.path(out_dir,"eval_pool_w_race.Rdata"))

############################################################
# Nonparametric transfer
############################################################
grid <- list()
total_sample_size <- sum(sapply(X, nrow))

for (index in 1:ntask) {
  grid[[index]] <- list()
  for (fold in 1:2) {
    grid[[index]][[fold]] <- get_grid_from_each_site(
      X = X[[index]],
      total_sample_size,
      method = "noise"
    )
  }
}
# Nonparametric Transfer Learning
transfer_Y_given_X <- function(Y, X, split_index, split_index.test, X.test=NULL){
  bandwidth_scale_seq <- seq(0.5,1,length.out=5)
  cv.bandwidth.error <- array(0, c(length(bandwidth_scale_seq),ntask))
  predict_Y_given_X_bandwidth <- NULL
  predict_Y_given_X <- predict_Y_given_X.test <- NULL
  predict_Y_given_X_opt <- NULL
  for (k in 1:length(bandwidth_scale_seq)){
    for (index.test in 1:ntask){
      bandwidth_scale <- bandwidth_scale_seq[k]
      ## each site for nonpar transfer
      Y_given_X_transfer_each_site <- NULL
      fit_Y_given_X <- list()
      lambda <-NULL
      for (fold in 1:2){
        for (index in 1:ntask){
          Y_given_X_transfer_each_site[[index]] <- Nonpar_Per_Site(X=X[[index]], Y=Y[[index]],
                                                                   split_index=split_index[[index]],
                                                                   grid = grid[[index.test]][[fold]],
                                                                   bandwidth_scale=bandwidth_scale, method="np")
        }
        ## nonpar transfer for Y_given_X and D_given_X
        ### transfer learning for Y_given_X (main node) indexed by fold is fitted using data not in this fold
        gradient <- hessian <- array(0, dim = c(NROW(grid[[index.test]][[fold]]), ntask))
        for (index in 1:ntask) {
          pseudo_fold_index <- switch(fold, '1'=2, '2'=1)
          gradient[,index] <- -Y_given_X_transfer_each_site[[index]]$gradient[[pseudo_fold_index]]
          hessian[,index] <- Y_given_X_transfer_each_site[[index]]$hessian[[pseudo_fold_index]]
        }
        fit_Y_given_X[[fold]] <- SemiTransfer_NonPar(gradient, hessian)
        lambda <- c(lambda, fit_Y_given_X[[fold]]$fit$lambda)
      }
      lambda <- sort(unique(lambda))
      cv.error <- array(0, dim=c(2,length(lambda)))
      predict_Y_given_X_opt[[index.test]] <- array(0, c(NROW(X.test[[index.test]]),1))
      for (fold in 1:2){
        for (index in 1:ntask){
          Y_given_X_transfer_each_site[[index]] <- Nonpar_Per_Site(X=X[[index]] , Y=Y[[index]],
                                                                   split_index=split_index[[index]],
                                                                   grid = grid[[index.test]][[fold]], bandwidth_scale=bandwidth_scale)
        }
        ## nonpar transfer for Y_given_X and D_given_X
        ### transfer learning for Y_given_X (main node) indexed by fold is fitted using data not in this fold
        gradient <- hessian <- array(0, dim = c(NROW(grid[[index.test]][[fold]]), ntask))
        for (index in 1:ntask) {
          pseudo_fold_index <- switch(fold, '1'=2, '2'=1)
          gradient[,index] <- -Y_given_X_transfer_each_site[[index]]$gradient[[pseudo_fold_index]]
          hessian[,index] <- Y_given_X_transfer_each_site[[index]]$hessian[[pseudo_fold_index]]
        }
        fit_Y_given_X[[fold]] <- SemiTransfer_NonPar(gradient, hessian, lambda=lambda)
        ### prediction match (each site) on fold 1
        predict_Y_given_X[[fold]] <- get_prediction_nonpar(fit_Y_given_X[[fold]],
                                                           X=X[[index.test]],
                                                           grid[[index.test]][[fold]], task=index.test)
        predict_Y_given_X.test[[fold]] <- get_prediction_nonpar(fit_Y_given_X[[fold]],
                                                                X=X.test[[index.test]],
                                                                grid[[index.test]][[fold]], task=index.test)
        ### calculate error (each site) on fold
        cv.error[fold,] <- apply(predict_Y_given_X[[fold]][split_index[[index.test]]==fold,],2, function(t){mean((t-
                                                                                                                    Y[[index.test]][split_index[[index.test]]==fold])^2)})
        
      }
      for (fold in 1:2){
        predict_Y_given_X_opt[[index.test]][split_index.test[[index.test]]==fold] <-
          predict_Y_given_X.test[[fold]][split_index.test[[index.test]]==fold,which.min(cv.error[fold,])]
      }
      cv.bandwidth.error[k, index.test] <- (min(cv.error[1,])+min(cv.error[2,]))/2
    }
    predict_Y_given_X_bandwidth[[k]] <- predict_Y_given_X_opt
  }
  f.value_opt <-NULL
  for (index in 1:ntask){
    f.value_opt[[index]] <- predict_Y_given_X_bandwidth[[which.min(cv.bandwidth.error[,index])]][[index]]
  }
  f.value_opt
}

Y1 <- Y0 <- X1 <- X0 <- split_index1 <- split_index0 <- NULL
for (index in 1:ntask) {
  Y1[[index]] <- Y[[index]][D[[index]] == 1]
  Y0[[index]] <- Y[[index]][D[[index]] == 0]
  X1[[index]] <- X[[index]][D[[index]] == 1, , drop = FALSE]
  X0[[index]] <- X[[index]][D[[index]] == 0, , drop = FALSE]
  split_index1[[index]] <- split_index[[index]][D[[index]] == 1]
  split_index0[[index]] <- split_index[[index]][D[[index]] == 0]
}

mu1_opt <- transfer_Y_given_X(Y = Y1, X = X1, split_index = split_index1, split_index.test = split_index, X.test = X)
mu0_opt <- transfer_Y_given_X(Y = Y0, X = X0, split_index = split_index0, split_index.test = split_index, X.test = X)
D_given_X_opt <- transfer_Y_given_X(Y = D, X = X, split_index = split_index, split_index.test = split_index, X.test = X)

for (index in 1:ntask) {
  Y1[[index]] <- Y_test[[index]][D_test[[index]] == 1]
  Y0[[index]] <- Y_test[[index]][D_test[[index]] == 0]
  X1[[index]] <- X_test[[index]][D_test[[index]] == 1, , drop = FALSE]
  X0[[index]] <- X_test[[index]][D_test[[index]] == 0, , drop = FALSE]
  split_index1[[index]] <- split_index_test[[index]][D_test[[index]] == 1]
  split_index0[[index]] <- split_index_test[[index]][D_test[[index]] == 0]
}

mu1_opt_test <- transfer_Y_given_X(Y = Y1, X = X1, split_index = split_index1, split_index.test = split_index_test, X.test = X_test)
mu0_opt_test <- transfer_Y_given_X(Y = Y0, X = X0, split_index = split_index0, split_index.test = split_index_test, X.test = X_test)
D_given_X_opt_test <- transfer_Y_given_X(Y = D_test, X = X_test, split_index = split_index_test, split_index.test = split_index_test, X.test = X_test)

fit_each_site_nonpar_tranfer <- vector("list", ntask)
for (index in 1:ntask) {
  fit_each_site_nonpar_tranfer[[index]] <- CATE_Per_Site(
    X[[index]], D[[index]], Y[[index]],
    nonpar_transfer = TRUE,
    propensity_score = D_given_X_opt[[index]],
    mu0 = mu0_opt[[index]],
    mu1 = mu1_opt[[index]],
    split_index = split_index[[index]],
    dim = 1
  )
}
saveRDS(fit_each_site_nonpar_tranfer, file = file.path(out_dir,"fit_each_site_nonpar_tranfer_w_race.Rdata"))

Semipara_Transfer <- function() {
  fit_both <- NULL
  lambda <- NULL

  for (dr.dim in 1:1) {
    fit_both[[dr.dim]] <- list()
    for (fold in 1:2) {
      gradient <- hessian <- NULL
      for (index in 1:ntask) {
        gradient[[index]] <- fit_each_site_nonpar_tranfer[[index]]$gradient[[fold]][[dr.dim]]
        hessian[[index]] <- fit_each_site_nonpar_tranfer[[index]]$hessian[[fold]][[dr.dim]]
      }

      initial_value <- list()
      for (index in 1:ntask) {
        initial_value[[index]] <- fit_each_site_nonpar_tranfer[[index]]$coef_estimate[[fold]][[1]][-1]
      }

      fit_both[[dr.dim]][[fold]] <- SemiTransfer_Par(
        gradient, hessian, initial_value = initial_value,
        type = "CATE"
      )
      lambda <- c(lambda, fit_both[[dr.dim]][[fold]]$lambda)
    }
  }

  lambda <- sort(unique(lambda))

  for (dr.dim in 1:1) {
    fit_both[[dr.dim]] <- list()
    for (fold in 1:2) {
      gradient <- hessian <- NULL
      for (index in 1:ntask) {
        gradient[[index]] <- fit_each_site_nonpar_tranfer[[index]]$gradient[[fold]][[dr.dim]]
        hessian[[index]] <- fit_each_site_nonpar_tranfer[[index]]$hessian[[fold]][[dr.dim]]
      }

      initial_value <- list()
      for (index in 1:ntask) {
        initial_value[[index]] <- fit_each_site_nonpar_tranfer[[index]]$coef_estimate[[fold]][[1]][-1]
      }

      fit_both[[dr.dim]][[fold]] <- SemiTransfer_Par(
        gradient, hessian, initial_value = initial_value,
        type = "CATE", lambda = lambda
      )
    }
  }

  coef_candidate <- list()
  for (index in 1:ntask) {
    coef_candidate[[index]] <- list()
    for (dr.dim in 1:1) {
      coef_candidate[[index]][[dr.dim]] <- list()
      for (fold in 1:2) {
        ncoef <- dr.dim * p - dr.dim * dr.dim
        coef_candidate[[index]][[dr.dim]][[fold]] <-
          fit_both[[dr.dim]][[fold]]$fit$gglasso.fit$beta[((index - 1) * ncoef + 1):(index * ncoef), ] +
          fit_both[[dr.dim]][[fold]]$fit$gglasso.fit$beta[(ntask * ncoef + 1):((ntask + 1) * ncoef), ]
      }
    }
  }

  fit_tuned <- coef_est_both <- NULL
  error <- array(0, c(ntask, length(lambda)))

  for (index in 1:ntask) {
    fit_tuned[[index]] <- CATE_tune_Per_Site(
      coef_candidate[[index]],
      X[[index]], D[[index]], Y[[index]],
      split_index = split_index[[index]],
      max.dim = max.dim,
      nfold = 2,
      lambda = lambda
    )
    error[index, ] <- fit_tuned[[index]]$error
  }

  error.all.task <- apply(error, 2, mean)

  for (index in 1:ntask) {
    coef_est_both[[index]] <- (
      coef_candidate[[index]][[1]][[1]][, which.min(error.all.task)] +
      coef_candidate[[index]][[1]][[2]][, which.min(error.all.task)]
    ) / 2
  }

  list(
    tuned = coef_est_both,
    untuned = (fit_both[[1]][[1]]$coef + fit_both[[1]][[2]]$coef) / 2
  )
}

coef_semipara <- Semipara_Transfer()
coef_est_both <- coef_semipara$tuned
coef_est_both_untuned <- coef_semipara$untuned

eval_semipara_transfer_untuned <- vector("list", ntask)
for (index in 1:ntask) {
  eval_semipara_transfer_untuned[[index]] <- CATE_predict(
    X[[index]], D[[index]], Y[[index]],
    c(1, coef_est_both_untuned[, index]) |> matrix(),
    nonpar_transfer = TRUE,
    number_split = 2,
    propensity_score = D_given_X_opt_test[[index]],
    mu0 = mu0_opt_test[[index]],
    mu1 = mu1_opt_test[[index]],
    split_index = split_index_test[[index]],
    dim = 1
  )
}
saveRDS(eval_semipara_transfer_untuned, file = file.path(out_dir, "eval_semipara_transfer_untuned_w_race.Rdata"))

eval_semipara_transfer_tuned <- vector("list", ntask)
for (index in 1:ntask) {
  eval_semipara_transfer_tuned[[index]] <- CATE_predict(
    X_test[[index]], D_test[[index]], Y_test[[index]],
    c(1, coef_est_both[[index]]) |> matrix(),
    nonpar_transfer = TRUE,
    number_split = 2,
    propensity_score = D_given_X_opt_test[[index]],
    mu0 = mu0_opt_test[[index]],
    mu1 = mu1_opt_test[[index]],
    split_index = split_index_test[[index]],
    dim = 1
  )
}
saveRDS(eval_semipara_transfer_tuned, file = file.path(out_dir, "eval_semipara_transfer_tuned_w_race.Rdata"))

############################################################
# Train evaluations for whole-data setting
############################################################
eval_Sai_train <- vector("list", ntask)
eval_para_transfer_tuned_train <- vector("list", ntask)
eval_para_transfer_untuned_train <- vector("list", ntask)
eval_no_transfer_train <- vector("list", ntask)
eval_semipara_transfer_untuned_train <- vector("list", ntask)
eval_semipara_transfer_tuned_train <- vector("list", ntask)

for (index in 1:ntask) {
  X_aux <- X[[index]]
  Y_aux <- Y[[index]]
  D_aux <- D[[index]]

  interaction_terms <- X_aux * D_aux
  lasso_X <- cbind(X_aux, D_aux, interaction_terms)
  beta_sai <- ceof_sai[[index]]
  err_sai <- as.numeric(Y_aux - lasso_X %*% beta_sai)

  eval_Sai_train[[index]] <- list(
    mse = list(mean(err_sai^2)),
    value_function = list(mean(err_sai^2)),
    f_hat = estimate_cate(X_aux, beta_sai)
  )

  eval_para_transfer_tuned_train[[index]] <- CATE_predict(
    X[[index]], D[[index]], Y[[index]],
    c(1, coef_est[[index]]) |> matrix(),
    nonpar_transfer = FALSE,
    number_split = 2,
    split_index = split_index[[index]],
    dim = 1
  )

  eval_para_transfer_untuned_train[[index]] <- CATE_predict(
    X[[index]], D[[index]], Y[[index]],
    c(1, coef_est_untuned[, index]) |> matrix(),
    nonpar_transfer = FALSE,
    number_split = 2,
    split_index = split_index[[index]],
    dim = 1
  )

  eval_no_transfer_train[[index]] <- CATE_predict(
    X[[index]], D[[index]], Y[[index]],
    coef_est_no_transfer[, index],
    split_index = NULL,
    number_split = 2,
    nonpar_transfer = FALSE,
    propensity_score = NULL,
    mu0 = NULL,
    mu1 = NULL,
    dim = 1
  )

  eval_semipara_transfer_untuned_train[[index]] <- CATE_predict(
    X[[index]], D[[index]], Y[[index]],
    c(1, coef_est_both_untuned[, index]) |> matrix(),
    nonpar_transfer = TRUE,
    number_split = 2,
    propensity_score = D_given_X_opt[[index]],
    mu0 = mu0_opt[[index]],
    mu1 = mu1_opt[[index]],
    split_index = split_index[[index]],
    dim = 1
  )

  eval_semipara_transfer_tuned_train[[index]] <- CATE_predict(
    X[[index]], D[[index]], Y[[index]],
    c(1, coef_est_both[[index]]) |> matrix(),
    nonpar_transfer = TRUE,
    number_split = 2,
    propensity_score = D_given_X_opt[[index]],
    mu0 = mu0_opt[[index]],
    mu1 = mu1_opt[[index]],
    split_index = split_index[[index]],
    dim = 1
  )
}

saveRDS(eval_Sai_train, file = "eval_Sai_train_w_race.Rdata")
saveRDS(eval_para_transfer_tuned_train, file = "eval_para_transfer_tuned_train_w_race.Rdata")
saveRDS(eval_para_transfer_untuned_train, file = "eval_para_transfer_untuned_train_w_race.Rdata")
saveRDS(eval_no_transfer_train, file = "eval_no_transfer_train_w_race.Rdata")
saveRDS(eval_semipara_transfer_untuned_train, file = "eval_semipara_transfer_untuned_train_w_race.Rdata")
saveRDS(eval_semipara_transfer_tuned_train, file = "eval_semipara_transfer_tuned_train_w_race.Rdata")

############################################################
# Summary objects
############################################################
eval_res <- list(
  eval_para_transfer_tuned = eval_para_transfer_tuned,
  eval_para_transfer_untuned = eval_para_transfer_untuned,
  eval_no_transfer = eval_no_transfer,
  eval_pool = list(eval_pool),
  eval_semipara_transfer_untuned = eval_semipara_transfer_untuned,
  eval_semipara_transfer_tuned = eval_semipara_transfer_tuned,
  eval_Sai = eval_Sai,
  eval_ARMUL = eval_ARMUL,
  eval_pERM = eval_pERM,

  eval_ARMUL_train = eval_ARMUL_train,
  eval_pERM_train = eval_pERM_train,
  eval_Sai_train = eval_Sai_train,
  eval_para_transfer_tuned_train = eval_para_transfer_tuned_train,
  eval_para_transfer_untuned_train = eval_para_transfer_untuned_train,
  eval_no_transfer_train = eval_no_transfer_train,
  eval_semipara_transfer_untuned_train = eval_semipara_transfer_untuned_train,
  eval_semipara_transfer_tuned_train = eval_semipara_transfer_tuned_train
)

coef_res <- list(
  beta_ARMUL = fit_armul$beta,
  beta_pERM = fit_perm$beta
)

res_df <- format_list_to_df(eval_res)
mean_mse_by_model <- aggregate(Value_Function ~ Model, data = res_df, FUN = mean)
print(mean_mse_by_model)

saveRDS(eval_res, file = "all_eval_methods_w_race.RDS")
saveRDS(coef_res, file = "all_coef_methods_w_race.RDS")
write.csv(res_df,
          "all_methods_summary_w_race.csv",
          row.names = FALSE)
write.csv(mean_mse_by_model,
          "mean_value_function_by_model_w_race.csv",
          row.names = FALSE)

############################################################
# f_hat collection
############################################################
methods <- eval_res
method_names <- names(methods)

all_f_hat <- list()
for (method_name in method_names) {
  eval_method <- methods[[method_name]]
  method_f_hat <- vector("list", length(eval_method))

  for (index in seq_along(eval_method)) {
    method_f_hat[[index]] <- eval_method[[index]]$f_hat
  }

  all_f_hat[[method_name]] <- method_f_hat
}

saveRDS(all_f_hat,
        "f_hat_results_w_race.rds")

############################################################
# Correlations of f_hat
############################################################
all_correlations <- list()

for (method_name in names(all_f_hat)) {
  method_preds <- all_f_hat[[method_name]]
  n_pred <- length(method_preds)

  cor_mat <- matrix(NA_real_, nrow = n_pred, ncol = n_pred)
  rownames(cor_mat) <- paste0("Dataset_", seq_len(n_pred))
  colnames(cor_mat) <- paste0("Dataset_", seq_len(n_pred))

  for (i in seq_len(n_pred)) {
    for (j in seq_len(n_pred)) {
      cor_mat[i, j] <- safe_cor(method_preds[[i]], method_preds[[j]])
    }
  }

  all_correlations[[method_name]] <- cor_mat
}

save(all_correlations, file = "correlations.RData")

correlations_df <- do.call(rbind, lapply(names(all_correlations), function(method_name) {
  cor_mat <- all_correlations[[method_name]]
  data.frame(
    Method = method_name,
    Dataset1 = rep(rownames(cor_mat), times = ncol(cor_mat)),
    Dataset2 = rep(colnames(cor_mat), each = nrow(cor_mat)),
    Correlation = as.vector(cor_mat)
  )
}))

write.csv(
  correlations_df,
  "correlations.csv",
  row.names = FALSE
)
out_dir <- "/corr"
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
saveRDS(eval_para_transfer_tuned, file = file.path(out_dir, "eval_para_transfer_tuned_w_race.Rdata"))
saveRDS(eval_para_transfer_untuned, file = file.path(out_dir, "eval_para_transfer_untuned_w_race.Rdata"))
saveRDS(eval_Sai, file = file.path(out_dir, "eval_Sai_transfer_w_race.Rdata"))
saveRDS(eval_no_transfer, file = file.path(out_dir, "eval_no_transfer_w_race.Rdata"))
saveRDS(eval_ARMUL, file = file.path(out_dir, "eval_ARMUL_w_race.Rdata"))
saveRDS(eval_pERM, file = file.path(out_dir, "eval_pERM_w_race.Rdata"))
saveRDS(eval_ARMUL_train, file = file.path(out_dir, "eval_ARMUL_train_w_race.Rdata"))
saveRDS(eval_pERM_train, file = file.path(out_dir, "eval_pERM_train_w_race.Rdata"))
saveRDS(eval_pool, file = file.path(out_dir, "eval_pool_w_race.Rdata"))
saveRDS(fit_each_site_nonpar_tranfer, file = file.path(out_dir, "fit_each_site_nonpar_tranfer_w_race.Rdata"))
saveRDS(eval_semipara_transfer_untuned, file = file.path(out_dir, "eval_semipara_transfer_untuned_w_race.Rdata"))
saveRDS(eval_semipara_transfer_tuned, file = file.path(out_dir, "eval_semipara_transfer_tuned_w_race.Rdata"))
saveRDS(eval_Sai_train, file = file.path(out_dir, "eval_Sai_train_w_race.Rdata"))
saveRDS(eval_para_transfer_tuned_train, file = file.path(out_dir, "eval_para_transfer_tuned_train_w_race.Rdata"))
saveRDS(eval_para_transfer_untuned_train, file = file.path(out_dir, "eval_para_transfer_untuned_train_w_race.Rdata"))
saveRDS(eval_no_transfer_train, file = file.path(out_dir, "eval_no_transfer_train_w_race.Rdata"))
saveRDS(eval_semipara_transfer_untuned_train, file = file.path(out_dir, "eval_semipara_transfer_untuned_train_w_race.Rdata"))
saveRDS(eval_semipara_transfer_tuned_train, file = file.path(out_dir, "eval_semipara_transfer_tuned_train_w_race.Rdata"))
saveRDS(eval_res, file = file.path(out_dir, "all_eval_methods_w_race.RDS"))
saveRDS(coef_res, file = file.path(out_dir, "all_coef_methods_w_race.RDS"))
saveRDS(all_f_hat, file = file.path(out_dir, "f_hat_results_w_race.rds"))
save(all_correlations, file = file.path(out_dir, "correlations.RData"))
write.csv(
  res_df,
  file.path(out_dir, "all_methods_summary_w_race.csv"),
  row.names = FALSE
)

write.csv(
  mean_mse_by_model,
  file.path(out_dir, "mean_value_function_by_model_w_race.csv"),
  row.names = FALSE
)

write.csv(
  correlations_df,
  file.path(out_dir, "correlations.csv"),
  row.names = FALSE
)
############################################################
# Optional plots
############################################################
print(plot_evaluation(eval_semipara_transfer_untuned))
print(plot_evaluation(eval_semipara_transfer_tuned))
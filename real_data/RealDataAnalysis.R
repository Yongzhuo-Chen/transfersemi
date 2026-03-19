source("prediction_per_site.R")


library(glmnet) 
eval_function <- function(seed){
set.seed(seed)
folder_path <- "result_real_data"
if (!dir.exists(folder_path)) {
  dir.create(folder_path, recursive = TRUE)
  message("Folder created: ", folder_path)
} else {
  message("Folder already exists: ", folder_path)
}
file_name <- paste0(folder_path, "/", seed, ".RData")




original_wd <- getwd()
setwd("../TransferSemi/R")
files <- list.files(pattern = "\\.R$")
a=lapply(files, source)
setwd(original_wd)
#convert_age_one_hot <- function(combined){
#  age_quantiles <- quantile(combined$age, probs = seq(0, 1, 0.25), na.rm = TRUE)
#  combined$age_quantile <- cut(
#    combined$age,
#    breaks = age_quantiles,
#    include.lowest = TRUE,
#    labels = c("Q1", "Q2", "Q3", "Q4")
#  )
#  age_one_hot <- model.matrix(~ age_quantile - 1, data = combined)
#  combined_one_hot <- cbind(combined[, !colnames(combined) %in% c("age", "age_quantile")], age_one_hot)
#  combined_one_hot
#}

convert_age_one_hot <- function(combined) {
  # Create a binary category for below 55 and above 55
  combined$age_category <- ifelse(combined$age <= 55, "Below_55", "Above_55")
  
  # Convert age_category into one-hot encoding
  age_one_hot <- model.matrix(~ age_category - 1, data = combined)
  
  # Combine the one-hot encoding with the rest of the dataset (excluding 'age' and 'age_category')
  combined_one_hot <- cbind(combined[, !colnames(combined) %in% c("age", "age_category")], age_one_hot)
  
  return(combined_one_hot)
}



plot_evaluation <- function(eval_input){
  mse_values <- sapply(eval_input, function(x) sapply(x$mse, function(y) y[[1]])) |> colMeans()
  value_function_values <- sapply(eval_input, function(x) sapply(x$value_function, function(y) y[[1]])) |> colMeans()
  
  # Prepare data for visualization
  library(ggplot2)
  library(reshape2)
  df <- data.frame(
    Index = rep(1:length(mse_values), times = 2),
    Type = c(rep(c("MSE"), times = length(mse_values)), rep(c("Value Function"), times = length(mse_values))),
    Value = c((mse_values),(value_function_values))
  )
  
  df_mse <- df[df$Type == "MSE", ]
  df_value_function <- df[df$Type == "Value Function", ]
  scale_factor <- max(df_value_function$Value) / max(df_mse$Value)
  ggplot() +
    geom_line(data = df_mse, aes(x = Index, y = Value, color = "MSE"), size = 1) +
    geom_point(data = df_mse, aes(x = Index, y = Value, color = "MSE"), size = 3) +
    geom_line(data = df_value_function, aes(x = Index, y = Value / scale_factor, color = "Value Function"), size = 1, linetype = "dashed") +
    geom_point(data = df_value_function, aes(x = Index, y = Value / scale_factor, color = "Value Function"), size = 3, shape = 16) +
    scale_y_continuous(
      name = "MSE",
      sec.axis = sec_axis(~ . * scale_factor, name = "Value Function")
    ) +
    scale_color_manual(
      values = c("MSE" = "blue", "Value Function" = "green"),
      name = "Type"
    ) +
    labs(
      title = "MSE and Value Function",
      x = "Index"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(hjust = 0.5),
      axis.title.y.left = element_text(color = "blue"),
      axis.title.y.right = element_text(color = "green"),
      legend.position = "top"
    )
}
drop_redundant_cols <- function(mat) {
  drop_cols <- c("age_categoryBelow_55", "yearmamsum0")
  keep_cols <- setdiff(colnames(mat), drop_cols)
  mat[, keep_cols, drop = FALSE]
}
format_result <- function(nested_list){
  result <- do.call(rbind, lapply(nested_list, function(item) {
    mse_values <- unlist(item$mse)
    value_function_values <- unlist(item$value_function)
    data.frame(
      mse_1 = mse_values[1],
      mse_2 = mse_values[2],
      value_function_1 = value_function_values[1],
      value_function_2 = value_function_values[2]
    )
  }))
  result
}

split_data <- function(data, train_ratio = 0.6) {
  train_indices <- sample(seq_len(nrow(data)), size = floor(train_ratio * nrow(data)))
  train_data <- data[train_indices, ]
  test_data <- data[-train_indices, ]
  list(train = train_data, test = test_data)
}
split_into_tasks <- function(data, n_tasks = 5) {
  task_indices <- sample(rep(1:n_tasks, length.out = nrow(data)))
  tasks <- lapply(1:n_tasks, function(t) data[task_indices == t, ])
  tasks
}





cape <- read.csv("cape_pseudo.csv")
ninr <- read.csv("ninr_pseudo.csv")
cape_copy <- cape[, colnames(cape)[-c(4, 5, 6, 7, 10, 11)]]
ninr_copy <- ninr[, colnames(cape)[-c(4, 5, 6, 7, 10, 11)]]
cape_train_test <- split_data(cape_copy)
cape_train <- split_into_tasks(cape_train_test$train, 2)
cape_test <- split_into_tasks(cape_train_test$test, 2)

ninr_train_test <- split_data(ninr_copy)
ninr_train <- split_into_tasks(ninr_train_test$train, 2)
ninr_test <- split_into_tasks(ninr_train_test$test, 2)
combined <- rbind(cape_copy, ninr_copy)
combined <- na.omit(combined)






X = list()
D <- list()
task <- list()
Y <- list()
X_test = list()
D_test = list()
Y_test = list()

check_variability <- function(data) {
  sapply(data, function(column) length(unique(column)) > 1)
}
n_tasks=4
for (index in 1:2){
  cape_train[[index]] <- cape_train[[index]][apply(cape_train[[index]], 1, function(row) all(!is.na(row))), ]

  X_age <- convert_age_one_hot(cape_train[[index]][, c(5:19)]) 
  # X_age is after converted by age one hot
  X_age$yearmamsum <- as.factor(X_age$yearmamsum)

  yearmamsum_one_hot <- model.matrix(~ yearmamsum - 1, data = X_age)
  X_tmp <- cbind(X_age[, !colnames(X_age) %in% c("yearmamsum")], yearmamsum_one_hot)
  X[[index]] <- drop_redundant_cols(X_tmp)
  
  D[[index]] <- cape_train[[index]][, 3]
  Y[[index]] <- cape_train[[index]][, 4]
}

for (index in 3:4){
  ninr_train[[index-2]] <- ninr_train[[index-2]][apply(ninr_train[[index-2]], 1, function(row) all(!is.na(row))), ]

  X_age <- convert_age_one_hot(ninr_train[[index-2]][, c(5:19)]) 
  # X_age is after converted by age one hot
  X_age$yearmamsum <- as.factor(X_age$yearmamsum)

  yearmamsum_one_hot <- model.matrix(~ yearmamsum - 1, data = X_age)
  X_tmp <- cbind(X_age[, !colnames(X_age) %in% c("yearmamsum")], yearmamsum_one_hot)
  X[[index]] <- drop_redundant_cols(X_tmp)
  
  D[[index]] <- as.numeric(ninr_train[[index-2]][, 3])
  Y[[index]] <- as.numeric(ninr_train[[index-2]][, 4])
}
for(index in 1:4){
  #X[[index]] = X[[index]][ , !(colnames(X[[index]]) %in% c("racecauc"))]
  X[[index]] <- as.matrix( X[[index]])
}

for (index in 1:2){
  cape_test[[index]] <- cape_test[[index]][apply(cape_test[[index]], 1, function(row) all(!is.na(row))), ]

  X_age <- convert_age_one_hot(cape_test[[index]][, c(5:19)]) 
  # X_age is after converted by age one hot
  X_age$yearmamsum <- as.factor(X_age$yearmamsum)

  yearmamsum_one_hot <- model.matrix(~ yearmamsum - 1, data = X_age)
  X_tmp <- cbind(X_age[, !colnames(X_age) %in% c("yearmamsum")], yearmamsum_one_hot)
  X_test[[index]] <- drop_redundant_cols(X_tmp)
  
  D_test[[index]] <- cape_test[[index]][, 3]
  Y_test[[index]] <- cape_test[[index]][, 4]
}

for (index in 3:4){
  ninr_test[[index-2]] <- ninr_test[[index-2]][apply(ninr_test[[index-2]], 1, function(row) all(!is.na(row))), ]

  X_age <- convert_age_one_hot(ninr_test[[index-2]][, c(5:19)]) 
  # X_age is after converted by age one hot
  X_age$yearmamsum <- as.factor(X_age$yearmamsum)
  yearmamsum_one_hot <- model.matrix(~ yearmamsum - 1, data = X_age)
  X_tmp <- cbind(X_age[, !colnames(X_age) %in% c("yearmamsum")], yearmamsum_one_hot)
  X_test[[index]] <- drop_redundant_cols(X_tmp)
  
  D_test[[index]] <- as.numeric(ninr_test[[index-2]][, 3])
  Y_test[[index]] <- as.numeric(ninr_test[[index-2]][, 4])
}
for(index in 1:4){
  #X_test[[index]] = X_test[[index]][ , !(colnames(X_test[[index]]) %in% c("racecauc"))]

  X_test[[index]] <- as.matrix(X_test[[index]])
  # Delete raceauc

}



ntask <- 4
split_index <- list()
fit_each_site <- list()
# Min-max normalization function
normalize_min_max <- function(x, eps = 1e-12) {
  x <- as.numeric(x)
  if (all(is.na(x))) return(x)

  mn <- min(x, na.rm = TRUE)
  mx <- max(x, na.rm = TRUE)

  if (!is.finite(mn) || !is.finite(mx)) return(rep(NA_real_, length(x)))
  if (mx - mn < eps) {
    # constant (or almost constant) -> return zeros (or keep original)
    out <- rep(0, length(x))
    out[is.na(x)] <- NA_real_
    return(out)
  }

  (x - mn) / (mx - mn)
}

# Apply the function to the matrix X[[index]]
continuous_variables <- c("bar1tot", "ben1tot", "se1tot", "sus1tot", "fear1tot", "fatal1tot", "know1tot")
for (index in 1:ntask) {
  n <- dim(X[[index]])[1]
  split_index[[index]] <- sample(1:2, n, replace = TRUE)
  X_test[[index]][, continuous_variables] <- apply(X_test[[index]][, continuous_variables], 2, normalize_min_max)
}

X_colnames = colnames(X[[1]])
selected_colnames = X_colnames[!X_colnames %in% c("married", "stage", "fdrhistory", "bar1tot", "se1tot")] #"married", "stage", "fdrhistory"
continuous_variables <- continuous_variables[!(continuous_variables %in% c("bar1tot", "se1tot"))]


for (index in 1:ntask) {
  n <- dim(X[[index]])[1]
  split_index[[index]] <- sample(1:2, n, replace = TRUE)
  X_test[[index]] <- X_test[[index]][, selected_colnames]
  X[[index]] <- X[[index]][, selected_colnames]
}

for (index in 1:ntask) {
  
  
  X[[index]][, continuous_variables] <- apply(X[[index]][, continuous_variables], 2, normalize_min_max)
  X[[index]][, continuous_variables] <- apply(X[[index]][, continuous_variables], 2, normalize_min_max)
  fit_each_site[[index]] <- CATE_Per_Site(X[[index]], D[[index]], 
                                          Y[[index]], split_index=split_index[[index]], dim = 1)
}

########################################################################
########################################################################
########################################################################
ceof_sai <- list()
lambda_seq <- 10^seq(2, -2, by = -0.1)

for (index in 1:ntask) {
  # --- Train on auxiliary tasks ---
  X_aux <- do.call(rbind, X[-index])
  Y_aux <- do.call(c, Y[-index])
  D_aux <- do.call(c, D[-index])
  
  interaction_terms <- X_aux * D_aux
  lasso_X <- cbind(X_aux, D_aux, interaction_terms)
  
  lasso_fit <- cv.glmnet(lasso_X, Y_aux, alpha = 1, lambda = lambda_seq, intercept = FALSE)
  
  # Use a fixed lambda instead of the CV-selected one
  fixed_lambda <- 0.1
  beta <- coef(lasso_fit$glmnet.fit, s = fixed_lambda)[-1]
  
  p_x <- ncol(X_aux)
  interaction_coef <- beta[(p_x + 2):(2 * p_x + 1)]
  
  # --- Fine-tune on held-out task ---
  Y_transfer <- Y[[index]]
  interaction_terms <- X[[index]] * D[[index]]
  X_transfer <- cbind(X[[index]], D[[index]], interaction_terms)
  
  residuals <- Y_transfer - X_transfer %*% beta
  valid_idx <- complete.cases(X_transfer) & !is.na(residuals)
  
  X_clean <- X_transfer[valid_idx, , drop = FALSE]
  y_clean <- residuals[valid_idx]
  
  cv_fit <- cv.glmnet(x = X_clean, y = y_clean, alpha = 1, lambda = lambda_seq, intercept = FALSE)
  best_lambda <- cv_fit$lambda.min
  best_coef <- coef(cv_fit, s = best_lambda)
  
  interaction_coef_delta <- best_coef[(p_x + 2):(2 * p_x + 1)]
  beta[(p_x + 2):(2 * p_x + 1)] <- interaction_coef + interaction_coef_delta
  
  ceof_sai[[index]] <- beta
} 
print(ceof_sai)
fit_ARMUL_beta <- function(X, D, Y, ntask, split_index, number_split=2,
                           T_global_nuis=1000, T_global_step2=2000,
                           spline_nuis=TRUE) {

  # per-task lengths
  n_list <- sapply(1:ntask, function(t) nrow(X[[t]]))

  # allocate per-task nuisance preds
  mu1_hat <- lapply(1:ntask, function(t) rep(NA_real_, n_list[t]))
  mu0_hat <- lapply(1:ntask, function(t) rep(NA_real_, n_list[t]))
  e_hat   <- lapply(1:ntask, function(t) rep(NA_real_, n_list[t]))

  for (fold in 1:number_split) {
    X1 <- Y1 <- X0 <- Y0 <- Xtr <- Dtr <- vector("list", ntask)
    Xte <- vector("list", ntask)

    for (t in 1:ntask) {

      # -------- sanity checks ----------
      stopifnot(nrow(X[[t]]) == length(D[[t]]))
      stopifnot(nrow(X[[t]]) == length(Y[[t]]))
      stopifnot(nrow(X[[t]]) == length(split_index[[t]]))

      # -------- indices ----------
      idx_tr <- which(split_index[[t]] != fold)
      idx_te <- which(split_index[[t]] == fold)

      Xte[[t]] <- X[[t]][idx_te, , drop=FALSE]

      idx1 <- idx_tr[D[[t]][idx_tr] == 1]
      idx0 <- idx_tr[D[[t]][idx_tr] == 0]

      # if a fold has no treated/control, vanilla_train will likely break
      if (length(idx1) == 0 || length(idx0) == 0) {
        stop(sprintf("Task %d fold %d has empty treated/control: n1=%d n0=%d",
                     t, fold, length(idx1), length(idx0)))
      }

      X1[[t]] <- X[[t]][idx1, , drop=FALSE]
      Y1[[t]] <- Y[[t]][idx1]
      X0[[t]] <- X[[t]][idx0, , drop=FALSE]
      Y0[[t]] <- Y[[t]][idx0]

      Xtr[[t]] <- X[[t]][idx_tr, , drop=FALSE]
      Dtr[[t]] <- D[[t]][idx_tr]
    }

    mu1_model <- vanilla_train(X1, Y1, link="logistic", T_global=T_global_nuis, spline=spline_nuis)
    mu0_model <- vanilla_train(X0, Y0, link="logistic", T_global=T_global_nuis, spline=spline_nuis)
    e_model   <- vanilla_train(Xtr, Dtr, link="logistic", T_global=T_global_nuis, spline=spline_nuis)

    for (t in 1:ntask) {
      idx_te <- which(split_index[[t]] == fold)

      pred1 <- drop(vanilla_predict(mu1_model, Xte, task_id=t, link="logistic"))
      pred0 <- drop(vanilla_predict(mu0_model, Xte, task_id=t, link="logistic"))
      prede <- drop(vanilla_predict(e_model,   Xte, task_id=t, link="logistic"))

      stopifnot(length(pred1) == length(idx_te))
      stopifnot(length(pred0) == length(idx_te))
      stopifnot(length(prede) == length(idx_te))

      mu1_hat[[t]][idx_te] <- pred1
      mu0_hat[[t]][idx_te] <- pred0
      e_hat[[t]][idx_te]   <- prede
    }
  }

  clip01 <- function(p, eps=1e-3) pmin(pmax(p, eps), 1-eps)
  e_hat <- lapply(e_hat, clip01)

  # step2: cross-fit pseudo outcome
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

      pseudoY[[t]] <- (Dt==1)/et * (Yt - mu1t) -
        (Dt==0)/(1-et) * (Yt - mu0t) +
        (mu1t - mu0t)

      X_step2[[t]] <- X[[t]][idx_tr, , drop=FALSE]
    }

    models <- vanilla_train(X_step2, pseudoY, link="linear", T_global=T_global_step2, spline=FALSE)

    coef_est[[fold]] <- vector("list", ntask)
    for (t in 1:ntask) {
      b <- models$vanilla[,,1][t,]
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

  list(beta = ARMUL_beta, mu1=mu1_hat, mu0=mu0_hat, e=e_hat)
}
##############################################################
fit_pERM_beta <- function(X, D, Y, ntask, split_index, number_split=2,
                          r_mu=3, nbasis_mu=10,
                          r_e=3, nbasis_e=10,
                          r_step2=2, nbasis_step2=1) {

  # per-task lengths
  n_list <- sapply(1:ntask, function(t) nrow(X[[t]]))

  mu1_hat <- lapply(1:ntask, function(t) rep(NA_real_, n_list[t]))
  mu0_hat <- lapply(1:ntask, function(t) rep(NA_real_, n_list[t]))
  e_hat   <- lapply(1:ntask, function(t) rep(NA_real_, n_list[t]))

  # -------------------------
  # cross-fit nuisances
  # -------------------------
  for (fold in 1:number_split) {

    Xte <- vector("list", ntask)
    peRMdata <- vector("list", ntask)

    # ---- mu1(x): train on treated in each task, predict on that task's held-out fold
    for (t in 1:ntask) {
      idx_tr <- which(split_index[[t]] != fold)
      idx_te <- which(split_index[[t]] == fold)

      Xte[[t]] <- X[[t]][idx_te, , drop=FALSE]

      idx1 <- idx_tr[D[[t]][idx_tr] == 1]
      X1 <- X[[t]][idx1, , drop=FALSE]
      Y1 <- Y[[t]][idx1]

      peRMdata[[t]] <- list(X=as.matrix(X1), y=as.matrix(Y1))
    }

    m1 <- pERM_torch(peRMdata, r=r_mu, nbasis=nbasis_mu,
                     info=TRUE, link="logistic", X_test_list=Xte)

    for (t in 1:ntask) {
      idx_te <- which(split_index[[t]] == fold)
      pred <- as.numeric(m1$test_preds[[t]])
      if (length(pred) != length(idx_te)) {
        stop(sprintf("mu1 mismatch: task %d fold %d: pred=%d, idx_te=%d",
                     t, fold, length(pred), length(idx_te)))
      }
      mu1_hat[[t]][idx_te] <- pred
    }

    # ---- mu0(x)
    for (t in 1:ntask) {
      idx_tr <- which(split_index[[t]] != fold)
      idx0 <- idx_tr[D[[t]][idx_tr] == 0]
      X0 <- X[[t]][idx0, , drop=FALSE]
      Y0 <- Y[[t]][idx0]
      peRMdata[[t]] <- list(X=as.matrix(X0), y=as.matrix(Y0))
    }

    m0 <- pERM_torch(peRMdata, r=r_mu, nbasis=nbasis_mu,
                     info=TRUE, link="logistic", X_test_list=Xte)

    for (t in 1:ntask) {
      idx_te <- which(split_index[[t]] == fold)
      pred <- as.numeric(m0$test_preds[[t]])
      if (length(pred) != length(idx_te)) {
        stop(sprintf("mu0 mismatch: task %d fold %d: pred=%d, idx_te=%d",
                     t, fold, length(pred), length(idx_te)))
      }
      mu0_hat[[t]][idx_te] <- pred
    }

    # ---- e(x)
    for (t in 1:ntask) {
      idx_tr <- which(split_index[[t]] != fold)
      Xtr <- X[[t]][idx_tr, , drop=FALSE]
      Dtr <- D[[t]][idx_tr]
      peRMdata[[t]] <- list(X=as.matrix(Xtr), y=as.matrix(Dtr))
    }

    me <- pERM_torch(peRMdata, r=r_e, nbasis=nbasis_e,
                     info=TRUE, link="logistic", X_test_list=Xte)

    for (t in 1:ntask) {
      idx_te <- which(split_index[[t]] == fold)
      pred <- as.numeric(me$test_preds[[t]])
      if (length(pred) != length(idx_te)) {
        stop(sprintf("e mismatch: task %d fold %d: pred=%d, idx_te=%d",
                     t, fold, length(pred), length(idx_te)))
      }
      e_hat[[t]][idx_te] <- pred
    }
  }

  clip01 <- function(p, eps=1e-3) pmin(pmax(p, eps), 1-eps)
  e_hat <- lapply(e_hat, clip01)

  # -------------------------
  # step2: fit beta on pseudo outcome (cross-fit)
  # -------------------------
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

      pseudoY <- (Dt==1)/et * (Yt - mu1t) -
        (Dt==0)/(1-et) * (Yt - mu0t) +
        (mu1t - mu0t)

      Xtr <- X[[t]][idx_tr, , drop=FALSE]
      peRMdata[[t]] <- list(X=as.matrix(Xtr), y=as.matrix(pseudoY))
    }

    # NOTE: if pERM_torch supports link="linear", use it here.
    m2 <- pERM_torch(peRMdata, r=r_step2, nbasis=nbasis_step2,
                     info=TRUE, link="linear")

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

  list(beta = pERM_beta, mu1=mu1_hat, mu0=mu0_hat, e=e_hat)
}
########################################################################
# ---- ARMUL fit on TRAIN ----
fit_armul <- fit_ARMUL_beta(X, D, Y, ntask=ntask, split_index=split_index, number_split=2)

# ---- pERM fit on TRAIN ----
fit_perm  <- fit_pERM_beta(X, D, Y, ntask=ntask, split_index=split_index, number_split=2)

# ---- Evaluate on TEST with CATE_predict (same structure) ----
eval_ARMUL <- vector("list", ntask)
eval_pERM  <- vector("list", ntask)

#####################################################################################


# ---- Evaluate on TRAIN similarly (optional) ----
eval_ARMUL_train <- vector("list", ntask)
eval_pERM_train  <- vector("list", ntask)

for (t in 1:ntask) {
  eval_ARMUL_train[[t]] <- CATE_predict(
    X[[t]], D[[t]], Y[[t]],
    coef_estimate = c(fit_armul$beta[,t]) |> matrix(),
    nonpar_transfer = FALSE,
    number_split = 2,
    split_index = split_index[[t]],
    dim = 1, real_data=FALSE
  )

  eval_pERM_train[[t]] <- CATE_predict(
    X[[t]], D[[t]], Y[[t]],
    coef_estimate = c(fit_perm$beta[,t]) |> matrix(),
    nonpar_transfer = FALSE,
    number_split = 2,
    split_index = split_index[[t]],
    dim = 1, real_data=FALSE
  )
}
max.dim <- 1
p <- dim(X[[1]])[2]
# tranfer learning update no nonpar transfer (main node)
Para_transfer <- function() {
  fit <- NULL
  lambda <- NULL
  for (dr.dim in 1:max.dim) {
    fit[[dr.dim]] <- list()
    for (fold in 1:2) {
      ## Gradient and Hessian
      gradient <- hessian <- NULL
      for (index in 1:ntask) {
        gradient[[index]] <- fit_each_site[[index]]$gradient[[fold]][[dr.dim]]
        hessian[[index]] <- fit_each_site[[index]]$hessian[[fold]][[dr.dim]]
      }

      ## Initial value
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
      ## Gradient and Hessian
      gradient <- hessian <- NULL
      for (index in 1:ntask) {
        gradient[[index]] <- fit_each_site[[index]]$gradient[[fold]][[dr.dim]]
        hessian[[index]] <- fit_each_site[[index]]$hessian[[fold]][[dr.dim]]
      }

      ## Initial value
      initial_value <- list()
      for (index in 1:ntask) {
        initial_value[[index]] <- c(t(fit_each_site[[index]]$coef_estimate[[fold]][[dr.dim]][-(1:dr.dim), ]))
      }
      fit[[dr.dim]][[fold]] <- SemiTransfer_Par(gradient,
                                                hessian,
                                                initial_value,
                                                type = "CATE",
                                                lambda = lambda)
    }
  }
  ## tuning optimal lambda
  ### get coefficients
  coef_candidate <- list()
  for (index in 1:ntask) {
    coef_candidate[[index]] <- list()
    for (dr.dim in 1:max.dim) {
      coef_candidate[[index]][[dr.dim]] <- list()
      for (fold in 1:2) {
        ncoef <- dr.dim * p - dr.dim * dr.dim
        coef_candidate[[index]][[dr.dim]][[fold]] <- fit[[dr.dim]][[fold]]$fit$gglasso.fit$beta[((index - 1) * ncoef + 1):(index * ncoef), ] +
          fit[[dr.dim]][[fold]]$fit$gglasso.fit$beta[(ntask * ncoef +
                                                        1):((ntask + 1) * ncoef), ]
      }
    }
  }
  ### cross-validation to tune on split dataset
  fit_tuned <- coef_est <- NULL
  error <- array(0, c(ntask, length(lambda)))
  for (index in 1:ntask) {
    fit_tuned[[index]] <- CATE_tune_Per_Site(
      coef_candidate[[index]],
      X[[index]],
      D[[index]],
      Y[[index]],
      split_index = split_index[[index]],
      max.dim = max.dim,
      nfold = 2,
      lambda = lambda
    )
    error[index, ] <- fit_tuned[[index]]$error
  }
  error.all.task <- apply(error, 2, mean)
  for (index in 1:ntask) {
    coef_est[[index]] <- (coef_candidate[[index]][[1]][[1]][, which.min(error.all.task)] +
                            coef_candidate[[index]][[1]][[2]][, which.min(error.all.task)]) / 2
  }
  list(tuned = coef_est,
       untuned = (fit[[1]][[1]]$coef + fit[[1]][[2]]$coef) / 2)
}
coef_para <- Para_transfer()
coef_est <- coef_para$tuned
coef_est_untuned <- coef_para$untuned

eval_para_transfer_tuned <- list()
split_index_test <- list()
for (index in 1:ntask) {
  n <- dim(X_test[[index]])[1]
  split_index_test[[index]] <- sample(1:2, n, replace = TRUE)
}
for (index in 1:ntask){
  eval_para_transfer_tuned[[index]] <- CATE_predict(X_test[[index]], D_test[[index]], Y_test[[index]],
                                              c(1, coef_est[[index]]) |> matrix(),nonpar_transfer = FALSE,
                                               number_split=2, split_index = split_index_test[[index]], dim=1)
}
eval_para_transfer_tuned

eval_para_transfer_untuned <- list()
for (index in 1:ntask){
  eval_para_transfer_untuned[[index]] <- CATE_predict(X_test[[index]], D_test[[index]], Y_test[[index]],
                                              c(1, coef_est_untuned[, index]) |> matrix(),nonpar_transfer = FALSE,
                                               number_split=2, split_index = split_index_test[[index]], dim=1)
}
eval_para_transfer_untuned

for (t in 1:ntask) {
  eval_ARMUL[[t]] <- CATE_predict(
    X_test[[t]], D_test[[t]], Y_test[[t]],
    coef_estimate = c(fit_armul$beta[,t]) |> matrix(),
    nonpar_transfer = FALSE,
    number_split = 2,
    split_index = split_index_test[[t]],
    dim = 1, real_data=FALSE
  )

  eval_pERM[[t]] <- CATE_predict(
    X_test[[t]], D_test[[t]], Y_test[[t]],
    coef_estimate = c(fit_perm$beta[,t]) |> matrix(),
    nonpar_transfer = FALSE,
    number_split = 2,
    split_index = split_index_test[[t]],
    dim = 1, real_data=FALSE
  )
}

##############################################################
##############################################################
##############################################################
eval_Sai <- list()
for (index in 1:ntask){
  X_aux <- X_test[[index]]
  Y_aux <- Y_test[[index]]
  D_aux <- D_test[[index]]
  interaction_terms <- X_aux * D_aux
  lasso_X <- cbind(X_aux, D_aux, interaction_terms)
  beta_sai <- ceof_sai[[index]]
  err_sai <- Y_aux - lasso_X %*% beta_sai
  result_sai <- list(mse=mean(err_sai^2), value_function=mean(err_sai^2), f_hat=mean(err_sai^2))
  eval_Sai[[index]] <- result_sai
}
##############################################################
##############################################################
##############################################################

# Data Pooling Method
#############################################################################################################################
##############################################################################################################################
##############################################################################################################################
# ----------------------------
# POOLED preprocessing (single dataset)
# ----------------------------

# 1) load + same column drops
cape <- read.csv("cape_pseudo.csv")
ninr <- read.csv("ninr_pseudo.csv")


cape_copy <- cape[, colnames(cape)[-c(4, 5, 6, 7, 10, 11)]]
ninr_copy <- ninr[, colnames(cape)[-c(4, 5, 6, 7, 10, 11)]]

pooled <- rbind(cape_copy, ninr_copy)
pooled <- pooled[apply(pooled, 1, function(row) all(!is.na(row))), ]  # match your per-site NA-row removal

# 2) same split function
pooled_train_test <- split_data(pooled, train_ratio = 0.6)
pooled_train <- pooled_train_test$train
pooled_test  <- pooled_train_test$test

# 3) same feature builder (age one-hot + yearmamsum one-hot)
build_XDY <- function(df_raw) {
  # X uses cols 5:19 in your code
  X_age <- convert_age_one_hot(df_raw[, c(5:19)])
  X_age$yearmamsum <- as.factor(X_age$yearmamsum)
  yearmamsum_one_hot <- model.matrix(~ yearmamsum - 1, data = X_age)

  X_df <- cbind(X_age[, !colnames(X_age) %in% c("yearmamsum")], yearmamsum_one_hot)
  X_df <- drop_redundant_cols(X_df)
  X_mat <- as.matrix(X_df)

  D_vec <- as.numeric(df_raw[, 3])
  Y_vec <- as.numeric(df_raw[, 4])

  list(X = X_mat, D = D_vec, Y = Y_vec)
}

pool_tr <- build_XDY(pooled_train)
pool_te <- build_XDY(pooled_test)

X_pool_train <- pool_tr$X
D_pool_train <- pool_tr$D
Y_pool_train <- pool_tr$Y

X_pool_test <- pool_te$X
D_pool_test <- pool_te$D
Y_pool_test <- pool_te$Y

# 4) robust min-max (your style, but safe)
normalize_min_max <- function(x, mn, mx, eps = 1e-12) {
  x <- as.numeric(x)
  if (all(is.na(x))) return(x)

  if (!is.finite(mn) || !is.finite(mx)) return(rep(NA_real_, length(x)))
  if (mx - mn < eps) {
    out <- rep(0, length(x))
    out[is.na(x)] <- NA_real_
    return(out)
  }
  (x - mn) / (mx - mn)
}

# 5) choose columns like you did
X_colnames <- colnames(X_pool_train)

selected_colnames <- X_colnames[!X_colnames %in% c("married", "stage", "fdrhistory", "bar1tot", "se1tot")]
X_pool_train <- X_pool_train[, selected_colnames, drop = FALSE]
X_pool_test  <- X_pool_test[,  selected_colnames, drop = FALSE]

continuous_variables <- c("bar1tot", "ben1tot", "se1tot", "sus1tot", "fear1tot", "fatal1tot", "know1tot")
continuous_variables <- continuous_variables[continuous_variables %in% colnames(X_pool_train)]
continuous_variables <- continuous_variables[!(continuous_variables %in% c("bar1tot", "se1tot"))]  # match your removal

# 6) IMPORTANT: fit min/max on TRAIN, apply to TRAIN+TEST
train_minmax <- lapply(continuous_variables, function(v) {
  mn <- min(X_pool_train[, v], na.rm = TRUE)
  mx <- max(X_pool_train[, v], na.rm = TRUE)
  list(mn = mn, mx = mx)
})
names(train_minmax) <- continuous_variables

for (v in continuous_variables) {
  mn <- train_minmax[[v]]$mn
  mx <- train_minmax[[v]]$mx
  X_pool_train[, v] <- normalize_min_max(X_pool_train[, v], mn, mx)
  X_pool_test[,  v] <- normalize_min_max(X_pool_test[,  v], mn, mx)
}

# 7) pooled split_index (same as you did)
set.seed(seed)
pooled_split_index <- sample(1:2, nrow(X_pool_train), replace = TRUE)
pooled_split_index_test <- sample(1:2, nrow(X_pool_test), replace = TRUE)
pooled_fit <- CATE_Per_Site(
  X_pool_train, D_pool_train, Y_pool_train,
  split_index = pooled_split_index,
  dim = 1, real_data=FALSE
)

# If you want evaluate on pooled test:
pooled_coef <- 0.5 * (pooled_fit$coef_estimate[[1]][[1]] + pooled_fit$coef_estimate[[2]][[1]])

eval_pool <- CATE_predict(
  X_pool_test, D_pool_test, Y_pool_test,
  pooled_coef,
  split_index = pooled_split_index_test,
  number_split = 2,
  nonpar_transfer = FALSE,
  propensity_score = NULL, mu0 = NULL, mu1 = NULL,
  dim = 1
)
print(eval_pool)
########################################################################
########################################################################
########################################################################


#initial value
coef_est_no_transfer <- NULL
for (index in 1:ntask) {
  coef_est_no_transfer <- cbind(
    coef_est_no_transfer,
    0.5 * (
      fit_each_site[[index]]$coef_estimate[[1]][[1]] + fit_each_site[[index]]$coef_estimate[[2]][[1]]
    )
  )
}
print(coef_est_no_transfer)

eval_no_transfer <- list()

for (index in 1:ntask){
  eval_no_transfer[[index]] <- CATE_predict(X_test[[index]], D_test[[index]], Y_test[[index]], coef_est_no_transfer[, index], split_index=NULL, number_split=2,nonpar_transfer=FALSE, propensity_score=NULL, mu0=NULL, mu1=NULL, dim=1)
}
eval_no_transfer


# Method wit Nonpar Transfer
## generate common grid
grid <- list()
total_sample_size <- n * ntask
for (index in 1:ntask){
  grid[[index]] <- list()
  for(fold in 1:2){
    grid[[index]][[fold]]<- get_grid_from_each_site(X=X[[index]],
                                                    total_sample_size, method="noise")
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
Y1 <- Y0 <- X1 <- X0 <- split_index1 <- split_index0 <-NULL
for (index in 1:ntask) {
  Y1[[index]] <- Y[[index]][D[[index]]==1]
  Y0[[index]] <- Y[[index]][D[[index]]==0]
  X1[[index]] <- X[[index]][D[[index]]==1,]
  X0[[index]] <- X[[index]][D[[index]]==0,]
  split_index1[[index]] <- split_index[[index]][D[[index]]==1]
  split_index0[[index]] <- split_index[[index]][D[[index]]==0]
}
mu1_opt <- transfer_Y_given_X(Y=Y1, X=X1, split_index = split_index1, split_index.test = split_index, X.test=X)
mu0_opt <- transfer_Y_given_X(Y=Y0, X=X0, split_index = split_index0, split_index.test = split_index, X.test=X)
D_given_X_opt <- transfer_Y_given_X(Y=D, X=X, split_index = split_index, split_index.test = split_index, X.test=X)

for (index in 1:ntask) {
  Y1[[index]] <- Y_test[[index]][D_test[[index]]==1]
  Y0[[index]] <- Y_test[[index]][D_test[[index]]==0]
  X1[[index]] <- X_test[[index]][D_test[[index]]==1,]
  X0[[index]] <- X_test[[index]][D_test[[index]]==0,]
  split_index1[[index]] <- split_index_test[[index]][D_test[[index]]==1]
  split_index0[[index]] <- split_index_test[[index]][D_test[[index]]==0]
}
mu1_opt_test <- transfer_Y_given_X(Y=Y1, X=X1, split_index = split_index1, split_index.test = split_index_test, X.test=X_test)
mu0_opt_test <- transfer_Y_given_X(Y=Y0, X=X0, split_index = split_index0, split_index.test = split_index_test, X.test=X_test)
D_given_X_opt_test <- transfer_Y_given_X(Y=D, X=X, split_index = split_index, split_index.test = split_index_test, X.test=X_test)



# each fit gradient and hessian for parametric
fit_each_site_nonpar_tranfer <- NULL
for (index in 1:ntask){
  fit_each_site_nonpar_tranfer[[index]] <- CATE_Per_Site(X[[index]], D[[index]], Y[[index]], nonpar_transfer = TRUE,
                                                         propensity_score = D_given_X_opt[[index]],
                                                         mu0 = mu0_opt[[index]],
                                                         mu1 = mu1_opt[[index]],
                                                         split_index = split_index[[index]], dim = 1)
}



# tranfer learning update with nonpar transfer (main node)
Semipara_Transfer <- function(){
  fit_both <- NULL
  lambda <- NULL
  for (dr.dim in 1:1){
    fit_both[[dr.dim]] <- list()
    for (fold in 1:2){
      ## Gradient and Hessian
      gradient <- hessian <- NULL
      for (index in 1:ntask) {
        gradient[[index]] <- fit_each_site_nonpar_tranfer[[index]]$gradient[[fold]][[dr.dim]]
        hessian[[index]] <- fit_each_site_nonpar_tranfer[[index]]$hessian[[fold]][[dr.dim]]
      }

      ## Initial value
      initial_value <- list()
      for (index in 1:ntask) {
        initial_value[[index]] <- fit_each_site_nonpar_tranfer[[index]]$coef_estimate[[fold]][[1]][-1]
      }
      fit_both[[dr.dim]][[fold]] <- SemiTransfer_Par(gradient, hessian, initial_value=initial_value,
                                                     type = "CATE")
      lambda <- c(lambda, fit_both[[dr.dim]][[fold]]$lambda)
    }
  }
  lambda <- sort(unique(lambda))
  for (dr.dim in 1:1){
    fit_both[[dr.dim]] <- list()
    for (fold in 1:2){
      ## Gradient and Hessian
      gradient <- hessian <- NULL
      for (index in 1:ntask) {
        gradient[[index]] <- fit_each_site_nonpar_tranfer[[index]]$gradient[[fold]][[dr.dim]]
        hessian[[index]] <- fit_each_site_nonpar_tranfer[[index]]$hessian[[fold]][[dr.dim]]
      }

      ## Initial value
      initial_value <- list()
      for (index in 1:ntask) {
        initial_value[[index]] <- fit_each_site_nonpar_tranfer[[index]]$coef_estimate[[fold]][[1]][-1]
      }
      fit_both[[dr.dim]][[fold]] <- SemiTransfer_Par(gradient, hessian, initial_value=initial_value,
                                                     type = "CATE", lambda=lambda)
    }
  }
  ## tuning optimal lambda
  ### get coefficients
  coef_candidate <- list()
  for (index in 1:ntask){
    coef_candidate[[index]] <- list()
    for (dr.dim in 1:1){
      coef_candidate[[index]][[dr.dim]] <- list()
      for (fold in 1:2){
        ncoef <- dr.dim*p-dr.dim*dr.dim
        coef_candidate[[index]][[dr.dim]][[fold]] <- fit_both[[dr.dim]][[fold]]$fit$gglasso.fit$beta[((index-1)*ncoef+1):(index*ncoef),]+
          fit_both[[dr.dim]][[fold]]$fit$gglasso.fit$beta[(ntask*ncoef+1):((ntask+1)*ncoef),]
      }
    }
  }
  ### cross-validation to tune on split dataset
  fit_tuned <- coef_est_both <- NULL
  error <- array(0, c(ntask, length(lambda)))
  for (index in 1:ntask){
    fit_tuned[[index]] <- CATE_tune_Per_Site(
      coef_candidate[[index]],
      X[[index]],
      D[[index]],
      Y[[index]],
      split_index = split_index[[index]],
      max.dim = max.dim,
      nfold = 2,
      lambda = lambda
    )
    error[index,] <- fit_tuned[[index]]$error
  }
  error.all.task <- apply(error,2,mean)
  for (index in 1:ntask){
    coef_est_both[[index]] <- (coef_candidate[[index]][[1]][[1]][,which.min(error.all.task)]+
                                 coef_candidate[[index]][[1]][[2]][,which.min(error.all.task)])/2
  }
  return(list(tuned=coef_est_both, untuned=(fit_both[[1]][[1]]$coef+fit_both[[1]][[2]]$coef)/2))
}
coef_semipara <- Semipara_Transfer()
coef_est_both <- coef_semipara$tuned
coef_est_both_untuned <- coef_semipara$untuned


eval_semipara_transfer_untuned <- list()
for (index in 1:ntask){
  eval_semipara_transfer_untuned[[index]] <- CATE_predict(X_test[[index]], D_test[[index]], Y_test[[index]],
                                              c(1, coef_est_both_untuned[,index]) |> matrix(),nonpar_transfer = TRUE,
                                               number_split=2, propensity_score= D_given_X_opt_test[[index]], 
                                              mu0 = mu0_opt_test[[index]], mu1 = mu1_opt_test[[index]],split_index = split_index_test[[index]], dim=1)
}

eval_semipara_transfer_tuned <- list()
for (index in 1:ntask){
  eval_semipara_transfer_tuned[[index]] <- CATE_predict(X_test[[index]], D_test[[index]], Y_test[[index]],
                                              c(1, coef_est_both[[index]]) |> matrix(),nonpar_transfer = TRUE,
                                               number_split=2, propensity_score= D_given_X_opt_test[[index]], 
                                              mu0 = mu0_opt_test[[index]], mu1 = mu1_opt_test[[index]],split_index = split_index_test[[index]], dim=1)
}

eval_semipara_transfer_untuned
plot_evaluation(eval_semipara_transfer_untuned)

eval_semipara_transfer_tuned
plot_evaluation(eval_semipara_transfer_tuned)
format_result(eval_semipara_transfer_untuned)
format_result(eval_semipara_transfer_tuned)

res <- list(
  eval_para_transfer_tuned = eval_para_transfer_tuned,
  eval_para_transfer_untuned = eval_para_transfer_untuned,
  eval_no_transfer = eval_no_transfer,
  eval_semipara_transfer_untuned = eval_semipara_transfer_untuned,
  eval_semipara_transfer_tuned = eval_semipara_transfer_tuned,
  eval_Sai = eval_Sai
)
format_list_to_df <- function(eval_list) {
  # Initialize an empty data frame
  result_df <- data.frame(
    Model = character(),
    Subgroup = integer(),
    MSE = numeric(),
    Value_Function = numeric(),
    stringsAsFactors = FALSE
  )
  
  # Iterate over the main list
  for (model_name in names(eval_list)) {
    # Iterate over each subgroup in the current model
    for (i in seq_along(eval_list[[model_name]])) {
      mse_list <- eval_list[[model_name]][[i]]$mse
      value_list <- eval_list[[model_name]][[i]]$value_function
      
      # Iterate over mse and value_function pairs
      for (j in seq_along(mse_list)) {
        mse_value <- mse_list[[j]][[1]]
        value_function_value <- value_list[[j]][[1]]
        
        # Add a row to the result data frame
        result_df <- rbind(result_df, data.frame(
          Model = model_name,
          Subgroup = i,
          MSE = mse_value,
          Value_Function = value_function_value
        ))
      }
    }
  }
  
  return(result_df)
}

res <- format_list_to_df(res)
mean_mse_by_model <- aggregate(Value_Function ~ Model, data = res, FUN = mean)
mean_mse_by_model                                                                                                                                       

# ---------- Evaluate Sai (your lasso-transfer) on TRAIN ----------
eval_Sai_train <- vector("list", ntask)
for (index in 1:ntask) {
  X_aux <- X[[index]]
  Y_aux <- Y[[index]]
  D_aux <- D[[index]]
  interaction_terms <- X_aux * D_aux
  lasso_X <- cbind(X_aux, D_aux, interaction_terms)
  beta_sai <- ceof_sai[[index]]
  err_sai <- Y_aux - lasso_X %*% beta_sai
  eval_Sai_train[[index]] <- list(mse=mean(err_sai^2), value_function=mean(err_sai^2), f_hat=mean(err_sai^2))
}

# ---------- Evaluate parametric transfer on TRAIN ----------
eval_para_transfer_tuned_train <- vector("list", ntask)
eval_para_transfer_untuned_train <- vector("list", ntask)

for (index in 1:ntask) {
  eval_para_transfer_tuned_train[[index]] <-
    CATE_predict(
      X[[index]], D[[index]], Y[[index]],
      c(1, coef_est[[index]]) |> matrix(),
      nonpar_transfer = FALSE,
      number_split = 2,
      split_index = split_index[[index]],
      dim = 1
    )

  eval_para_transfer_untuned_train[[index]] <-
    CATE_predict(
      X[[index]], D[[index]], Y[[index]],
      c(1, coef_est_untuned[, index]) |> matrix(),
      nonpar_transfer = FALSE,
      number_split = 2,
      split_index = split_index[[index]],
      dim = 1
    )
}

# ---------- Evaluate no-transfer on TRAIN ----------
eval_no_transfer_train <- vector("list", ntask)
for (index in 1:ntask) {
  eval_no_transfer_train[[index]] <-
    CATE_predict(
      X[[index]], D[[index]], Y[[index]],
      coef_est_no_transfer[, index],
      split_index = NULL, number_split = 2,
      nonpar_transfer = FALSE,
      propensity_score = NULL, mu0 = NULL, mu1 = NULL,
      dim = 1
    )
}

# ---------- Evaluate semipara (nonpar transfer) on TRAIN ----------
eval_semipara_transfer_untuned_train <- vector("list", ntask)
eval_semipara_transfer_tuned_train   <- vector("list", ntask)

for (index in 1:ntask) {
  eval_semipara_transfer_untuned_train[[index]] <-
    CATE_predict(
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

  eval_semipara_transfer_tuned_train[[index]] <-
    CATE_predict(
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

res <- list(
  eval_para_transfer_tuned = eval_para_transfer_tuned,
  eval_para_transfer_untuned = eval_para_transfer_untuned,
  eval_no_transfer = eval_no_transfer,
  eval_pool = eval_pool,
  eval_semipara_transfer_untuned = eval_semipara_transfer_untuned,
  eval_semipara_transfer_tuned = eval_semipara_transfer_tuned,
  eval_Sai = eval_Sai,

  eval_ARMUL = eval_ARMUL,
  eval_pERM  = eval_pERM,

  eval_ARMUL_train = eval_ARMUL_train,
  eval_pERM_train  = eval_pERM_train,

  beta_ARMUL = fit_armul$beta,
  beta_pERM  = fit_perm$beta
)


save(res, file = file_name)
}





args <- commandArgs(trailingOnly = TRUE)
seed <- as.numeric(args[1])         # First argument passed

cat(seed)
eval_function(seed)



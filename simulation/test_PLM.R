script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_arg) != 1L) stop("Run this simulation with Rscript.", call. = FALSE)
script_path <- normalizePath(sub("^--file=", "", script_arg[[1L]]), mustWork = TRUE)
source(file.path(dirname(script_path), "reproducibility_helpers.R"))
repo_root <- simulation_repo_root()
# multi source partial linear model
run_simulation <- function(seed, n, similarity, dim, lambda_length){
  
ntask <- 5
n <- n # vary this from 200 to 500
p <- dim
similarity <- similarity #vary this from 1, 0.8, 0.6, 0.4
cpu_device <- seed_reproducibly(seed)

dictionary_mse <- ensure_output_dir(file.path(
  output_root, paste0("results_11_dim", dim),
  paste0("mse_n_", n, "_simi_", similarity, "lambda_len", lambda_length)
))
filename <- file.path(dictionary_mse, paste0("mse_data_seed_", seed, ".rds"))
dictionary_estimate <- ensure_output_dir(file.path(
  output_root, paste0("results_11_dim", dim),
  paste0("est_n_", n, "_simi_", similarity, "lambda_len", lambda_length)
))
filename_estimates <- file.path(dictionary_estimate, paste0("estimate_data_seed_", seed, ".rds"))
dictionary_time <- ensure_output_dir(file.path(
  output_root, paste0("results_11_dim", dim),
  paste0("_n_", n, "_simi_", similarity, "lambda_len", lambda_length)
))
#if (file.exists(filename)) {
#  cat("File for seed", seed, "already exists. Skipping this seed.\n")
#  return(NULL)  
#}
cat("Start the simulation for seed ",seed, "n", n, "similarity", similarity)
effect_common <- 2
X <- Y <- D <- effect <- NULL
for (index in 1:ntask) {
  X[[index]] <- matrix(rnorm(n * p), n, p)

  D[[index]] <- 0.25*(X[[index]][,1])^2+(X[[index]][,2])^2 + 
    rnorm(1)*(1-similarity)*((X[[index]][,3])^2+(X[[index]][,4])^2-2)*(index>3)+ rnorm(n)*0.5
  effect[[index]] <- effect_common+rnorm(1)*0.1*(1-similarity)+(1-similarity)*(index>4)*0.1 # changed from 0.05 to 0.1
  Y[[index]] <- D[[index]]*effect[[index]]+2*((rowMeans(X[[index]]))^2+4*(rowMeans(X[[index]]))^3)+ rnorm(n) #previous is 5


  #X = matrix(rnorm(n_obs*n_vars), nrow=n_obs, ncol=n_vars)
  #  d = X[,1]*X[,5]+ X[,7]^4 + rnorm(n_obs)
  #  y = theta[i]*d + sin(X[,2])+exp(X[,3])+(X[,6])^2 + rnorm(n_obs)
}

# generate split_index
split_index <- NULL
for (index in 1:ntask){
  split_index[[index]] <- sample(1:2, n, replace = TRUE)
}

# Method without Nonpar Transfer
# each site no nonpar transfer
##############################################################################################################################
##############################################################################################################################
##############################################################################################################################

Sai_transfer <- list()

for (index in 1:ntask){
  X_aux <- do.call(rbind, X[-index])
  Y_aux <- do.call(c, Y[-index])
  D_aux <- do.call(c, D[-index])
  lasso_X <- cbind(X_aux, D_aux)
  lasso_fit <- cv.glmnet(lasso_X, Y_aux, alpha = 1, intercept = FALSE)
  coef_vec_aux <- as.vector(coef(lasso_fit, s = "lambda.min"))

  pseudo.X <- cbind(X[[index]], D[[index]])
  pseudo_y <- Y[[index]] - pseudo.X%*%coef_vec_aux[-1]
  lambda_seq <- 10^seq(2, -3, by = -0.1)
  cv_fit <- cv.glmnet(x = (pseudo.X), y = pseudo_y, alpha = 1, lambda = lambda_seq, intercept = FALSE)
  coef_vec <- as.vector(coef(cv_fit, s = "lambda.min"))
  coef_axr  <- coef_vec[length(coef_vec)]
  Sai_transfer[[index]] <- coef_vec_aux[length(coef_vec)] + coef_axr
}
##############################################################################################################################
##############################################################################################################################
##############################################################################################################################

# Method of RsNet
##############################################################################################################################
##############################################################################################################################
##############################################################################################################################
Net_transfer <- list()
for (index in 1:ntask){
  proc <- process_for_rtl(X, D, Y, effect, target_indx = index, method="PLM")

  str(proc, max.level = 1) 
  #X_list is D from source data
  #Z_list is X from source data
  #y_list is Y from source data
  fit_src <- fit_sources(
    proc$X_list, proc$Z_list, proc$y_list,
    hidden = c(5,3), p = 1, epochs = 9000,
    device = cpu_device
  )
  fit_tgt <- fit_target_ols(fit_src, proc$X0, proc$Z0, proc$y0)
  Net_transfer[[index]] <- fit_tgt$coef[1]
  print("NET TRANSFER")
  print(fit_tgt$coef)
  print(fit_tgt$coef[1])
}

##############################################################################################################################
##############################################################################################################################
##############################################################################################################################

# Method of ARMUL_LASSO
##############################################################################################################################
##############################################################################################################################
##############################################################################################################################



suppressPackageStartupMessages({
  library(splines)
  library(gglasso)
})


# assumes you already defined: seed, ntask, n, p
# and set similarity=1 as in your snippet
set.seed(seed)


number_split <- 2
sample_size  <- length(Y[[1]])
index_select <- sample(1:number_split, sample_size, replace = TRUE)

# ----------------------------
# 2) (Optional) Freeze spline basis
# ----------------------------
library(splines)
library(gglasso)

# ----------------------------
# ----------------------------
freeze_spline_funs <- function(X_list, df = 10, boundary_expand = 0.40, clamp = FALSE) {
  d <- ncol(X_list[[1]])
  spline_funs <- vector("list", d)
  
  for (j in 1:d) {
    pooled_x <- unlist(lapply(X_list, function(X) as.numeric(X[, j])))
    
    xmin <- min(pooled_x, na.rm = TRUE)
    xmax <- max(pooled_x, na.rm = TRUE)
    rng  <- xmax - xmin
    if (!is.finite(rng) || rng == 0) rng <- 1
    
    bmin <- xmin - boundary_expand * rng
    bmax <- xmax + boundary_expand * rng
    
    B_pool <- splines::bs(
      pooled_x, df = df, degree = 3, intercept = TRUE,
      Boundary.knots = c(bmin, bmax)
    )
    
    knots_j     <- attr(B_pool, "knots")
    bknots_j    <- attr(B_pool, "Boundary.knots")
    degree_j    <- attr(B_pool, "degree")
    intercept_j <- attr(B_pool, "intercept")
    
    spline_funs[[j]] <- function(x) {
      x <- as.numeric(x)
      if (clamp) x <- pmin(pmax(x, bknots_j[1]), bknots_j[2])
      splines::bs(
        x,
        knots = knots_j,
        Boundary.knots = bknots_j,
        degree = degree_j,
        intercept = intercept_j
      )
    }
  }
  spline_funs
}

expand_with_frozen_splines <- function(X, spline_funs) {
  blocks <- lapply(seq_len(ncol(X)), function(j) spline_funs[[j]](X[, j]))
  do.call(cbind, blocks)
}

# ----------------------------
# Correct stacked design for Theta_j = gamma - v_j
# group: length = ncol(Xbig)
# pf:    length = number_of_groups (NOT number of columns)
# ----------------------------
build_mt_design <- function(Xs_list) {
  m <- length(Xs_list)
  p_eff <- ncol(Xs_list[[1]])
  n_list <- sapply(Xs_list, nrow)
  N <- sum(n_list)
  
  # columns: [gamma (p_eff)] + [v1 (p_eff)] + ... + [vm (p_eff)]
  Ptot <- p_eff + m * p_eff
  Xbig <- matrix(0, nrow = N, ncol = Ptot)
  
  row_start <- 1L
  for (j in 1:m) {
    nj <- n_list[j]
    rows <- row_start:(row_start + nj - 1L)
    
    # gamma block appears in every task
    Xbig[rows, 1:p_eff] <- Xs_list[[j]]
    
    # v_j block only for task j, with minus sign => gamma - v_j
    col_start <- p_eff + (j - 1L) * p_eff + 1L
    col_end   <- p_eff + j * p_eff
    Xbig[rows, col_start:col_end] <- -Xs_list[[j]]
    
    row_start <- row_start + nj
  }
  
  # GROUPS (must be 1..G):
  # gamma: each coefficient its own group: 1..p_eff
  # each v_j block is one group: (p_eff+1)..(p_eff+m)
  group_gamma <- 1:p_eff
  group_v <- rep(p_eff + (1:m), each = p_eff)
  group <- c(group_gamma, group_v)
  
  G <- p_eff + m
  
  # penalty factor PER GROUP:
  # gamma groups unpenalized => 0
  # v groups penalized => 1 (lambda chosen by CV)
  pf_group <- c(rep(0, p_eff), rep(1, m))
  
  stopifnot(length(group) == ncol(Xbig))
  stopifnot(length(pf_group) == G)
  
  list(Xbig = Xbig, group = group, pf_group = pf_group, p_eff = p_eff)
}

# ----------------------------
# Fit multi-task model with CV-selected lambda from cv.gglasso
# ----------------------------
mt_fit_cv <- function(X_list, y_list,
                      spline = TRUE, df = 10,
                      boundary_expand = 0.40,
                      clamp = FALSE,
                      seed = 1,
                      nfolds = 5,
                      lambda_choice = c("min", "1se")) {
  
  set.seed(seed)
  lambda_choice <- match.arg(lambda_choice)
  
  m <- length(X_list)
  y_list <- lapply(y_list, function(y) as.numeric(y))
  
  # expand X
  if (spline) {
    spline_funs <- freeze_spline_funs(X_list, df = df, boundary_expand = boundary_expand, clamp = clamp)
    Xs_list <- lapply(X_list, expand_with_frozen_splines, spline_funs = spline_funs)
  } else {
    spline_funs <- NULL
    Xs_list <- X_list
  }
  
  ybig <- unlist(y_list)
  
  built <- build_mt_design(Xs_list)
  Xbig <- built$Xbig
  group <- built$group
  pf_group <- built$pf_group
  p_eff <- built$p_eff
  
  # CV picks lambda automatically
  cvfit <- cv.gglasso(
    x = Xbig, y = ybig,
    group = group,
    loss = "ls",
    pf = pf_group,     
    intercept = F,
    nfolds = nfolds
  )
  
  lam <- if (lambda_choice == "min") cvfit$lambda.min else cvfit$lambda.1se
  
  cf <- coef(cvfit, s = lam)
  a0 <- as.numeric(cf[1, 1])
  
  # remaining rows are coefficients
  b <- matrix(as.numeric(cf[-1, 1]), ncol = 1)
  
  gamma <- b[1:p_eff, , drop = FALSE]
  
  Theta_list <- vector("list", m)
  for (j in 1:m) {
    idx <- (p_eff + (j - 1L) * p_eff + 1):(p_eff + j * p_eff)
    vj <- b[idx, , drop = FALSE]
    Theta_list[[j]] <- gamma - vj
  }
  
  list(
    cvfit = cvfit,
    lambda = lam,
    intercept = a0,
    Theta_list = Theta_list,
    spline_funs = spline_funs
  )
}

mt_predict <- function(model, X_test_list, task_id) {
  spline_funs <- model$spline_funs
  Theta <- model$Theta_list[[task_id]]  # p_eff x 1
  
  X_task <- X_test_list[[task_id]]
  Xs_test <- NULL
  for (j in 1:ncol(X_task)) {
    if (is.null(spline_funs)) {
      Xs_j <- X_task[, j, drop = FALSE]
    } else {
      Xs_j <- spline_funs[[j]](X_task[, j])
    }
    Xs_test <- cbind(Xs_test, Xs_j)
  }
  
  as.numeric(model$intercept + Xs_test %*% Theta)
}


# ----------------------------
# 5) ARMUL using gglasso-CV in place of tune_lambda_vanilla + vanilla_train
# ----------------------------
ARMUL_D_res <- vector("list", ntask)
ARMUL_Y_res <- vector("list", ntask)

for (index in 1:ntask) {
  
  D_given_X <- rep(NA_real_, sample_size)
  Y_given_X <- rep(NA_real_, sample_size)
  
  for (split_id in 1:number_split) {
    
    idx_tr <- which(index_select == split_id)
    idx_te <- which(index_select != split_id)
    
    X_train <- lapply(X, function(t) t[idx_tr, , drop = FALSE])
    D_train <- lapply(D, function(t) t[idx_tr])
    Y_train <- lapply(Y, function(t) t[idx_tr])
    
    X_test  <- lapply(X, function(t) t[idx_te, , drop = FALSE])
    
    # ---- Stage 1: fit D|X via CV-gross group-lasso ----
    model_D <- mt_fit_cv(
      X_list = X_train,
      y_list = D_train,
      spline = TRUE, df = 10,
      seed = seed,
      nfolds = 5
    )
    D_given_X[idx_te] <- mt_predict(model_D, X_test, task_id = index)
    
    # ---- Stage 1: fit Y|X via CV-gross group-lasso ----
    model_Y <- mt_fit_cv(
      X_list = X_train,
      y_list = Y_train,
      spline = TRUE, df = 10,
      seed = seed,
      nfolds = 5
    )
    Y_given_X[idx_te] <- mt_predict(model_Y, X_test, task_id = index)
  }
  
  ARMUL_D_res[[index]] <- matrix(D[[index]] - D_given_X, ncol = 1)
  ARMUL_Y_res[[index]] <- matrix(Y[[index]] - Y_given_X, ncol = 1)
}

# ----------------------------
# Stage 2: residual regression Y_res ~ D_res using CV gglasso (no spline)
# ----------------------------
ARMUL_transfer_lasso <- vector("list", ntask)

for (index in 1:ntask) {
  
  coef_by_outer_split <- numeric(number_split)
  
  for (split_id in 1:number_split) {
    
    D_res_train <- lapply(ARMUL_D_res, function(t) t[index_select == split_id, , drop = FALSE])
    Y_res_train <- lapply(ARMUL_Y_res, function(t) as.numeric(t[index_select == split_id, , drop = FALSE]))
    
    # Fit multi-task regression of Y_res on D_res; each task has 1 predictor
    model2 <- mt_fit_cv(
      X_list = D_res_train,
      y_list = Y_res_train,
      spline = FALSE, df = 1,
      seed = seed,
      nfolds = 5
    )
    
    # Extract task-specific scalar coefficient (Theta_list[[index]] is 1x1)
    coef_by_outer_split[split_id] <- as.numeric(model2$Theta_list[[index]])
  }
  
  ARMUL_transfer_lasso[[index]] <- mean(coef_by_outer_split)
}

cat("ARMUL_transfer_lasso (gglasso CV lambda):\n")
print(unlist(ARMUL_transfer_lasso))
################################################################################




# Method of ARMUL
##############################################################################################################################
##############################################################################################################################
##############################################################################################################################

c_grid_stage1 <- 10^seq(-10, 1, length.out = 10)   # 0.01 → 10
c_grid_stage2 <- 10^seq(-10, 1, length.out = 10)

sample_size = length(Y[[1]])
ARMUL_transfer <- list()
ARMUL_D_res <- list()
ARMUL_Y_res <- list()
number_split=2
index_select <- sample(1:number_split, sample_size, replace = TRUE)
tune_lambda_vanilla <- function(X_list, y_list,
                                link="linear",
                                spline=TRUE, df=1,
                                c_grid = seq(0.05, 1, by=0.05),
                                val_frac = 0.2,
                                seed = 1,
                                T_global = 5000, T_local = 1,
                                eta_global = 0.01, eta_local = 0.01,
                                penalty = "new",
                                target_task = NULL) {
  set.seed(seed)
  m <- length(X_list)
  n_list <- sapply(y_list, function(y) if (is.matrix(y)) nrow(y) else length(y))
  stopifnot(length(unique(n_list)) == 1)
  n <- n_list[1]

  # inner split indices (shared across tasks)
  idx_val <- sample.int(n, size = ceiling(val_frac * n), replace = FALSE)
  idx_tr  <- setdiff(seq_len(n), idx_val)

  # build inner train/val lists
  X_tr <- lapply(X_list, function(X) X[idx_tr, , drop=FALSE])
  y_tr <- lapply(y_list, function(y) y[idx_tr])
  X_va <- lapply(X_list, function(X) X[idx_val, , drop=FALSE])
  y_va <- lapply(y_list, function(y) y[idx_val])

  d <- ncol(X_list[[1]])
  p_eff <- if (spline) d * df else d

  # convert y to matrices like your vanilla_train expects
  y_va_mat <- lapply(y_va, function(y) matrix(y, ncol=1))

  eval_one_c <- function(cval) {
    lbd <- cval * sqrt(p_eff / n_list)  # vector length m

    models <- vanilla_train(
      X_tr, y_tr,
      link = link, penalty = penalty,
      lbd = lbd,
      eta_global = eta_global, eta_local = eta_local,
      T_global = T_global, T_local = T_local,
      df = df, spline = spline
    )

    # predict for each task on val and compute MSE
    mses <- numeric(m)
    for (j in 1:m) {
      pred <- vanilla_predict(models, X_va, task_id = j, link = link)
      pred <- as.numeric(pred)
      truth <- as.numeric(y_va_mat[[j]])
      mses[j] <- mean((truth - pred)^2)
    }

    if (!is.null(target_task)) mses[target_task] else mean(mses)
  }

  errs <- sapply(c_grid, eval_one_c)
  best_i <- which.min(errs)

  list(
    c_best = c_grid[best_i],
    err_best = errs[best_i],
    errs = errs,
    c_grid = c_grid
  )
}
number_split <- 2
sample_size  <- length(Y[[1]])
index_select <- sample(1:number_split, sample_size, replace = TRUE)

ARMUL_D_res <- vector("list", ntask)
ARMUL_Y_res <- vector("list", ntask)

for (index in 1:ntask) {

  D_given_X <- rep(NA_real_, sample_size)
  Y_given_X <- rep(NA_real_, sample_size)

  for (split_index in 1:number_split) {

    # ---- outer split: TRAIN/TEST indices (shared across tasks) ----
    idx_tr  <- which(index_select == split_index)
    idx_te  <- which(index_select != split_index)

    X_train <- lapply(X, function(t) t[idx_tr, , drop=FALSE])
    D_train <- lapply(D, function(t) t[idx_tr])
    Y_train <- lapply(Y, function(t) t[idx_tr])

    X_test  <- lapply(X, function(t) t[idx_te, , drop=FALSE])

    # --------------------------
    # Tune lambda for D ~ X (stage 1)
    # --------------------------
    tune_D <- tune_lambda_vanilla(
      X_list = X_train,
      y_list = D_train,
      link   = "linear",
      spline = TRUE, df = 10,
      c_grid = c_grid_stage1,
      val_frac = 0.2,
      seed = seed,
      T_global = 5000,
      penalty = "new",
      target_task = index
    )

    # refit D|X on full outer TRAIN using tuned lambda
    d_eff1 <- ncol(X_train[[1]])
    p_eff1 <- d_eff1 * 10  # spline TRUE df=10 => p_eff = d*df
    n_list1 <- sapply(D_train, length)
    lbd_D <- tune_D$c_best * sqrt(p_eff1 / n_list1)

    model_D <- vanilla_train(
      X_train, D_train,
      link = "linear",
      spline = TRUE, df = 10,
      lbd = lbd_D,
      T_global = 1000
    )

    D_given_X[idx_te] <- as.numeric(vanilla_predict(model_D, X_test, task_id = index, link="linear"))

    # --------------------------
    # Tune lambda for Y ~ X (stage 1)
    # --------------------------
    tune_Y <- tune_lambda_vanilla(
      X_list = X_train,
      y_list = Y_train,
      link   = "linear",
      spline = TRUE, df = 10,
      c_grid = c_grid_stage1,
      val_frac = 0.2,
      seed = seed,
      T_global = 5000,
      penalty = "new",
      target_task = index
    )

    n_list2 <- sapply(Y_train, length)
    lbd_Y <- tune_Y$c_best * sqrt(p_eff1 / n_list2)

    model_Y <- vanilla_train(
      X_train, Y_train,
      link = "linear",
      spline = TRUE, df = 10,
      lbd = lbd_Y,
      T_global = 5000
    )

    Y_given_X[idx_te] <- as.numeric(vanilla_predict(model_Y, X_test, task_id = index, link="linear"))
  }

  ARMUL_D_res[[index]] <- matrix(D[[index]] - D_given_X, ncol=1)
  ARMUL_Y_res[[index]] <- matrix(Y[[index]] - Y_given_X, ncol=1)
}

ARMUL_coef <- rep(0, times=number_split)


ARMUL_transfer <- vector("list", ntask)

for (index in 1:ntask) {

  coef_by_outer_split <- numeric(number_split)

  for (split_index in 1:number_split) {

    # outer train/test residual data (all tasks)
    D_res_train <- lapply(ARMUL_D_res, function(t) t[index_select == split_index, , drop=FALSE])
    Y_res_train <- lapply(ARMUL_Y_res, function(t) as.numeric(t[index_select == split_index, , drop=FALSE]))

    D_res_test  <- lapply(ARMUL_D_res, function(t) t[index_select != split_index, , drop=FALSE])
    Y_res_test  <- lapply(ARMUL_Y_res, function(t) as.numeric(t[index_select != split_index, , drop=FALSE]))

    # ----- inner tuning on outer TRAIN only -----
    tune <- tune_lambda_vanilla(
      X_list = D_res_train,
      y_list = Y_res_train,
      link = "linear",
      spline = TRUE, df = 1,
      c_grid = c_grid_stage2,
      val_frac = 0.2,
      seed = seed,
      T_global = 5000,
      target_task = index   # tune for the task
    )

    m <- length(D_res_train)
    n_list <- sapply(Y_res_train, length)
    p_eff <- 1
    lbd_best <- tune$c_best * sqrt(p_eff / n_list)

    models2 <- vanilla_train(
      D_res_train, Y_res_train,
      link = "linear",
      lbd = lbd_best,
      T_global = 5000,
      spline = TRUE
    )

    # task-specific coefficient for this outer split
    # (since X is 1-dim, this is a scalar)
    coef_by_outer_split[split_index] <- as.numeric(models2$vanilla[index,,1])
  }

  ARMUL_transfer[[index]] <- mean(coef_by_outer_split)
}
##############################################################################################################################
##############################################################################################################################
##############################################################################################################################

####################################################################################################
# pERM: tune (C1,C2) in ALL steps (D~X stage1, Y~X stage1, final residual stage2)
# - tune_C1C2_pERM_stage1(): same signature + same return type (list(loss, C1, C2))
####################################################################################################

# ----------------------------
# Stage-1 tuner (same signature + same return type)
# ----------------------------
tune_C1C2_pERM_stage1 <- function(X_list, y_list,
                                 r = 20, nbasis = 5,
                                 C1_grid = 10^seq(-3, 2, length.out = 10),
                                 C2_grid = 10^seq(-3, 2, length.out = 10),
                                 link = "linear",
                                 val_frac = 0.2,
                                 seed = 1,
                                 target_task = NULL,
                                 lr = 1e-5, max_iter = 1000, tol = 1e-3,
                                 info = FALSE) {
  set.seed(seed)
  ntask <- length(X_list)
  n <- nrow(X_list[[1]])
  stopifnot(all(vapply(X_list, nrow, 1L) == n))

  idx_val <- sample.int(n, size = ceiling(val_frac * n), replace = FALSE)
  idx_tr  <- setdiff(seq_len(n), idx_val)

  data_tr <- lapply(seq_len(ntask), function(t)
    list(X = as.matrix(X_list[[t]][idx_tr, , drop=FALSE]),
         y = as.numeric(y_list[[t]][idx_tr]))
  )
  X_val_list <- lapply(seq_len(ntask), function(t)
    as.matrix(X_list[[t]][idx_val, , drop=FALSE])
  )
  y_val_list <- lapply(seq_len(ntask), function(t)
    as.numeric(y_list[[t]][idx_val])
  )

  best <- list(loss = Inf, C1 = NA, C2 = NA)

  for (c1 in C1_grid) for (c2 in C2_grid) {
    fit <- pERM_torch(
      data_tr,
      r = r, nbasis = nbasis,
      C1 = c1, C2 = c2,
      lr = lr, max_iter = max_iter, tol = tol,
      link = link, info = info,
      X_test_list = X_val_list,
      device = cpu_device
    )

    losses <- vapply(seq_len(ntask), function(t) {
      compute_val_loss(y_val_list[[t]], fit$test_preds[[t]], link = link)
    }, numeric(1))

    L <- if (!is.null(target_task)) losses[target_task] else mean(losses)

    if (is.finite(L) && L < best$loss) best <- list(loss = L, C1 = c1, C2 = c2)
  }

  best
}

# ----------------------------
# Stage-2 tuner (NEW) for final residual regression, same return type
# ----------------------------
tune_C1C2_pERM_stage2 <- function(X_list, y_list,
                                 r = 1, nbasis = 1,
                                 C1_grid = 10^seq(-4, 1, length.out = 10),
                                 C2_grid = 10^seq(-4, 1, length.out = 10),
                                 link = "linear",
                                 val_frac = 0.2,
                                 seed = 1,
                                 target_task = NULL,
                                 lr = 1e-4, max_iter = 1000, tol = 1e-3,
                                 info = FALSE) {
  set.seed(seed)
  ntask <- length(X_list)
  n <- nrow(X_list[[1]])
  stopifnot(all(vapply(X_list, nrow, 1L) == n))

  idx_val <- sample.int(n, size = ceiling(val_frac * n), replace = FALSE)
  idx_tr  <- setdiff(seq_len(n), idx_val)

  data_tr <- lapply(seq_len(ntask), function(t)
    list(X = as.matrix(X_list[[t]][idx_tr, , drop=FALSE]),
         y = as.numeric(y_list[[t]][idx_tr]))
  )
  X_val_list <- lapply(seq_len(ntask), function(t)
    as.matrix(X_list[[t]][idx_val, , drop=FALSE])
  )
  y_val_list <- lapply(seq_len(ntask), function(t)
    as.numeric(y_list[[t]][idx_val])
  )

  best <- list(loss = Inf, C1 = NA, C2 = NA)

  for (c1 in C1_grid) for (c2 in C2_grid) {
    fit <- pERM_torch(
      data_tr,
      r = r, nbasis = nbasis,
      C1 = c1, C2 = c2,
      lr = lr, max_iter = max_iter, tol = tol,
      link = link, info = info,
      X_test_list = X_val_list,
      device = cpu_device
    )

    losses <- vapply(seq_len(ntask), function(t) {
      compute_val_loss(y_val_list[[t]], fit$test_preds[[t]], link = link)
    }, numeric(1))

    L <- if (!is.null(target_task)) losses[target_task] else mean(losses)

    if (is.finite(L) && L < best$loss) best <- list(loss = L, C1 = c1, C2 = c2)
  }

  best
}

####################################################################################################
# MAIN: pERM with tuning in all steps (keeps your object types: lists, matrices, etc.)
####################################################################################################

pERM_transfer <- list()
pERM_D_res <- list()
pERM_Y_res <- list()
peRMdata <- list()

sample_size <- length(Y[[1]])

# fixed settings
r_fixed <- 3
nbasis_fixed <- 1
C1_grid <- 10^seq(-4, 2, length.out = 10)
C2_grid <- 10^seq(-4, 2, length.out = 10)

# final stage2 grids (often different scale)
C1_grid_stage2 <- 10^seq(-4, 1, length.out = 10)
C2_grid_stage2 <- 10^seq(-4, 1, length.out = 10)

# initialize predictions containers (keep as list of numeric vectors)
n <- length(Y[[1]])
D_given_Xs <- replicate(ntask, rep(0, n), simplify = FALSE)
Y_given_Xs <- replicate(ntask, rep(0, n), simplify = FALSE)


for (split_index in 1:number_split) {

  tr <- which(index_select == split_index)
  te <- which(index_select != split_index)

  # test list must be per-task
  X_te_list <- lapply(seq_len(ntask), function(t)
    as.matrix(X[[t]][te, , drop=FALSE])
  )

  # ----------------------------
  # D ~ X  (tune C1,C2 on OUTER TRAIN only)
  # ----------------------------
  X_tr_list <- lapply(seq_len(ntask), function(t) as.matrix(X[[t]][tr, , drop=FALSE]))
  D_tr_list <- lapply(seq_len(ntask), function(t) as.numeric(D[[t]][tr]))

  bestD <- tune_C1C2_pERM_stage1(
    X_list = X_tr_list, y_list = D_tr_list,
    r = r_fixed, nbasis = nbasis_fixed,
    C1_grid = C1_grid, C2_grid = C2_grid,
    link = "linear",
    seed = seed,
    info = FALSE
  )

  dataD_tr <- lapply(seq_len(ntask), function(t)
    list(X = X_tr_list[[t]], y = D_tr_list[[t]])
  )

  fitD <- pERM_torch(
    dataD_tr,
    r = r_fixed, nbasis = nbasis_fixed,
    C1 = bestD$C1, C2 = bestD$C2,
    info = TRUE, link = "linear",
    X_test_list = X_te_list,
    device = cpu_device
  )

  for (t in 1:ntask) D_given_Xs[[t]][te] <- fitD$test_preds[[t]]

  # ----------------------------
  # Y ~ X  (tune C1,C2 on OUTER TRAIN only)
  # ----------------------------
  Y_tr_list <- lapply(seq_len(ntask), function(t) as.numeric(Y[[t]][tr]))

  bestY <- tune_C1C2_pERM_stage1(
    X_list = X_tr_list, y_list = Y_tr_list,
    r = r_fixed, nbasis = nbasis_fixed,
    C1_grid = C1_grid, C2_grid = C2_grid,
    link = "linear",
    seed = seed,
    info = FALSE
  )

  dataY_tr <- lapply(seq_len(ntask), function(t)
    list(X = X_tr_list[[t]], y = Y_tr_list[[t]])
  )

  fitY <- pERM_torch(
    dataY_tr,
    r = r_fixed, nbasis = nbasis_fixed,
    C1 = bestY$C1, C2 = bestY$C2,
    info = TRUE, link = "linear",
    X_test_list = X_te_list,
    device = cpu_device
  )

  for (t in 1:ntask) Y_given_Xs[[t]][te] <- fitY$test_preds[[t]]
}

# ----------------------------
# ----------------------------
pERM_D_res <- lapply(seq_len(ntask), function(t) matrix(as.numeric(D[[t]] - D_given_Xs[[t]]), ncol=1))
pERM_Y_res <- lapply(seq_len(ntask), function(t) matrix(as.numeric(Y[[t]] - Y_given_Xs[[t]]), ncol=1))

# ----------------------------
# FINAL Stage-2: residual(Y) ~ residual(D)  (tune C1,C2 in EACH outer split)
# ----------------------------
coef <- rep(0, times = number_split)
coef_mat <- matrix(0, nrow = number_split, ncol = ntask)
for (split_index in 1:number_split) {

  tr <- which(index_select == split_index)

  # build residual training lists (keep types: X is matrix, y is numeric)
  X2_tr_list <- lapply(seq_len(ntask), function(t)
    as.matrix(pERM_D_res[[t]][tr, , drop=FALSE])
  )
  Y2_tr_list <- lapply(seq_len(ntask), function(t)
    as.numeric(pERM_Y_res[[t]][tr, 1])
  )

  best2 <- tune_C1C2_pERM_stage2(
    X_list = X2_tr_list, y_list = Y2_tr_list,
    r = 1, nbasis = 1,
    C1_grid = C1_grid_stage2, C2_grid = C2_grid_stage2,
    link = "linear",
    seed = seed,
    info = FALSE
  )

  # fit stage2 on residual training data (keep peRMdata as list of lists with matrices)
  for (t in 1:ntask) {
    peRMdata[[t]] <- list(
      X = as.matrix(pERM_D_res[[t]][index_select==split_index, , drop=FALSE]),
      y = as.matrix(pERM_Y_res[[t]][index_select==split_index, drop=FALSE])
    )
  }

  model <- pERM_torch(
    peRMdata,
    r = 1, nbasis = 1,
    info = TRUE, link = "linear",
    C1 = best2$C1, C2 = best2$C2,
    device = cpu_device
  )

  # keep your exact update logic + types
  for (index in 1:ntask) {
    coef_mat[split_index, index] <- model$step2[1, index]
  }
}
for (index in 1:ntask) {
  pERM_transfer[[index]] <- mean(coef_mat[, index])
}
# Data Pooling method
##############################################################################################################################
##############################################################################################################################
##############################################################################################################################

split_index <- NULL
for (index in 1:ntask){
  split_index[[index]] <- sample(1:2, n, replace = TRUE)
}
pooled_res <- list()
pooled_X <- do.call(rbind, X)
pooled_Y <- do.call(c, Y)
pooled_D <- do.call(c, D)
pooled_temp <- PLM_Per_Site(pooled_X, pooled_D, pooled_Y, split_index=split_index[[index]])
for (index in 1:ntask){
  pooled_res[[index]] <- pooled_temp$coef_estimate |> mean()
}
print("The pooled results are:")  
print(pooled_res)
##############################################################################################################################
##############################################################################################################################
##############################################################################################################################

# Method without Nonpar Transfer
# each site no nonpar transfer
fit_each_site <- NULL
for (index in 1:ntask){
  fit_each_site[[index]] <- PLM_Per_Site(X[[index]], D[[index]], Y[[index]], split_index=split_index[[index]])
}
Para_Transfer <- function(){
  # tranfer learning update no nonpar transfer (main node)
  fit <- NULL
  lambda <- 10*10^(-seq(0,10, length.out=lambda_length))
  for (fold in 1:2){
    ## Gradient and Hessian
    gradient <- hessian <- NULL
    for (index in 1:ntask) {
      gradient[[index]] <- fit_each_site[[index]]$gradient[fold]
      hessian[[index]] <- fit_each_site[[index]]$hessian[fold]
    }
    
    ## Initial value
    initial_value <- list()
    for (index in 1:ntask) {
      initial_value[[index]] <- fit_each_site[[index]]$coef_estimate[fold]
    }
    lambda <- sort(unique(lambda), decreasing = TRUE)

    fit[[fold]] <- SemiTransfer_Par(gradient, hessian, initial_value, type = "PLM", lambda=lambda)
    lambda <- c(lambda, fit[[fold]]$lambda)
  }
  lambda <- sort(unique(lambda))
  fit <- NULL
  for (fold in 1:2){
    ## Gradient and Hessian
    gradient <- hessian <- NULL
    for (index in 1:ntask) {
      gradient[[index]] <- fit_each_site[[index]]$gradient[fold]
      hessian[[index]] <- fit_each_site[[index]]$hessian[fold]
    }
    
    ## Initial value
    initial_value <- list()
    for (index in 1:ntask) {
      initial_value[[index]] <- fit_each_site[[index]]$coef_estimate[fold]
    }
    lambda <- sort(unique(lambda), decreasing = TRUE)
    print("lambda before semitransfer_PAR")
    print(lambda)
    fit[[fold]] <- SemiTransfer_Par(gradient, hessian, initial_value, type = "PLM", lambda=lambda)
  }
  ## tuning optimal lambda
  ### get coefficients
  coef_candidate <- list()
  for (index in 1:ntask){
    coef_candidate[[index]] <- list()
    for (fold in 1:2){
      coef_candidate[[index]][[fold]] <- fit[[fold]]$fit$gglasso.fit$beta[index,]+
        fit[[fold]]$fit$gglasso.fit$beta[ntask+1,]
    }
  }
  ### cross-validation to tune on split dataset
  lambda <- sort(unique(lambda), decreasing = TRUE)
  fit_tuned <- coef_est <-coef_est_tuned <- NULL
  error <- array(0, c(ntask, length(lambda)))
  

  for (index in 1:ntask){
    fit_tuned[[index]] <- PLM_tune_Per_Site(coef_candidate[[index]], X[[index]], D[[index]],
                                            Y[[index]], split_index=split_index[[index]], 
                                            nfold=2, lambda=lambda)
    error[index,] <- fit_tuned[[index]]$error
  }
  error.all.task <- apply(error,2,mean)
  for (index in 1:ntask){
    coef_est_tuned[[index]] <- (coef_candidate[[index]][[1]][which.min(error.all.task)]+
                                  coef_candidate[[index]][[2]][which.min(error.all.task)])/2
  }
  return(list(coef_est_tuned=coef_est_tuned, coef_est_untuned=(fit[[1]]$coef+fit[[2]]$coef)/2))
}
start_time <- Sys.time()
fit_para_transfer <- Para_Transfer()
coef_est_tuned <- fit_para_transfer$coef_est_tuned
coef_est <- fit_para_transfer$coef_est_untuned
end_time <- Sys.time()
time_para_transfer <- difftime(end_time, start_time, units="secs")
#initial value
coef_est_no_transfer <- NULL
for (index in 1:ntask) {
  coef_est_no_transfer <- c(coef_est_no_transfer, mean(fit_each_site[[index]]$coef_estimate))
}
print(coef_est_no_transfer)

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

## Nonparametric transfer
transfer_Y_given_X <- function(Y, X){
  bandwidth_scale_seq <- seq(0.5,1,length.out=8)
  cv.bandwidth.error <- array(0, c(length(bandwidth_scale_seq),ntask))
  predict_Y_given_X_bandwidth <- NULL
  predict_Y_given_X <- NULL
  predict_Y_given_X_opt <- NULL
  lambda <- 10*10^(-seq(0,10, length.out=lambda_length))
  for (k in 1:length(bandwidth_scale_seq)){
    for (index.test in 1:ntask){
      bandwidth_scale <- bandwidth_scale_seq[k]
      ## each site for nonpar transfer
      Y_given_X_transfer_each_site <- NULL
      fit_Y_given_X <- list()
      for (fold in 1:2){
        for (index in 1:ntask){
          Y_given_X_transfer_each_site[[index]] <- Nonpar_Per_Site(X=X[[index]], Y=Y[[index]],
                                                                   split_index=split_index[[index]],
                                                                   grid = grid[[index.test]][[fold]], bandwidth_scale=bandwidth_scale, method="np")
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
        lambda <- c(lambda, fit_Y_given_X[[fold]]$fit$lambda)
      }
      lambda <- sort(unique(lambda), decreasing = TRUE)
      cv.error <- array(0, dim=c(2,length(lambda)))
      predict_Y_given_X_opt[[index.test]] <- array(0, c(NROW(X[[index.test]]),1))
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
        #lambda <- sort(unique(lambda), decreasing = TRUE)
        fit_Y_given_X[[fold]] <- SemiTransfer_NonPar(gradient, hessian)
        ### prediction match (each site) on fold 1
        predict_Y_given_X[[fold]] <- get_prediction_nonpar(fit_Y_given_X[[fold]], 
                                                           X=X[[index.test]], 
                                                           grid[[index.test]][[fold]], task=index.test)
        ### calculate error (each site) on fold 
        cv.error[fold,] <- apply(predict_Y_given_X[[fold]][split_index[[index.test]]==fold,],2, function(t){mean((t-
                                    Y[[index.test]][split_index[[index.test]]==fold])^2)})
        
      }
      for (fold in 1:2){
        predict_Y_given_X_opt[[index.test]][split_index[[index.test]]==fold] <-
          predict_Y_given_X[[fold]][split_index[[index.test]]==fold,which.min(cv.error[fold,])]
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
start_time <- Sys.time()
Y_given_X_opt <- transfer_Y_given_X(Y=Y, X=X)
D_given_X_opt <- transfer_Y_given_X(Y=D, X=X)

# nonparametric_transfer
Nonpara_Transfer <- function(){
  ## each fit gradient and hessian for parametric
  fit_each_site_nonpar_tranfer <- NULL
  lambda <- 10*10^(-seq(0,10, length.out=lambda_length))
  for (index in 1:ntask){
    fit_each_site_nonpar_tranfer[[index]] <- PLM_Per_Site(X[[index]], D[[index]],
                                                          Y[[index]], split_index=split_index[[index]],
                                                          Y_given_X = Y_given_X_opt[[index]],
                                                          D_given_X = D_given_X_opt[[index]],
                                                          nonpar_transfer = TRUE)
  }
  
  # tranfer learning update with nonpar transfer (main node)
  fit_both <-  NULL
  for (fold in 1:2){
    ## Gradient and Hessian
    gradient <- hessian <- NULL
    for (index in 1:ntask) {
      gradient[[index]] <- fit_each_site_nonpar_tranfer[[index]]$gradient[fold]
      hessian[[index]] <- fit_each_site_nonpar_tranfer[[index]]$hessian[fold]
    }
    
    ## Initial value
    initial_value <- list()
    for (index in 1:ntask) {
      initial_value[[index]] <- fit_each_site_nonpar_tranfer[[index]]$coef_estimate[fold]
    }
    #lambda <- sort(unique(lambda), decreasing = TRUE)
    print("lambda before semitransfer_PAR")
    lambda <- sort(unique(lambda))
    print(lambda)
    fit_both[[fold]] <- SemiTransfer_Par(gradient, hessian, initial_value, type = "PLM", lambda=lambda)
    lambda <- c(lambda, fit_both[[fold]]$lambda)
    
  }
  ## tuning optimal lambda
  fit_both <- NULL
  lambda <- sort(unique(lambda))
  for (fold in 1:2){
    ## Gradient and Hessian
    gradient <- hessian <- NULL
    for (index in 1:ntask) {
      gradient[[index]] <- fit_each_site_nonpar_tranfer[[index]]$gradient[fold]
      hessian[[index]] <- fit_each_site_nonpar_tranfer[[index]]$hessian[fold]
    }
    
    ## Initial value
    initial_value <- list()
    for (index in 1:ntask) {
      initial_value[[index]] <- fit_each_site_nonpar_tranfer[[index]]$coef_estimate[fold]
    }
    
    fit_both[[fold]] <- SemiTransfer_Par(gradient, hessian, initial_value, type = "PLM", lambda=lambda)
  }
  
  ### get coefficients
  coef_candidate <- list()
  for (index in 1:ntask){
    coef_candidate[[index]] <- list()
    for (fold in 1:2){
      coef_candidate[[index]][[fold]] <- fit_both[[fold]]$fit$gglasso.fit$beta[index,]+
        fit_both[[fold]]$fit$gglasso.fit$beta[ntask+1,]
    }
  }
  ### cross-validation to tune on split dataset
  fit_tuned_both <- coef_est_both_tuned <- coef_est_both <- NULL
  error <- array(0, c(ntask, length(lambda)))
  for (index in 1:ntask){
    fit_tuned_both[[index]] <- PLM_tune_Per_Site(coef_candidate[[index]], X[[index]], D[[index]],
                                                 Y[[index]], split_index=split_index[[index]], 
                                                 Y_given_X = Y_given_X_opt[[index]],
                                                 D_given_X = D_given_X_opt[[index]],
                                                 nfold=2, lambda=lambda, nonpar_transfer=TRUE)
    error[index,] <- fit_tuned_both[[index]]$error
  }
  error.all.task <- apply(error,2,mean)
  for (index in 1:ntask){
    coef_est_both_tuned[[index]] <- (coef_candidate[[index]][[1]][which.min(error.all.task)]+
                                       coef_candidate[[index]][[2]][which.min(error.all.task)])/2
  }
  return(list(coef_est_both_tuned=coef_est_both_tuned, coef_est_both_untuned=(fit_both[[1]]$coef+fit_both[[2]]$coef)/2))
}
fit_nonpara_transfer <- Nonpara_Transfer()
coef_est_both_tuned <- fit_nonpara_transfer$coef_est_both_tuned
coef_est_both <- fit_nonpara_transfer$coef_est_both_untuned
end_time <- Sys.time()
time_nonpar_transfer <- difftime(end_time, start_time, units="secs")
# compare mse
mse_sai_transfer <- (unlist(effect)-unlist(Sai_transfer))^2
mse_net_transfer <- (unlist(effect)-unlist(Net_transfer))^2
mse_ARMUL_transfer <- (unlist(effect)-unlist(ARMUL_transfer))^2
mse_pERM_transfer <- (unlist(effect)-unlist(pERM_transfer))^2
mse_par_transfer <- (coef_est-unlist(effect))^2
mse_par_transfer_tuned <- (unlist(coef_est_tuned)-unlist(effect))^2
mse_nonpar_transfer <- (coef_est_both-unlist(effect))^2
mse_nonpar_transfer_tuned <- (unlist(coef_est_both_tuned)-unlist(effect))^2
mse_standard <- (coef_est_no_transfer-unlist(effect))^2
mse_pooled <- (unlist(effect)-unlist(pooled_res))^2

mse_ARUML_lasso_transfer <- (unlist(effect) - unlist(ARMUL_transfer_lasso))^2

res <- data.frame(res=rbind(mse_sai_transfer, mse_net_transfer, mse_ARMUL_transfer, mse_pERM_transfer,mse_pooled, mse_par_transfer,mse_par_transfer_tuned, 
                            mse_nonpar_transfer, mse_nonpar_transfer_tuned, 
                            mse_standard, mse_ARUML_lasso_transfer))
row.names(res) <- c("Sai_Transfer","Net_Transfer","ARMUL_transfer", "pERM_Transfer","Pooled", "Para_Transfer", "Para_Transfer_Tuned","NonPara_Transfer",
                     "NonPara_Transfer_Tuned", "Baseline", "ARUML_lasso_Transfer")
colnames(res) <- c('Task1', 'Task2', 'Task3', 'Task4', 'Task5')
print(res)
saveRDS(res, file = filename)

results_list <- list(
  coef_est = coef_est,
  coef_est_tuned = coef_est_tuned,
  coef_est_both = coef_est_both,
  coef_est_both_tuned = coef_est_both_tuned,
  coef_est_no_transfer = coef_est_no_transfer,
  effect = effect,
  ARMUL_transfer=ARMUL_transfer
)
print("The results list:")
print(results_list)
# Save the list to a .RData file
saveRDS(results_list, file = filename_estimates)

time <- list(
  time_para_transfer = time_para_transfer,
  time_nonpar_transfer = time_nonpar_transfer
)

# save time as csv file
time_filename <- file.path(dictionary_time, paste0("time_data_seed_", seed, ".csv"))
write.csv(time, file = time_filename, row.names = FALSE)
}


usage <- "Rscript simulation/test_PLM.R <n> <similarity> <seed> <dim> <lambda_length>"
cli <- parse_numeric_cli(c("n", "similarity", "seed", "dim", "lambda_length"), usage)
validate_common_simulation_args(cli, minimum_dim = 4L)
require_integer_argument(cli$lambda_length, "lambda_length", minimum = 2L)
n <- cli$n
similarity <- cli$similarity
seed <- cli$seed
dim <- cli$dim
lambda_length <- cli$lambda_length
output_root <- simulation_output_root(repo_root)
source_transfersemi(repo_root)
library(glmnet)
cat("The dim is", dim, "\n")
cat(seed, n, similarity, dim)
cat("The dim is", dim, "\n")
run_simulation(seed, n, similarity, dim, lambda_length)

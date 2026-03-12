library(torch)

# ----------------------------
# Utilities
# ----------------------------
to_tensor <- function(x, device) {
  torch_tensor(as.matrix(x), dtype = torch_float(), device = device)
}

row_sum <- function(x) torch_sum(x, dim = 2, keepdim = TRUE)  # sum over features

# ----------------------------
# Representation network R(Z): q -> p
# ----------------------------
repnet <- nn_module(
  "RepNet",
  initialize = function(q, hidden = c(5, 5), p = 2) {
    self$fc1 <- nn_linear(q, hidden[1])
    self$fc2 <- if (length(hidden) > 1) nn_linear(hidden[1], hidden[2]) else NULL
    self$fc_out <- nn_linear(
      if (is.null(self$fc2)) hidden[1] else hidden[2],
      p
    )
  },
  forward = function(z) {
    #h <- nnf_sigmoid(self$fc1(z))
    h <- (self$fc1(z))
    if (!is.null(self$fc2)) {
      #h <- nnf_sigmoid(self$fc2(h))
      h <- (self$fc2(h))
    }
    self$fc_out(h)  # R(Z) in R^p
  }
)


# ----------------------------
# RTL model (sources): shared R(Z), domain-specific beta_k, gamma_k
# ----------------------------
rtl_model <- nn_module(
  "RTLModel",
  initialize = function(q, d, p, K, hidden = c(5, 5)) {
    self$R <- repnet(q = q, hidden = hidden, p = p)
    # beta: K x d ; gamma: K x p
    self$beta  <- nn_parameter(torch_zeros(K, d))
    self$gamma <- nn_parameter(torch_zeros(K, p))
  },
  forward = function(x, z, k_idx) {
    #X is D from source data
    #Z is X from source data
    #y is Y from source data
    # x: N x d ; z: N x q ; k_idx: N (1..K)
    Rz <- self$R(z)               # N x p
    # select domain-specific rows
    beta_k  <- self$beta[k_idx$to(dtype = torch_long()), ]    # N x d
    gamma_k <- self$gamma[k_idx$to(dtype = torch_long()), ]   # N x p
    # linear parts
    x_part  <- row_sum(x * beta_k)       # N x 1
    z_part  <- row_sum(Rz * gamma_k)     # N x 1
    x_part + z_part                      # y_hat (N x 1)
  }
)

# ----------------------------
# Fit on sources (full-batch for clarity)
# ----------------------------
fit_sources <- function(X_list, Z_list, y_list,
                        hidden = c(5,5), p = 2,
                        lr = 1e-3, weight_decay = 0.0,
                        epochs = 1000, verbose = TRUE,
                        device = NULL,
                        test_frac = 0.2, seed = 1,
                        patience = 30, min_delta = 0.0,
                        restore_best = TRUE) {
  if (is.null(device)) { 
    device <- if (cuda_is_available()) torch_device("cuda") else torch_device("cpu")
  }

  K <- length(X_list)
  stopifnot(length(Z_list) == K, length(y_list) == K)

  d <- ncol(X_list[[1]])
  q <- ncol(Z_list[[1]])

  # ----------------------------
  # Shared train/test split indices (same rows across tasks)
  # ----------------------------
  set.seed(seed)
  n <- nrow(Z_list[[1]])
  stopifnot(all(vapply(Z_list, nrow, 1L) == n))
  stopifnot(all(vapply(X_list, nrow, 1L) == n))
  stopifnot(all(vapply(y_list, nrow, 1L) == n))

  idx_te <- sample.int(n, size = ceiling(test_frac * n), replace = FALSE)
  idx_tr <- setdiff(seq_len(n), idx_te)

  submat <- function(M, idx) as.matrix(M[idx, , drop = FALSE])
  subvec <- function(v, idx) as.matrix(v[idx, , drop = FALSE])

  X_tr_list <- lapply(X_list, submat, idx = idx_tr)
  Z_tr_list <- lapply(Z_list, submat, idx = idx_tr)
  y_tr_list <- lapply(y_list, subvec, idx = idx_tr)

  X_te_list <- lapply(X_list, submat, idx = idx_te)
  Z_te_list <- lapply(Z_list, submat, idx = idx_te)
  y_te_list <- lapply(y_list, subvec, idx = idx_te)

  # ----------------------------
  # Stack train
  # ----------------------------
  N_tr_vec <- sapply(y_tr_list, nrow)
  Ntr      <- sum(N_tr_vec)
  k_tr_idx <- unlist(Map(function(k, n) rep(k, n), seq_len(K), N_tr_vec))

  X_tr_all <- do.call(rbind, X_tr_list)
  Z_tr_all <- do.call(rbind, Z_tr_list)
  y_tr_all <- do.call(rbind, y_tr_list)

  x_tr <- to_tensor(X_tr_all, device)
  z_tr <- to_tensor(Z_tr_all, device)
  y_tr <- to_tensor(y_tr_all, device)
  k_tr <- torch_tensor(k_tr_idx, dtype = torch_long(), device = device)

  # ----------------------------
  # Stack test
  # ----------------------------
  N_te_vec <- sapply(y_te_list, nrow)
  Nte      <- sum(N_te_vec)
  k_te_idx <- unlist(Map(function(k, n) rep(k, n), seq_len(K), N_te_vec))

  X_te_all <- do.call(rbind, X_te_list)
  Z_te_all <- do.call(rbind, Z_te_list)
  y_te_all <- do.call(rbind, y_te_list)

  x_te <- to_tensor(X_te_all, device)
  z_te <- to_tensor(Z_te_all, device)
  y_te <- to_tensor(y_te_all, device)
  k_te <- torch_tensor(k_te_idx, dtype = torch_long(), device = device)

  # ----------------------------
  # Model + optimizer
  # ----------------------------
  model <- rtl_model(q = q, d = d, p = p, K = K, hidden = hidden)
  model$to(device = device)
  opt <- optim_adam(model$parameters, lr = lr, weight_decay = weight_decay)

  # ----------------------------
  # Early stopping bookkeeping
  # ----------------------------
  best_test <- Inf
  best_epoch <- 0
  bad_count <- 0
  best_state <- NULL

  # safe deep copy of all parameters to CPU
  capture_state <- function(model) {
    with_no_grad({
      lapply(model$parameters, function(p) p$detach()$clone()$cpu())
    })
  }
  restore_state <- function(model, state_list) {
    with_no_grad({
      params <- model$parameters
      for (i in seq_along(params)) {
        params[[i]]$copy_(state_list[[i]]$to(device = device))
      }
    })
  }

  # ----------------------------
  # Train loop
  # ----------------------------
  for (e in seq_len(epochs)) {
    model$train()
    opt$zero_grad()

    y_hat <- model(x_tr, z_tr, k_tr)
    loss_tr <- nnf_mse_loss(y_hat, y_tr)
    loss_tr$backward()
    opt$step()

    # ----- eval on test -----
    model$eval()
    with_no_grad({
      y_hat_te <- model(x_te, z_te, k_te)
      loss_te  <- nnf_mse_loss(y_hat_te, y_te)
    })

    tr_val <- as.numeric(loss_tr$item())
    te_val <- as.numeric(loss_te$item())

    if (verbose && (e %% max(1, floor(epochs/10)) == 0 || e == 1)) {
      cat(sprintf("RTL [epoch %d] train MSE=%.6f  test MSE=%.6f\n", e, tr_val, te_val))
    }

    # ----- best? -----
    if (is.finite(te_val) && (te_val < best_test - min_delta)) {
      best_test <- te_val
      best_epoch <- e
      bad_count <- 0
      if (restore_best) best_state <- capture_state(model)
    } else {
      bad_count <- bad_count + 1
      if (bad_count >= patience) {
        if (verbose) {
          cat(sprintf("Early stop at epoch %d (best test MSE=%.6f at epoch %d)\n",
                      e, best_test, best_epoch))
        }
        break
      }
    }
  }

  # restore best weights
  if (restore_best && !is.null(best_state)) {
    restore_state(model, best_state)
  }

  # print trained beta/gamma (after restoring best)
  with_no_grad({
    beta_tr  <- as_array(model$beta$detach()$cpu())
    gamma_tr <- as_array(model$gamma$detach()$cpu())
  })
  cat("\n==== Trained beta (K x d) [best-by-test] ====\n"); print(beta_tr)
  cat("\n==== Trained gamma (K x p) [best-by-test] ====\n"); print(gamma_tr)

  list(
    model = model,
    device = device,
    d = d, q = q, p = p, K = K,
    split = list(idx_tr = idx_tr, idx_te = idx_te),
    best = list(test_mse = best_test, epoch = best_epoch)
  )
}

# ----------------------------
# Target-step: freeze R, estimate (beta0, gamma0) by OLS
# ----------------------------
fit_target_ols <- function(fitted_sources, X0, Z0, y0, ridge = 0.0, add_intercept = FALSE) {
  model  <- fitted_sources$model
  device <- fitted_sources$device
  
  model$eval()
  with_no_grad({
    RZ0 <- as_array(model$R(to_tensor(Z0, device)))  # n0 x p
  })
  
  D0 <- cbind(if (add_intercept) 1 else NULL, X0, RZ0)   # n0 x (d(+1)+p)
  yv <- as.numeric(y0)
  
  # OLS / Ridge
  XtX <- crossprod(D0)
  if (ridge > 0) {
    lambda <- diag(ridge, ncol(D0))
    if (add_intercept) lambda[1,1] <- 0  # don't penalize intercept
    XtX <- XtX + lambda
  }
  Xty <- crossprod(D0, yv)
  coef <- solve(XtX, Xty)  # (d(+1)+p) vector
  
  # Variance, SEs, CIs for beta0 block
  yhat   <- as.numeric(D0 %*% coef)
  resid  <- yv - yhat
  df     <- nrow(D0) - ncol(D0)
  sigma2 <- sum(resid^2) / max(df, 1)
  
  vcov   <- sigma2 * solve(crossprod(D0))  # OLS formula
  se     <- sqrt(diag(vcov))
  
  list(
    coef = coef,
    se   = se,
    sigma2 = sigma2,
    df   = df,
    design = D0
  )
}



process_for_rtl <- function(X, D, Y, effect, target_indx = 1, method = "CATE") {
  ntask <- length(X)
  
  # build source lists
  if (method == "CATE"){
    X_list <- lapply(X[-target_indx], function(x) as.matrix(x))  # ensure matrix
  }
  else{
    X_list <- lapply(D[-target_indx], function(d) matrix(d, ncol = 1))   # ensure matrix
  }
  Z_list <- X[-target_indx]                                           # keep as is (n × p)
  y_list <- lapply(Y[-target_indx], function(y) matrix(y, ncol = 1))  # ensure matrix
  
  # build target
  if (method == "CATE"){
    X0 <- as.matrix(X[[target_indx]])
  }
  else{
    X0 <- matrix(D[[target_indx]], ncol = 1)
  }
  #X0 <- matrix(D[[target_indx]], ncol = 1)
  Z0 <- X[[target_indx]]
  y0 <- matrix(Y[[target_indx]], ncol = 1)
  
  list(
    X_list = X_list,
    Z_list = Z_list,
    y_list = y_list,
    X0 = X0, Z0 = Z0, y0 = y0, beta0=effect[[target_indx]]
  )
}


build_spline_funs_from_tasks <- function(data, df, degree = 3, intercept = TRUE,
                                         boundary_expand = 0.01,   # 5% range padding
                                         clamp = FALSE) {         # optional: clip x into boundaries
  stopifnot(length(data) >= 1)
  p <- ncol(data[[1]]$X)
  stopifnot(all(vapply(data, function(d) ncol(d$X), 1L) == p))
  
  lapply(seq_len(p), function(j) {
    pooled_x <- unlist(lapply(data, function(d) as.numeric(d$X[, j])))
    
    xmin <- min(pooled_x, na.rm = TRUE)
    xmax <- max(pooled_x, na.rm = TRUE)
    rng  <- xmax - xmin
    if (!is.finite(rng) || rng == 0) rng <- 1
    
    # expand boundaries a bit
    bmin <- xmin - boundary_expand * rng
    bmax <- xmax + boundary_expand * rng
    
    # fit bs ONCE with explicit boundaries
    bs_obj <- splines::bs(
      pooled_x,
      df = df, degree = degree, intercept = intercept,
      Boundary.knots = c(bmin, bmax)
    )
    
    function(x) {
      x <- as.numeric(x)
      if (clamp) x <- pmin(pmax(x, bmin), bmax)  # optional: avoid extrapolation entirely
      as.matrix(predict(bs_obj, x))
    }
  })
}
compute_val_loss <- function(y_true, y_pred, link = "linear") {
  if (link == "linear") {
    return(mean((y_true - y_pred)^2))
  } else {
    # logistic cross-entropy
    eps <- 1e-12
    y_pred <- pmin(pmax(y_pred, eps), 1 - eps)
    return(-mean(y_true * log(y_pred) + (1 - y_true) * log(1 - y_pred)))
  }
}

# Apply the spline mappers to a single matrix X (n x p) -> (n x (p*df))
expand_with_spline_funs <- function(X, spline_funs) {
  stopifnot(ncol(X) == length(spline_funs))
  blocks <- lapply(seq_len(ncol(X)), function(j) spline_funs[[j]](X[, j]))
  do.call(cbind, blocks)
}

# Expand an entire list of task design matrices with the same mappers
expand_tasks_with_spline <- function(data, spline_funs) {
  lapply(data, function(d) {
    Xs <- expand_with_spline_funs(d$X, spline_funs)
    list(X = Xs, y = d$y)
  })
}

pERM_torch <- function(data, r = 3, nbasis=5, lr = 1e-2, max_iter = 200,
                       C1 = 0.001, C2 = 0.001, info = FALSE, tol = 1e-3,
                       link = c("linear","logistic"), X_test=NULL, X_test_list=NULL) {
  
  link <- match.arg(link)
  stopifnot(requireNamespace("torch", quietly = TRUE))
  
  Ttasks <- length(data)
  n_vec  <- vapply(data, function(d) nrow(d$X), numeric(1))
  p      <- ncol(data[[1]]$X)
  n_tot  <- sum(n_vec)
  if (!is.null(nbasis) && nbasis > 1) {
    # build reusable per-feature mappers from pooled training
    spline_funs <- build_spline_funs_from_tasks(data, df = nbasis, degree = 3, intercept = TRUE)
    # expand every task with the SAME basis
    data <- expand_tasks_with_spline(data, spline_funs)
  }
  
  
  
  
  # Stack data
  X <- do.call(rbind, lapply(data, function(d) d$X))
  y <- unlist(lapply(data, function(d) d$y))
  idx_ranges <- split(seq_len(n_tot), rep(seq_len(Ttasks), times = n_vec))
  
  # Torch tensors
  X_t <- torch::torch_tensor(X, dtype = torch::torch_float64())
  y_t <- torch::torch_tensor(y, dtype = torch::torch_float64())
  
  # Init A_hat: (T x p x r)
  A_hat_arr <- array(
    0,
    dim = c(Ttasks, p * nbasis, r)
  )
  for (t in 1:Ttasks) {
    tmp <- matrix(rnorm(p * nbasis * r, mean = 0, sd = 1),
                  nrow = p * nbasis, ncol = r)
    A_hat_arr[t,,] <- qr.Q(qr(tmp))[, 1:r, drop = FALSE]
  }
  A_hat <- torch::torch_tensor(A_hat_arr, requires_grad = TRUE, dtype = torch::torch_float64())
  
  # Init A_bar: (p x r)
  A_bar_mat <- matrix(rnorm(p * nbasis * r, mean = 0, sd = 1),
                      nrow = p * nbasis, ncol = r)

  # Orthonormalize columns (QR)
  A_bar_mat <- qr.Q(qr(A_bar_mat))[, 1:r, drop = FALSE]
  A_bar <- torch::torch_tensor(A_bar_mat, requires_grad = TRUE, dtype = torch::torch_float64())
  # Init theta: (r x T)
  theta <- torch::torch_randn(c(r, Ttasks), dtype = torch::torch_float64())
  # normalize each column (task) to have unit norm
  theta <- theta / (torch::torch_norm(theta, dim = 1, keepdim = TRUE) + 1e-8)
  theta$requires_grad_(TRUE)
  
  # Projection helper
  
  proj_mat <- function(A) {
    At <- A$transpose(-2, -1)
    Inv <- torch::torch_inverse(torch::torch_matmul(At, A))
    torch::torch_matmul(A, torch::torch_matmul(Inv, At))
  }
  
  
  
  # Spectral norm (largest singular value as scalar)
  # Spectral norm (largest singular value)
  spectral_norm <- function(M) {
    dims <- M$size()
    
    # scalar (0-D)
    if (length(dims) == 0) {
      return(torch::torch_abs(M))
    }
    
    # 1D vector -> ||v||2
    if (length(dims) == 1) {
      return(torch::torch_norm(M, p = 2))
    }
    
    # 1x1 matrix
    if (length(dims) == 2 && as.integer(dims[1]) == 1L && as.integer(dims[2]) == 1L) {
      return(torch::torch_abs(M)$squeeze())
    }
    
    # general 2D matrix: largest singular value
    sv <- torch::torch_svd(M, compute_uv = FALSE)  # returns list(u, d, v); d exists even if uv not computed
    torch::torch_max(sv[[2]])
  }
  
  
  lam <- sqrt(r * p + log(Ttasks)) * C1
  
  # Step 1 loss
  loss_step1 <- function(A_hat, theta, A_bar) {
    s <- torch::torch_tensor(0, dtype = torch::torch_float64())
    for (t in seq_len(Ttasks)) {
      rr_idx <- torch::torch_tensor(idx_ranges[[t]], dtype = torch::torch_int64())
      Xt <- X_t$index_select(1, rr_idx)
      yt <- y_t$index_select(1, rr_idx)
      
      At <- A_hat[t, , ]
      th <- theta[, t]
      lin <- torch::torch_matmul(Xt, torch::torch_matmul(At, th))
      
      if (link == "linear") {
        resid <- yt - lin
        data_term <- 0.5 / n_tot * torch::torch_dot(resid, resid)
      } else {
        data_term <- 1 / n_tot * (torch::torch_sum(torch::nnf_softplus(lin)) -
                                    torch::torch_dot(yt, lin))
      }
      
      
      Pt   <- proj_mat(At)
      Pbar <- proj_mat(A_bar)
      if (ncol(Pt)==1){
        pen  <- lam  / sqrt(n_tot) * spectral_norm(Pt - Pbar) * 0
      }else{
        pen  <- lam  / sqrt(n_tot) * spectral_norm(Pt - Pbar)
      }
      
      
      s <- s + data_term + pen
    }
    s
  }
  
  # Optimize Step 1
  opt1 <- torch::optim_adam(list(A_hat, A_bar, theta), lr = lr)
  loss_prev <- Inf
  for (i in seq_len(max_iter)) {
    opt1$zero_grad()
    l <- loss_step1(A_hat, theta, A_bar)
    l$backward()
    opt1$step()
    li <- as.numeric(l$item())
    if (info && i %% 100 == 0) cat("Step1 pERM", i, "loss =", li, "\n")
    if (abs(loss_prev - li) / max(1e-12, li) <= tol) {
      if (info) cat("Step 1 converged.\n")
      break
    }

    loss_prev <- li
  }
  
  beta1 <- matrix(0, p*nbasis, Ttasks)
  for (t in seq_len(Ttasks)) {
    At_det <- A_hat[t, , ]$detach()
    th_det <- theta[, t]$detach()
    beta1[, t] <- as.numeric(torch::torch_matmul(At_det, th_det)$cpu())
  }
  if (info) cat("Step 1 completed.\n")
  
  # Step 2
  gamma <- sqrt(p*nbasis + log(Ttasks)) * C2
  beta <- torch::torch_full(
    c(p * nbasis, Ttasks),
    fill_value = 2,
    requires_grad = TRUE,
    dtype = torch::torch_float64()
  )
  
  loss_step2 <- function(beta) {
    s <- torch::torch_tensor(0, dtype = torch::torch_float64())
    beta1_t <- torch::torch_tensor(beta1, dtype = torch::torch_float64())
    for (t in seq_len(Ttasks)) {
      rr_idx <- torch::torch_tensor(idx_ranges[[t]], dtype = torch::torch_int64())
      Xt <- X_t$index_select(1, rr_idx)
      yt <- y_t$index_select(1, rr_idx)
      
      bt <- beta[, t]
      lin <- torch::torch_matmul(Xt, bt)
      
      if (link == "linear") {
        resid <- yt - lin
        data_term <- 0.5 / n_vec[t] * torch::torch_dot(resid, resid)
      } else {
        data_term <- 1 / n_vec[t] * (torch::torch_sum(torch::nnf_softplus(lin)) -
                                       torch::torch_dot(yt, lin))
        
      }
      
      reg <- gamma / sqrt(n_vec[t]) * torch::torch_norm(bt - beta1_t[, t])
      s <- s + data_term + reg
    }
    s
  }
  
  opt2 <- torch::optim_adam(list(beta), lr = lr)
  loss_prev <- Inf
  for (i in seq_len(max_iter)) {
    opt2$zero_grad()
    l2 <- loss_step2(beta)
    l2$backward()
    opt2$step()
    li <- as.numeric(l2$item())
    
    if (info && i %% 100 == 0) cat("Step2 pERM", i, "loss =", li, "\n")
    if (abs(loss_prev - li) / max(1e-12, li) <= tol) {
      if (info) cat("Step 1 converged.\n")
      break
    }
    loss_prev <- li
  }
  
  beta2 <- as.matrix(beta$detach()$cpu())
  if (info) cat("Step 2 completed.\n")
  train_preds <- vector("list", length = Ttasks)
  for (t in seq_len(Ttasks)) {
    X_task <- data[[t]]$X
    train_preds[[t]] <- drop(X_task %*% beta2[, t])
    if (link == "logistic") {
      train_preds[[t]] <- 1 / (1 + exp(-train_preds[[t]]))
    }
  }
  if(!is.null(X_test)){
    X_test_exp <- if (!is.null(nbasis) && nbasis > 1) expand_with_spline_funs(X_test, spline_funs) else X_test
    test_preds <- vector("list", length = Ttasks)
    for (t in seq_len(Ttasks)) {
      test_preds[[t]] <- drop(X_test_exp %*% beta2[, t])
      if (link == "logistic") {
        test_preds[[t]] <- 1 / (1 + exp(-test_preds[[t]]))
      }
    }
    return(list(
      step1 = beta1,
      step2 = beta2,
      A_bar = as.matrix(A_bar$detach()$cpu()),
      train_preds=train_preds,
      test_preds=test_preds
    ))
  }
  if(!is.null(X_test_list)){
    X_test_exp <- if (!is.null(nbasis) && nbasis > 1) lapply(X_test_list, function(X) expand_with_spline_funs(X, spline_funs)) else X_test_list
    test_preds <- vector("list", length = Ttasks)
    for (t in seq_len(Ttasks)) {
      test_preds[[t]] <- drop(X_test_exp[[t]] %*% beta2[, t])
      if (link == "logistic") {
        test_preds[[t]] <- 1 / (1 + exp(-test_preds[[t]]))
      }
    }
    
    return(list(
      step1 = beta1,
      step2 = beta2,
      A_bar = as.matrix(A_bar$detach()$cpu()),
      train_preds=train_preds,
      test_preds=test_preds
    ))
  }
  
  list(
    step1 = beta1,
    step2 = beta2,
    A_bar = as.matrix(A_bar$detach()$cpu()),
    train_preds=train_preds
  )
}

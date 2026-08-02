
gradient_loss <- function(X, y, b, link = "linear") {
  z <- X %*% b
  if (link == "logistic") {
    d_out <- ncol(b)
    if (d_out == 1) {
      z <- 1 / (1 + exp(-z))
    } else {
      tmp <- exp(z)
      tmp2 <- tmp %*% matrix(1, ncol = 1, nrow = d_out)
      z <- tmp / tmp2
    }
  }
  return(t(X) %*% (z - y))
}

pgd_v <- function(X, y, link, lbd, w, v, penalty = "new", eta = 0.01, T = 10) {
  v_t <- v
  n <- nrow(y)
  for (t in 1:T) {
    g <- - gradient_loss(X, y, w - v_t, link) / n
    tmp <- v_t - eta * g
    
    if (penalty == "new") {
      r <- norm(tmp, type = "F")
      if (r > 0) {
        v_t <- max(0, 1 - lbd * eta / r) * tmp
      } else {
        v_t <- 0
      }
    } else {
      v_t <- v_t - eta * (g + lbd * v_t)
    }
  }
  return(v_t)
}
 
# ----------------------------
# Vanilla ARMUL training
# ----------------------------
vanilla_train <- function(X_list, y_list, link = "linear", penalty = "new",
                          lbd = NULL, eta_global = 0.01, eta_local = 0.01,
                          T_global = 100, T_local = 1,
                          df = 10, spline = TRUE,
                          boundary_expand = 0.40,
                          clamp = FALSE,
                          print_every = 100, verbose = TRUE) {

  m <- length(X_list)
  d <- ncol(X_list[[1]])

  # ensure y matrices
  y_list <- lapply(y_list, function(y) if (is.vector(y)) matrix(y, ncol = 1) else y)
  d_out <- ncol(y_list[[1]])
  n_list <- sapply(y_list, nrow)
  N <- sum(n_list)

  if (is.null(lbd)) lbd <- 0.1 * sqrt(d / n_list)

  # ---- freeze spline basis using pooled training data ----
  if (spline) {
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
        pooled_x,
        df = df, degree = 3, intercept = TRUE,
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

    # expand each task using the frozen basis
    Xs_list <- lapply(X_list, function(X) {
      blocks <- lapply(seq_len(ncol(X)), function(j) spline_funs[[j]](X[, j]))
      do.call(cbind, blocks)
    })

    df_eff <- ncol(spline_funs[[1]](X_list[[1]][, 1]))

  } else {
    spline_funs <- NULL
    Xs_list <- X_list
    df_eff <- 1
  }

  p_eff <- d * df_eff
  gamma <- matrix(0, p_eff, d_out)
  V <- array(0, dim = c(m, p_eff, d_out))

  pooled_loss <- function(gamma, V) {
    sse <- 0
    for (j in 1:m) {
      Theta_j <- gamma - V[j,,]
      r <- Xs_list[[j]] %*% Theta_j - y_list[[j]]
      sse <- sse + sum(r^2)
    }
    sse / N
  }

  for (t in 1:T_global) {
    g <- matrix(0, p_eff, d_out)

    for (j in 1:m) {
      v <- pgd_v(Xs_list[[j]], y_list[[j]], link, lbd[j],
                 gamma, V[j,,], penalty, eta_local, T_local)
      V[j,,] <- v
      g <- g + gradient_loss(Xs_list[[j]], y_list[[j]], gamma - v, link) / N
    }

    gamma <- gamma - eta_global * g

    if (verbose && (t %% print_every == 0)) {
      loss_t <- pooled_loss(gamma, V)
      cat(sprintf("[iter %d/%d] pooled MSE = %.6f\n", t, T_global, loss_t))
    }
  }

  models <- list(
    vanilla_gamma = gamma,
    vanilla = array(0, dim = c(m, p_eff, d_out)),
    spline_funs = spline_funs
  )
  for (j in 1:m) models$vanilla[j,,] <- gamma - V[j,,]

  return(models)
}


vanilla_predict <- function(models, X_test_list, task_id, link = "linear") {
  spline_funs <- models$spline_funs
  Theta <- models$vanilla[task_id,,1, drop = FALSE] |> matrix()

  # expand test X using the SAME frozen basis
  Xs_test <- NULL
  X_task <- X_test_list[[task_id]]

  for (j in 1:ncol(X_task)) {
    if (is.null(spline_funs)) {
      Xs_j <- X_task[, j, drop = FALSE]
    } else {
      Xs_j <- spline_funs[[j]](X_task[, j])
    }
    Xs_test <- cbind(Xs_test, Xs_j)
  }

  z <- Xs_test %*% Theta
  if (link == "linear") return(z)
  if (link == "logistic") return(1 / (1 + exp(-z)))
}
# ----------------------------
# Example simulation
# ----------------------------

#set.seed(123)
#ntask <- 5         # number of tasks
#n <- 50        # samples per task
#p <- 10        # number of features

#effect_common <- 2
#X <- Y <- D <- effect <- NULL
#similarity=0.4
#for (index in 1:ntask) {
#  X[[index]] <- matrix(rnorm(n * p), n, p)
#  
#  D[[index]] <- 0.25*(X[[index]][,1])^2+(X[[index]][,2])^2 + 
#    rnorm(1)*(1-similarity)*((X[[index]][,3])^2+(X[[index]][,4])^2-2)*(index>3)+ rnorm(n)*0.5
#  effect[[index]] <- effect_common+rnorm(1)*0.1*(1-similarity)+(1-similarity)*(index>4)*0.1 # changed from 0.05 to 0.1
#  Y[[index]] <- D[[index]]*effect[[index]]+2*((rowMeans(X[[index]]))^2+4*(rowMeans(X[[index]]))^3)+ rnorm(n) #previous is 5
#}


# Train vanilla ARMUL
#models <- vanilla_train(X, D, link = "linear", T_global = 2000)

# Inspect results
#print(models$vanilla_gamma)
#y_pred <- vanilla_predict(models, X_list, task_id = 1, link = "linear")
#y_true = D[[1]]
#head(y_pred)
#y_true - y_pred
#mean((y_true - y_pred)^2)

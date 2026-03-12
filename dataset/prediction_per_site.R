CATE_predict <- function(X, D, Y, coef_estimate, split_index = NULL, number_split = 2,
                         nonpar_transfer = FALSE, propensity_score = NULL, mu0 = NULL,
                         mu1 = NULL, dim = 1, real_data = FALSE) {
  sample_size <- length(Y)
  
  if (is.null(split_index)) {
    split_index <- sample(1:number_split, sample_size, replace = TRUE)
  } else {
    number_split <- length(unique(split_index))
  }
  
  f.value <- f.gradient <- EX <- NULL
  
  if (!nonpar_transfer) {
    propensity_score <- main_effect <- mu0 <- mu1 <- array(0, c(sample_size, 1))
  } else {
    main_effect <- (mu0 + mu1) / 2
  }
  
  gradient <- hessian <- NULL
  fit <- NULL
  
  for (index in 1:number_split) {
    fit[[index]] <- list()
    gradient[[index]] <- hessian[[index]] <- list()
    f.value[[index]] <- f.gradient[[index]] <- EX[[index]] <- list()
  }
  
  for (index in 1:number_split) {
    fit[[index]] <- list()
    gradient[[index]] <- hessian[[index]] <- list()
    
    if (!nonpar_transfer) {
      propensity_score[split_index == index] <- ks(
        X[split_index != index, , drop = FALSE],
        D[split_index != index],
        X[split_index == index, , drop = FALSE]
      )
      mu0[split_index == index] <- ks(
        X[split_index != index & D == 0, , drop = FALSE],
        Y[split_index != index & D == 0],
        X[split_index == index, , drop = FALSE]
      )
      mu1[split_index == index] <- ks(
        X[split_index != index & D == 1, , drop = FALSE],
        Y[split_index != index & D == 1],
        X[split_index == index, , drop = FALSE]
      )
      main_effect[split_index == index] <- (mu0[split_index == index] + mu1[split_index == index]) / 2
    }
  }
  
  mean_square_error <- list()
  value_function <- list()
  
  for (index in 1:number_split) {
    train_idx <- split_index != index
    
    mean_square_error[[index]] <- list()
    value_function[[index]] <- list()
    
    pseudo.Y <- (D[train_idx] == 1) / propensity_score[train_idx] * (Y[train_idx] - mu1[train_idx]) -
      (D[train_idx] == 0) / (1 - propensity_score[train_idx]) * (Y[train_idx] - mu0[train_idx]) +
      mu1[train_idx] - mu0[train_idx]
    
    # preprocess X exactly as in training
    if (real_data) {
      x_all <- as.data.frame(X)
      x_train <- x_all[train_idx, , drop = FALSE]
      
      # remove same redundant columns
      x_train <- x_train[, !colnames(x_train) %in% c("age_categoryBelow_55", "yearmamsum0"), drop = FALSE]
      x_all   <- x_all[,   !colnames(x_all)   %in% c("age_categoryBelow_55", "yearmamsum0"), drop = FALSE]
      
      # remove zero-variance columns based on training fold
      keep <- apply(x_train, 2, var) > 0
      x_train <- x_train[, keep, drop = FALSE]
      x_all   <- x_all[,   keep, drop = FALSE]
      
      # scale using training fold only
      x_train_sc <- scale(x_train)
      center_vec <- attr(x_train_sc, "scaled:center")
      scale_vec  <- attr(x_train_sc, "scaled:scale")
      x_all_sc   <- scale(x_all, center = center_vec, scale = scale_vec)
      
      X_use <- as.matrix(x_all_sc)
      X_train_use <- X_use[train_idx, , drop = FALSE]
    } else {
      X_use <- as.matrix(X)
      X_train_use <- X_use[train_idx, , drop = FALSE]
    }
    
    for (index2 in 1:dim) {
      beta <- coef_estimate[[index]][[index2]]
      beta <- as.matrix(beta)
      
      link <- X_use %*% beta
      
      f.bw <- np::npregbw(
        xdat = link[train_idx, , drop = FALSE],
        ydat = pseudo.Y
      )
      f_fit <- np::npreg(f.bw, exdat = link, gradients = TRUE)
      
      f.value[[index]][[index2]] <- f_fit$mean
      f.gradient[[index]][[index2]] <- f_fit$grad
      
      EX[[index]][[index2]] <- apply(X_train_use, 2, function(t) {
        bw_tmp <- np::npregbw(
          xdat = link[train_idx, , drop = FALSE],
          ydat = t
        )
        fit_tmp <- np::npreg(bw_tmp, exdat = link, gradients = FALSE)
        fit_tmp$mean
      })
      
      unsigned_weight <- 0.5 / (propensity_score * D + (1 - propensity_score) * (1 - D))
      mean_square_error[[index]][[index2]] <- mean(
        unsigned_weight * (Y - (D - 0.5) * f_fit$mean - main_effect)^2
      )
      
      D_pred <- ifelse(f_fit$mean > 0, 1, 0)
      pi <- mean(D == 1)
      
      value_function[[index]][[index2]] <- mean(
        (D_pred == D) * Y / (D * pi + (1 - D) * (1 - pi))
      )
    }
  }
  
  return(list(
    mse = mean_square_error,
    value_function = value_function,
    f_hat = f.value
  ))
}
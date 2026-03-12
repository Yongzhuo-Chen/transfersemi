DR_tune_Per_Site <- function(coef_candidate, X, Y, split_index, max.dim, nfold, lambda){
  which_min <- error.min <- array(0, c(max.dim,1))
  for (dim in 1:max.dim){
    error <- array(0, c(nfold, length(lambda)))
    for (fold in 1:nfold){
      coef <- coef_candidate[[dim]][[fold]]
      error[fold,] <- apply(coef, 2, function(beta){
        if (dim > 1){
          coef <- array(0, dim = c(NCOL(X), dim))
          coef[1:dim,] <- pracma::eye(dim)
          coef[-(1:dim),] <- matrix(beta, nrow = NCOL(X)-dim, ncol = dim)
        } else {
          coef <- c(1, c(beta))
        }
        link <- X %*% coef
        f.bw <- np::npregbw(xdat=link[split_index==fold,,drop=FALSE], ydat=Y[split_index==fold],
                            newdata=link)
        f_fit <- np::npreg(f.bw, exdat=link, gradients = FALSE)
        mean((Y[split_index!=fold]-f_fit$mean[split_index!=fold])^2)
      })
    }
    error_aggre <- apply(error, 2, mean)
    which_min[dim] <- which.min(error_aggre)
    error.min[dim] <- min(error_aggre)
  }
  dim.opt <- which.min(error.min)
  lambda.opt <-which_min[dim.opt]
  return(list(dim.opt=dim.opt, lambda.opt=lambda.opt,error=error_aggre))
}

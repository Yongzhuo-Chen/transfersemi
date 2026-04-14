CATE_tune_Per_Site <- function(coef_candidate, X,D, Y, split_index, max.dim, nfold, lambda){
  which_min <- error.min <- array(0, c(max.dim,1))
  for (dim in 1:max.dim){
    error <- array(0, c(nfold, length(lambda)))
    for (fold in 1:nfold){
      coef <- coef_candidate[[dim]][[fold]]
      propensity_score <- ks(X[split_index==fold,], D[split_index==fold], X[split_index!=fold,])
      mu0 <- ks(X[split_index==fold & D==0,],Y[split_index==fold & D==0],X[split_index!=fold,])
      mu1 <- ks(X[split_index==fold & D==1,],Y[split_index==fold & D==1],X[split_index!=fold,])
      main_effect <- (mu0+mu1)/2
      unsigned_weight <- 1/(propensity_score*D[split_index!=fold]+(1-propensity_score)*(1-D[split_index!=fold]))
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
        mean(unsigned_weight*(Y[split_index!=fold]-(D[split_index!=fold]-0.5)*f_fit$mean[split_index!=fold]-main_effect)^2)
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

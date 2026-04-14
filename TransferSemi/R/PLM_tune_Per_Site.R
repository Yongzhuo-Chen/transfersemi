PLM_tune_Per_Site <- function(coef_candidate, X, D, Y, Y_given_X=NULL, D_given_X=NULL,
                              split_index, nfold, lambda, nonpar_transfer = FALSE){
  which_min <- error.min <- 0
  error <- array(0, c(nfold, length(lambda)))
  for (fold in 1:nfold){
    coef <- coef_candidate[[fold]]
    if (!nonpar_transfer){
      D_given_X <- ks(X[split_index==fold,], D[split_index==fold], X)
      Y_given_X <- ks(X[split_index==fold,], Y[split_index==fold], X)
    }
    error[fold,] <- sapply(coef, function(beta){
      mean((Y[split_index!=fold]-Y_given_X[split_index!=fold]-beta*(D[split_index!=fold]-D_given_X[split_index!=fold]))^2)
    })
  }
  error_aggre <- apply(error, 2, mean)
  which_min <- which.min(error_aggre)
  error.min <- min(error_aggre)
  lambda.opt <- which_min
  return(list(lambda.opt=lambda.opt,
              coef.opt=(coef_candidate[[1]][lambda.opt]+coef_candidate[[2]][lambda.opt])/2, error=error_aggre))
}

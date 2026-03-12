SemiTransfer_Par <- function(gradient, hessian, initial_value, type=c("DR", "PLM", "ATE"), lambda=NULL){
  ncoef <- length(initial_value[[1]])
  ntask <- length(initial_value)

  I <- cbind(diag(ncoef*ntask), pracma::repmat(diag(ncoef), ntask, 1))

  G <- Initial_value <- rep(0, ncoef*ntask)
  H <- Matrix::Matrix(0, nrow=ncoef*ntask, ncol=ncoef*ntask, sparse=TRUE)
  for (index in 1:ntask){
    G[((index-1)*ncoef+1):(index*ncoef)] <- gradient[[index]]
    H[((index-1)*ncoef+1):(index*ncoef), ((index-1)*ncoef+1):(index*ncoef)] <- hessian[[index]]
    Initial_value[((index-1)*ncoef+1):(index*ncoef)] <- initial_value[[index]]
  }

  svd_h <- svd(H)
  h_root <- svd_h$v %*% diag(sqrt(svd_h$d)) %*% t(svd_h$v)
  pseudo_x <- h_root %*% I
  pseudo_y <- as.vector(h_root %*% Initial_value - svd_h$v %*% diag(1/sqrt(svd_h$d)) %*% t(svd_h$v) %*% G)

  index <- c(rep(1:(ntask+1), each=ncoef))
  pf <- c(rep(1, ntask), 0)
  fit <- gglasso::cv.gglasso(x=pseudo_x, y=pseudo_y, group=index, lambda=lambda, pf=pf,intercept = FALSE)

  coef <- array(0, dim=c(ncoef, ntask))
  for (index in 1:ntask){
    coef[,index] <- fit$gglasso.fit$beta[((index-1)*ncoef+1):(index*ncoef),
                                          which(fit$lambda==fit$lambda.min)]+
      fit$gglasso.fit$beta[(ntask*ncoef+1):((ntask+1)*ncoef),
                           which(fit$lambda==fit$lambda.min)]
  }
  list(fit=fit, lambda=fit$lambda, coef=coef)
}

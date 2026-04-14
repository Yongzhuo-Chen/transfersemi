# gradient/hessian dimension is number of testing data x number of tasks
# pred is number of testing data x number of tasks
SemiTransfer_NonPar <- function(gradient, hessian, lambda=NULL, gradient.fit=TRUE){
  ntask <- NCOL(hessian)
  nxtest <- NROW(hessian)

  G <- rep(0, times=nxtest*(ntask+1))
  H <- Matrix::Matrix(0, nrow=nxtest*(ntask+1), ncol=nxtest*(ntask+1), sparse=TRUE)

  for (index in 1:ntask){
    H[((index-1)*nxtest+1):(index*nxtest), ((index-1)*nxtest+1):(index*nxtest)] <-
      diag(c(hessian[,index]))
    H[((index-1)*nxtest+1):(index*nxtest), (ntask*nxtest+1):((ntask+1)*nxtest)] <-diag(c(hessian[,index]))
    H[(ntask*nxtest+1):((ntask+1)*nxtest), ((index-1)*nxtest+1):(index*nxtest)] <-diag(c(hessian[,index]))
    G[((index-1)*nxtest+1):(index*nxtest)] <- c(gradient[,index])
  }
  H[(ntask*nxtest+1):((ntask+1)*nxtest),(ntask*nxtest+1):((ntask+1)*nxtest)] <-
    diag(c(apply(hessian,1,sum)))
  G[(ntask*nxtest+1):((ntask+1)*nxtest)] <- c(apply(gradient,1,sum))

  svd_h <- svd(H)
  h_root <- svd_h$v %*% diag(sqrt(svd_h$d)) %*% t(svd_h$v)
  pseudo_x <- -h_root
  pseudo_y <- as.vector(svd_h$v %*% diag(1/sqrt(svd_h$d)) %*% t(svd_h$v) %*% G)

  index <- rep(1:(ntask+1), each=nxtest)
  pf <- c(rep(1, ntask), 0)
  fit <- gglasso::gglasso(x=pseudo_x, y=pseudo_y, group=index, lambda=lambda, pf=pf,intercept = FALSE)

  pred <- array(0, c(nxtest, ntask, length(fit$lambda)))
  for (index1 in 1:ntask){
    for (index2 in 1:length(fit$lambda)){
      pred[,index1,index2] <- fit$beta[((index1-1)*nxtest+1):(index1*nxtest),
                                           index2]+
        fit$beta[(ntask*nxtest+1):((ntask+1)*nxtest),
                             index2]
    }

  }
  list(fit=fit, lambda=fit$lambda, pred=pred)
}

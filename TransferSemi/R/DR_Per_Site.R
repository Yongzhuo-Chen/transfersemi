DR_Per_Site <- function(X, Y, split_index=NULL, number_split=2,
                          nonpar_transfer=FALSE, f.value=NULL, EX=NULL, dim=1){
  sample_size <- length(Y)
  if (is.null(split_index)){
    split_index <- sample(1:number_split, sample_size, replace = TRUE)
  } else {
    number_split <- length(unique(split_index))
  }

  if (!nonpar_transfer){
    f.value <- f.gradient <- EX <- NULL
  } else {
    f.gradient <- NULL
  }

  coef_estimate <- gradient <- hessian <- NULL
  fit <- NULL
  for (index in 1:number_split){
    fit[[index]] <- list()
    coef_estimate[[index]] <- list()
    gradient[[index]] <- hessian[[index]] <- list()
    if (!nonpar_transfer){
      f.value[[index]] <- f.gradient[[index]] <- EX[[index]] <- list()
    } else {
      f.gradient[[index]] <- list()
    }
  }
  for (index in 1:number_split){
    fit[[index]] <- MAVE::mave(Y[split_index!=index]~X[split_index!=index,], method="csopg",max.dim=dim)
    for (index2 in 1:dim){
      beta <- fit[[index]]$dir[[index2]]
      if (dim(beta)[2] > 1){
        coef_estimate[[index]][[index2]] <- beta %*% solve(beta[1:dim,1:dim])
      } else {
        coef_estimate[[index]][[index2]] <- beta/beta[1]
      }
      if (!nonpar_transfer){
        link <- X %*% coef_estimate[[index]][[index2]]
        f.bw <- np::npregbw(xdat=link[split_index!=index,,drop=FALSE], ydat=Y[split_index!=index],
                            newdata=link)
        f_fit <- np::npreg(f.bw, exdat=link, gradients = TRUE)
        f.value[[index]][[index2]] <- f_fit$mean
        f.gradient[[index]][[index2]] <- f_fit$grad
        EX[[index]][[index2]] <- apply(X[split_index!=index,,drop=FALSE], 2, function(t){
          f.bw <- np::npregbw(xdat=link[split_index!=index,,drop=FALSE], ydat=t,
                              newdata=link)
          f_fit <- np::npreg(f.bw, exdat=link, gradients = FALSE)
          f_fit$mean
        })
      } else {
        link <- X %*% coef_estimate[[index]][[index2]]
        f.bw <- np::npregbw(xdat=link[split_index!=index,,drop=FALSE], ydat=Y[split_index!=index],
                            newdata=link)
        f_fit <- np::npreg(f.bw, exdat=link, gradients = TRUE)
        f.gradient[[index]][[index2]] <- f_fit$grad
      }
      coef.dim <- NCOL(beta)
      gradient[[index]][[index2]] <- array(0, dim = c(coef.dim*(NCOL(X)-coef.dim),1))
      hessian[[index]][[index2]] <- matrix(0, nrow=coef.dim*(NCOL(X)-coef.dim), ncol = coef.dim*(NCOL(X)-coef.dim))
      for (index3 in 1:sample_size){
        if (split_index[index3]==index){
          gradient[[index]][[index2]] <- gradient[[index]][[index2]]-c((Y[index3]-f.value[[index]][[index2]][index3])*
                                                                         kronecker(f.gradient[[index]][[index2]][index3,,drop=FALSE], X[index3,-(1:coef.dim)]-EX[[index]][[index2]][index3,-(1:coef.dim)]))
          hessian[[index]][[index2]] <- hessian[[index]][[index2]] + c(kronecker(f.gradient[[index]][[index2]][index3,,drop=FALSE],
                                                                       X[index3,-(1:coef.dim)]-EX[[index]][[index2]][index3,-(1:coef.dim)]))%*%
            t(c(kronecker(f.gradient[[index]][[index2]][index3,,drop=FALSE],
                          X[index3,-(1:coef.dim)]-EX[[index]][[index2]][index3,-(1:coef.dim)])))
        }
      }
      hessian[[index]][[index2]] <- hessian[[index]][[index2]]/(sum(split_index==index))
      gradient[[index]][[index2]] <- gradient[[index]][[index2]]/sum(split_index==index)
    }
  }
  return(list(hessian=hessian, gradient=gradient,
              coef_estimate=coef_estimate, V_estimate=hessian,
              number_split=number_split, split_index=split_index))
}

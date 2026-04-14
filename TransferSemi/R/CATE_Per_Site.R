CATE_Per_Site <- function(X, D, Y, split_index=NULL, number_split=2,
                         nonpar_transfer=FALSE, propensity_score=NULL, mu0=NULL,
                         mu1=NULL, dim=1, real_data=FALSE){
  sample_size <- length(Y)
  if (is.null(split_index)){
    split_index <- sample(1:number_split, sample_size, replace = TRUE)
  } else {
    number_split <- length(unique(split_index))
  }

  f.value <- f.gradient <- EX <- NULL

  if (!nonpar_transfer){
    propensity_score <- main_effect <- mu0 <- mu1 <- array(0, c(sample_size,1))
  } else {
    main_effect <- (mu0 + mu1)/2
  }

  coef_estimate <- gradient <- hessian <- NULL
  fit <- NULL
  for (index in 1:number_split){
    fit[[index]] <- list()
    coef_estimate[[index]] <- list()
    gradient[[index]] <- hessian[[index]] <- list()
    f.value[[index]] <- f.gradient[[index]] <- EX[[index]] <- list()
  }
  for (index in 1:number_split){
    fit[[index]] <- list()
    coef_estimate[[index]] <- list()
    gradient[[index]] <- hessian[[index]] <- list()
    if (!nonpar_transfer){
      propensity_score[split_index==index] <- ks(X[split_index!=index,], D[split_index!=index], X[split_index==index,], bandwidth_scale=2)
      mu0[split_index==index] <- ks(X[split_index!=index & D==0,],Y[split_index!=index & D==0],X[split_index==index,], bandwidth_scale=2)
      mu1[split_index==index] <- ks(X[split_index!=index & D==1,],Y[split_index!=index & D==1],X[split_index==index,], bandwidth_scale=2)
      main_effect[split_index==index] <- (mu0[split_index==index]+mu1[split_index==index])/2
    }
  }
  pseudo.Y_list <- list()
  X_list <- list()
  for (index in 1:number_split){
    pseudo.Y <- (D[split_index!=index]==1)/propensity_score[split_index!=index] * (Y[split_index!=index]- mu1[split_index!=index])-
      (D[split_index!=index]==0)/(1-propensity_score[split_index!=index]) * (Y[split_index!=index]- mu0[split_index!=index])+mu1[split_index!=index]-mu0[split_index!=index]
    pseudo.Y_list[[index]] <- pseudo.Y
    X_list[[index]] <- X[split_index!=index,]
    if(real_data){
      x_train <- as.data.frame(X[train_idx, , drop = FALSE])
      x_train <- x_train[, !colnames(x_train) %in% c("age_categoryBelow_55", "yearmamsum0"), drop = FALSE]
      x_train <- x_train[, apply(x_train, 2, var) > 0, drop = FALSE]
      x_train <- as.data.frame(scale(x_train))
      
      X_list[[index]] <- x_train
      
      x_train$y <- pseudo.Y
      
      fit[[index]] <- MAVE::mave(
        y ~ .,
        data = x_train,
        method = "csopg",
        max.dim = dim
      )
    }else{fit[[index]] <- MAVE::mave(pseudo.Y~X[split_index!=index,], method="csopg",max.dim=dim)}
    
    for (index2 in 1:dim){
      beta <- fit[[index]]$dir[[index2]]
      if (dim(beta)[2] > 1){
        coef_estimate[[index]][[index2]] <- beta %*% solve(beta[1:dim,1:dim])
      } else {
        coef_estimate[[index]][[index2]] <- beta/beta[1] #beta/beta[1]# beta / sum(beta^)2#
      }
      link <- X %*% coef_estimate[[index]][[index2]]
      f.bw <- np::npregbw(xdat=link[split_index!=index,,drop=FALSE], ydat=pseudo.Y,
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

      coef.dim <- NCOL(beta)
      gradient[[index]][[index2]] <- array(0, dim = c(coef.dim*(NCOL(X)-coef.dim),1))
      hessian[[index]][[index2]] <- matrix(0, nrow=coef.dim*(NCOL(X)-coef.dim), ncol = coef.dim*(NCOL(X)-coef.dim))

      signed_weight <- 2*(D-0.5)/(propensity_score*D+(1-propensity_score)*(1-D))
      unsigned_weight <- 0.5/(propensity_score*D+(1-propensity_score)*(1-D))
      for (index3 in 1:sample_size){
        if (split_index[index3]==index){
          gradient[[index]][[index2]] <- gradient[[index]][[index2]]-c(signed_weight[index3]*(Y[index3]-(D[index3]-0.5)*f.value[[index]][[index2]][index3]-main_effect[index3])*
                                                                         kronecker(f.gradient[[index]][[index2]][index3,,drop=FALSE], X[index3,-(1:coef.dim)]-EX[[index]][[index2]][index3,-(1:coef.dim)]))
          hessian[[index]][[index2]] <- hessian[[index]][[index2]] + unsigned_weight[index3]*c(kronecker(f.gradient[[index]][[index2]][index3,,drop=FALSE],
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
              number_split=number_split, split_index=split_index,
              pseudo.Y_list=pseudo.Y_list, X_list=X_list))
}

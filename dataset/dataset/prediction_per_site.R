CATE_predict <- function(X, D, Y, coef_estimate, split_index=NULL, number_split=2,
                          nonpar_transfer=FALSE, propensity_score=NULL, mu0=NULL,
                          mu1=NULL, dim=1){
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
  gradient <- hessian <- NULL
  fit <- NULL
  for (index in 1:number_split){
    fit[[index]] <- list()
    gradient[[index]] <- hessian[[index]] <- list()
    f.value[[index]] <- f.gradient[[index]] <- EX[[index]] <- list()
  }
  for (index in 1:number_split){
    fit[[index]] <- list()
    gradient[[index]] <- hessian[[index]] <- list()
    if (!nonpar_transfer){
      propensity_score[split_index==index] <- ks(X[split_index!=index,], D[split_index!=index], X[split_index==index,])
      mu0[split_index==index] <- ks(X[split_index!=index & D==0,],Y[split_index!=index & D==0],X[split_index==index,])
      mu1[split_index==index] <- ks(X[split_index!=index & D==1,],Y[split_index!=index & D==1],X[split_index==index,])
      main_effect[split_index==index] <- (mu0[split_index==index]+mu1[split_index==index])/2
    }
  }
  mean_square_error <- list()
  value_function <- list()
  for (index in 1:number_split){
    mean_square_error[[index]] <- list()
    value_function[[index]] <- list()
    pseudo.Y <- (D[split_index!=index]==1)/propensity_score[split_index!=index] * (Y[split_index!=index]- mu1[split_index!=index])-
      (D[split_index!=index]==0)/(1-propensity_score[split_index!=index]) * (Y[split_index!=index]- mu0[split_index!=index])+
      mu1[split_index!=index]-mu0[split_index!=index]
    for (index2 in 1:dim){

      link <- X %*% coef_estimate
      f.bw <- np::npregbw(xdat=link[split_index!=index,,drop=FALSE], ydat=pseudo.Y, newdata=link)
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
      signed_weight <- 2*(D-0.5)/(propensity_score*D+(1-propensity_score)*(1-D))
      unsigned_weight <- 0.5/(propensity_score*D+(1-propensity_score)*(1-D))
      mean_square_error[[index]][[index2]] <- mean(unsigned_weight*(Y-(D-0.5)*f_fit$mean-main_effect)^2)
      D_pred <- ifelse(f_fit$mean>0, 1, 0)
      pi <- mean(D == 1)
      
      value_function[[index]][[index2]] <- mean((D_pred == D)*Y / (D * pi + (1 - D)*(1-pi)))
    }
  }
  
  return(list(mse=mean_square_error, value_function=value_function, f_hat=f_fit$mean))
}

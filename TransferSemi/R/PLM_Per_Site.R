PLM_Per_Site <- function(X, D, Y, split_index=NULL, number_split=2,
                         nonpar_transfer=FALSE, D_given_X=NULL, Y_given_X=NULL){
  sample_size <- length(Y)
  if (is.null(split_index)){
    split_index <- sample(1:number_split, sample_size, replace = TRUE)
  } else {
    number_split <- length(unique(split_index))
  }
  if (!nonpar_transfer){
    D_given_X <- Y_given_X <- rep(0, times=sample_size)
    for (index in 1:number_split){
      D_given_X[split_index==index] <- ks(X[split_index!=index,], D[split_index!=index], X[split_index==index,])
      Y_given_X[split_index==index] <- ks(X[split_index!=index,], Y[split_index!=index], X[split_index==index,])
    }
  }
  Y_residual <- Y-Y_given_X
  D_residual <- D-D_given_X
  coef_estimate <- rep(0, times=number_split)
  V_estimate <- rep(0, times=number_split)
  fit <- NULL
  for (index in 1:number_split){
    fit[[index]] <- lm(Y_residual[split_index==index]~0+D_residual[split_index==index])
    coef_estimate[index] <- fit[[index]]$coefficients
    V_estimate[index] <- mean(D_residual[split_index==index]*D[split_index==index])
  }

  return(list(hessian=V_estimate, gradient=c(0,0),
              coef_estimate=coef_estimate, V_estimate=V_estimate,
              number_split=number_split, split_index=split_index,
              Y_given_X=Y_given_X, D_given_X=D_given_X,
              Y_residual=Y_residual, D_residual=D_residual))
}

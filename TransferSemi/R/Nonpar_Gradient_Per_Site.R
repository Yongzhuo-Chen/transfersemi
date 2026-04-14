Nonpar_Gradient_Per_Site <- function(X, Y, Y_given_X, split_index=NULL, number_split=2,
                            grid, bandwidth_scale=1, method='ks'){
  sample_size <- length(Y)
  if (is.null(split_index)){
    split_index <- sample(1:number_split, sample_size, replace = TRUE)
  } else {
    number_split <- length(unique(split_index))
  }

  gradient <- hessian <- NULL
  for (index in 1:number_split){
    gradient[[index]] <- get_gradient_nonpar_gradient(Y[split_index==index],
                                             X[split_index==index,], Y_given_X, grid,
                                             bandwidth_scale=bandwidth_scale, method=method)
    hessian[[index]] <- get_hessian_nonpar_gradient(X[split_index==index], grid,
                                           bandwidth_scale=bandwidth_scale)
  }
  return(list(hessian=hessian, gradient=gradient))
}

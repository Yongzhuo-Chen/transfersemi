# ks gets the kernel estimation
ks <- function(xx, yy, xx.test, bandwidth_scale=1){
  nobs <- nrow(as.matrix(xx))
  nvars <- ncol(as.matrix(xx))
  hopt <- (4/(nvars+2))^(1/(nvars+4)) * (nobs^(-1/(nvars+4))) * bandwidth_scale
  wm <- function(t){
    if (ncol(as.matrix(xx))==1){
      weight <- exp(-0.5 * (as.numeric(t)-xx)^2/(hopt^2)) * hopt
    } else {
      weight <- apply(xx,1,function(s){exp(-0.5 * sum((t-s)^2)/(hopt^2)) * hopt^(ncol(xx))})
    }
    weighted.mean(yy, weight)
  }
  if (nrow(as.matrix(xx.test))==1) {
    yy.test <- wm(xx.test)
  } else {
    if (ncol((as.matrix(xx.test)))==1){
      yy.test <- sapply(as.matrix(xx.test), function(t){
        wm(t)
      })
    } else {
      yy.test <- apply(as.matrix(xx.test),1,function(t){
        wm(t)
      })
    }
  }
  yy.test
}
# getgradient for nonparametric transfer learning
get_gradient_nonpar <- function(y, X, x_test, bandwidth_scale=1, method="ks"){
  if (method=='ks'){
    nobs <- nrow(as.matrix(X))
    nvars <- ncol(as.matrix(X))
    hopt <- (4/(nvars+2))^(1/(nvars+4)) * (nobs^(-1/(nvars+4))) * bandwidth_scale
    wm <- function(t){
      if (ncol(as.matrix(X))==1){
        weight <- exp(-0.5 * (as.numeric(t)-X)^2/(hopt^2)) * hopt
      } else {
        weight <- apply(X,1,function(s){exp(-0.5 * sum((t-s)^2)/(hopt^2)) * hopt^(ncol(X))})
      }
      weighted.mean(y, weight)
    }
    if (nrow(as.matrix(x_test))==1) {
      g.test <- wm(x_test)
    } else {
      if (ncol((as.matrix(x_test)))==1){
        g.test <- sapply(as.matrix(x_test), function(t){
          wm(t)
        })
      } else {
        g.test <- apply(as.matrix(x_test),1,function(t){
          wm(t)
        })
      }
    }
    g.test
  } else if (method=="np") {
    f.bw <- np::npregbw(xdat=X, ydat=as.vector(y),
                        newdata=x_test, bws=rep(bandwidth_scale, NCOL(X)), bandwidth.compute=FALSE, bwscaling=TRUE)
    f_fit <- np::npreg(f.bw, exdat=x_test)
    f_fit$mean
  }
}
# get hessian for nonparametric transfer learning
get_hessian_nonpar <- function(X, x_test, bandwidth_scale=1){
  rep(1, NROW(x_test))
}
# getgradient for nonparametric transfer learning - gradient
get_gradient_nonpar_gradient <- function(y, X, Y_given_X, x_test, bandwidth_scale=1){
  nobs <- nrow(as.matrix(X))
  nvars <- ncol(as.matrix(X))
  hopt <- (6/(nvars+2))^(1/(nvars+6)) * (nobs^(-1/(nvars+6))) * bandwidth_scale
  wm <- function(t, Y_given_X){
    if (ncol(as.matrix(X))==1){
      weight <- exp(-0.5 * (as.numeric(t)-X)^2/(hopt^2)) * hopt
      sum((X-t)*weight*(y-Y_given_X))/sum(weight)
    } else {
      weight <- apply(X,1,function(s){exp(-0.5 * sum((t-s)^2)/(hopt^2)) * hopt^(ncol(X))})
      -apply(apply(X,1,function(s){s-t}),2,function(s){weighted.mean((y-Y_given_X)*s, weight)})
    }
  }
  if (nrow(as.matrix(x_test))==1) {
    g.test <- wm(c(Y_given_X, x_test))
  } else {
    if (ncol((as.matrix(x_test)))==1){
      g.test <- apply(cbind(Y_given_X, as.matrix(x_test)),1, function(t){
        wm(t[-1],t[1])
      })
    } else {
      g.test <- apply(Y_given_X,cbind(as.matrix(x_test)),1,function(t){
        wm(t[-1], t[1])
      })
    }
  }
  g.test
}
# get hessian for nonparametric transfer learning
get_hessian_nonpar_gradient <- function(X, x_test, bandwidth_scale=1){
  nobs <- nrow(as.matrix(X))
  nvars <- ncol(as.matrix(X))
  hopt <- (6/(nvars+2))^(1/(nvars+6)) * (nobs^(-1/(nvars+6))) * bandwidth_scale
  hessian <- array(0, c(NROW(x_test), NCOL(X), NCOL(X)))
  wm <- function(t){
    if (ncol(as.matrix(X))==1){
      weight <- exp(-0.5 * (as.numeric(t)-X)^2/(hopt^2)) * hopt
      sum((as.numeric(t)-X)*weight*(as.numeric(t)-X))/sum(weight)
    } else {
      weight <- apply(X,1,function(s){exp(-0.5 * sum((t-s)^2)/(hopt^2)) * hopt^(ncol(X))})
      weight*(t-X) %*% t(t-X)/sum(weight)
    }
  }
  for (index in 1:NROW(x_test)){
    hessian[index,1:nvars,1:nvars] <- wm(x_test[index,])
  }
  hessian
}
# get grid from each site
get_grid_from_each_site <- function(X, total_sample_size, var=1, method=c("noise", "grid")){
  n <- NROW(X)
  p <- NCOL(X)
  if (method=="noise"){
    noise <- matrix(1.96*rnorm(n*p)*var/sqrt(total_sample_size),nrow=n, ncol=p)
    grid <- X+noise
  } else {
    x_seq <- NULL
    for (index in 1:p){
      x_seq[[index]] <- seq(min(x[index]), max(x[index]), by=1.96*var/sqrt(total_sample_size))
    }
    grid <- NULL
  }
  grid
}
# prediction from nonpar transfer learning
get_prediction_nonpar <- function(fit_Y_given_X, X, grid, task){
  predict <- array(0, c(NROW(X), NCOL(fit_Y_given_X$pred)))
  pred <- apply(X,1,function(t){
    distance <- array(0, c(NROW(grid),1))
    for (index in 1:NROW(grid)){
      distance[index] <- sum((t-grid[index,])^2)
    }
    fit_Y_given_X$pred[which.min(distance),task,]
  })
  t(pred)
}
#convert
convert <- function(coef, dim=1){
  ntask <- NCOL(coef)
  ncoef <- NROW(coef)/dim+dim
  coef_converted <- NULL
  for (index in 1:ntask){
    coef_converted[[index]] <- matrix(0, nrow = ncoef, ncol = dim)
    for (index2 in 1:dim){
      coef_converted[[index]][(dim+1):ncoef,index2] <- coef[(index2*(ncoef-dim-1)):((index2*(ncoef-dim-1))+NROW(coef)/dim-1),index]
    }
    coef_converted[[index]][1:dim, 1:dim] <- pracma::eye(dim)
  }
  coef_converted
}
# calculate error using mave loss function for gradient estimation tuning
get_error_dr_per_site <- function(Y, predict_f_gradient, f.value, X){
  nobs <- nrow(as.matrix(X))
  nvars <- ncol(as.matrix(X))
  hopt <- (4/(nvars+2))^(1/(nvars+4)) * (nobs^(-1/(nvars+4)))
  wm <- function(t){
    if (ncol(as.matrix(X))==1){
      weight <- exp(-0.5 * (as.numeric(t)-X)^2/(hopt^2)) * hopt
      weight/sum(weight)
    } else {
      weight <- apply(X,1,function(s){exp(-0.5 * sum((t-s)^2)/(hopt^2)) * hopt^(ncol(X))})
      weight/sum(weight)
    }
  }
  loss <- array(0, c(NCOL(predict_f_gradient),1))
  for (index in 1:NCOL(predict_f_gradient)){
    for (index2 in 1:length(Y)){
      loss[index] <- loss[index] + mean((Y-f.value[index2]-predict_f_gradient[index2,index]*(X-X[index2,]))^2*wm(X[index2,]))
    }
  }
  loss
}
# format nonpara transfer learning output into appropriate format for parametric transfer learning
format_to_list <- function(f.value, split_index){
  number_of_split <- length(unique(split_index))
  f.value.transformed <- list()
  for(index in 1:number_of_split){
    f.value.transformed[[index]] <- list(f.value)
  }
  f.value.transformed
}

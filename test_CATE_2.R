
setwd("TransferSemi/R")
files <- list.files(pattern = "\\.R$")
lapply(files, source)
library(glmnet)

simulation <- function(n=n, similarity=similarity, seed=seed, dim=dim){
result_dir = paste0("/orange/muxuan.liang/yongzhuo/TransferSemi_5/CATE_dim", dim, "/CATE_", n, "_", similarity)
if (!dir.exists(result_dir)) {
  dir.create(result_dir, recursive = TRUE)
}
# multi source CATE
ntask <- 5
p <- dim
max.dim <- 1
set.seed(seed)


effect_common <- c(-1,1,0.5,0.5,-0.5,-0.5,0,0)
X <- Y <- D <- effect <- propensity_score <- prob_Y <- NULL
for (index in 1:ntask) {
  X[[index]] <- matrix(runif(n * p, min = -1, max = 1), n, p)
  propensity_score[[index]] <- plogis(X[[index]][, 1] + 0.5 * (X[[index]][, 2]) ^
                                        2 * (index > 3))
  D[[index]] <- sapply(propensity_score[[index]], function(t) {
    rbinom(1, 1, t)
  })
  effect[[index]] <- effect_common + rnorm(1) * 0.01 + 0.5*(1 - similarity) * # 0.05 to 0.1
    (index > 4)
  prob_Y[[index]] <- plogis((2*D[[index]]-1) * X[[index]] %*% effect[[index]] +
                              0.2* (X[[index]] %*% effect[[index]]+1) ^ 2)
  Y[[index]] <- sapply(prob_Y[[index]], function(t) {
    rbinom(1, 1, t)
  })
}

# generate split_index
split_index <- NULL
for (index in 1:ntask) {
  split_index[[index]] <- sample(1:2, n, replace = TRUE)
}

# Method without Nonpar Transfer
# each site no nonpar transfer
fit_each_site <- NULL
for (index in 1:ntask) {
  fit_each_site[[index]] <- CATE_Per_Site(X[[index]], D[[index]], Y[[index]], split_index =
                                            split_index[[index]], dim = 1)
}

########################################################################
########################################################################
########################################################################
fit.sai <- list()
ceof_sai <- list()
auxi_coef <- list()
lambda_seq <- 10^seq(2, -2, by = -0.1)
for (index in 1:ntask) {
  X_aux <- do.call(rbind, X[-index])
  Y_aux <- do.call(c, Y[-index])
  D_aux <- do.call(c, D[-index])
  interaction_terms <- X_aux * D_aux
  lasso_X <- cbind(X_aux, D_aux, interaction_terms)
  lasso_fit <- cv.glmnet(lasso_X, Y_aux, alpha = 0, lmabda=lambda_seq, intercept = FALSE)
  beta <- coef(lasso_fit, s = "lambda.min")[-1]
  p_x <- ncol(X_aux)
  interaction_coef <- beta[(p_x + 2):(2 * p_x + 1)]

  
  Y_transfer <- Y[[index]]
  interaction_terms <- X[[index]] * D[[index]]
  X_transfer <- cbind(X[[index]], D[[index]], interaction_terms)
  
  cv_fit <- cv.glmnet(x = X_transfer, y = Y_transfer - X_transfer %*% beta, alpha = 1, lambda = lambda_seq, intercept = FALSE)
  best_lambda <- cv_fit$lambda.min
  best_coef <- coef(cv_fit, s = best_lambda)
  interaction_coef_delta <- best_coef[(p_x + 2):(2 * p_x + 1)]
  
  ceof_sai[[index]] <- interaction_coef + interaction_coef_delta
  
  ceof_sai[[index]] <- ceof_sai[[index]] / (ceof_sai[[index]][1])
}
########################################################################
########################################################################
########################################################################


# tranfer learning update no nonpar transfer (main node)
Para_transfer <- function() {
  fit <- NULL
  lambda <- NULL
  for (dr.dim in 1:max.dim) {
    fit[[dr.dim]] <- list()
    for (fold in 1:2) {
      ## Gradient and Hessian
      gradient <- hessian <- NULL
      for (index in 1:ntask) {
        gradient[[index]] <- fit_each_site[[index]]$gradient[[fold]][[dr.dim]]
        hessian[[index]] <- fit_each_site[[index]]$hessian[[fold]][[dr.dim]]
      }

      ## Initial value
      initial_value <- list()
      for (index in 1:ntask) {
        initial_value[[index]] <- c(t(fit_each_site[[index]]$coef_estimate[[fold]][[dr.dim]][-(1:dr.dim), ]))
      }
      fit[[dr.dim]][[fold]] <- SemiTransfer_Par(gradient, hessian, initial_value, type = "DR")
      lambda <- c(lambda, fit[[dr.dim]][[fold]]$fit$gglasso.fit$lambda)
    }
  }
  lambda <- sort(unique(lambda))
  for (dr.dim in 1:max.dim) {
    fit[[dr.dim]] <- list()
    for (fold in 1:2) {
      ## Gradient and Hessian
      gradient <- hessian <- NULL
      for (index in 1:ntask) {
        gradient[[index]] <- fit_each_site[[index]]$gradient[[fold]][[dr.dim]]
        hessian[[index]] <- fit_each_site[[index]]$hessian[[fold]][[dr.dim]]
      }

      ## Initial value
      initial_value <- list()
      for (index in 1:ntask) {
        initial_value[[index]] <- c(t(fit_each_site[[index]]$coef_estimate[[fold]][[dr.dim]][-(1:dr.dim), ]))
      }
      fit[[dr.dim]][[fold]] <- SemiTransfer_Par(gradient,
                                                hessian,
                                                initial_value,
                                                type = "CATE",
                                                lambda = lambda)
    }
  }
  ## tuning optimal lambda
  ### get coefficients
  coef_candidate <- list()
  for (index in 1:ntask) {
    coef_candidate[[index]] <- list()
    for (dr.dim in 1:max.dim) {
      coef_candidate[[index]][[dr.dim]] <- list()
      for (fold in 1:2) {
        ncoef <- dr.dim * p - dr.dim * dr.dim
        coef_candidate[[index]][[dr.dim]][[fold]] <- fit[[dr.dim]][[fold]]$fit$gglasso.fit$beta[((index -
                                                                                                    1) * ncoef + 1):(index * ncoef), ] +
          fit[[dr.dim]][[fold]]$fit$gglasso.fit$beta[(ntask * ncoef +
                                                        1):((ntask + 1) * ncoef), ]
      }
    }
  }
  ### cross-validation to tune on split dataset
  fit_tuned <- coef_est <- NULL
  error <- array(0, c(ntask, length(lambda)))
  for (index in 1:ntask) {
    fit_tuned[[index]] <- CATE_tune_Per_Site(
      coef_candidate[[index]],
      X[[index]],
      D[[index]],
      Y[[index]],
      split_index = split_index[[index]],
      max.dim = max.dim,
      nfold = 2,
      lambda = lambda
    )
    error[index, ] <- fit_tuned[[index]]$error
  }
  error.all.task <- apply(error, 2, mean)
  for (index in 1:ntask) {
    coef_est[[index]] <- (coef_candidate[[index]][[1]][[1]][, which.min(error.all.task)] +
                            coef_candidate[[index]][[1]][[2]][, which.min(error.all.task)]) /
      2
  }
  list(tuned = coef_est,
       untuned = (fit[[1]][[1]]$coef + fit[[1]][[2]]$coef) / 2)
}
coef_para <- Para_transfer()
coef_est <- coef_para$tuned
coef_est_untuned <- coef_para$untuned

#initial value
coef_est_no_transfer <- NULL
for (index in 1:ntask) {
  coef_est_no_transfer <- cbind(
    coef_est_no_transfer,
    0.5 * (
      fit_each_site[[index]]$coef_estimate[[1]][[1]] + fit_each_site[[index]]$coef_estimate[[2]][[1]]
    )
  )
}
print(coef_est_no_transfer)

# Method wit Nonpar Transfer
## generate common grid
grid <- list()
total_sample_size <- n * ntask
for (index in 1:ntask){
  grid[[index]] <- list()
  for(fold in 1:2){
    grid[[index]][[fold]]<- get_grid_from_each_site(X=X[[index]],
                                                    total_sample_size, method="noise")
  }
}
# Nonparametric Transfer Learning
transfer_Y_given_X <- function(Y, X, split_index, split_index.test, X.test=NULL){
  bandwidth_scale_seq <- seq(0.5,1,length.out=5)
  cv.bandwidth.error <- array(0, c(length(bandwidth_scale_seq),ntask))
  predict_Y_given_X_bandwidth <- NULL
  predict_Y_given_X <- predict_Y_given_X.test <- NULL
  predict_Y_given_X_opt <- NULL
  for (k in 1:length(bandwidth_scale_seq)){
    for (index.test in 1:ntask){
      bandwidth_scale <- bandwidth_scale_seq[k]
      ## each site for nonpar transfer
      Y_given_X_transfer_each_site <- NULL
      fit_Y_given_X <- list()
      lambda <-NULL
      for (fold in 1:2){
        for (index in 1:ntask){
          Y_given_X_transfer_each_site[[index]] <- Nonpar_Per_Site(X=X[[index]], Y=Y[[index]],
                                                                   split_index=split_index[[index]],
                                                                   grid = grid[[index.test]][[fold]], bandwidth_scale=bandwidth_scale, method="np")
        }
        ## nonpar transfer for Y_given_X and D_given_X
        ### transfer learning for Y_given_X (main node) indexed by fold is fitted using data not in this fold
        gradient <- hessian <- array(0, dim = c(NROW(grid[[index.test]][[fold]]), ntask))
        for (index in 1:ntask) {
          pseudo_fold_index <- switch(fold, '1'=2, '2'=1)
          gradient[,index] <- -Y_given_X_transfer_each_site[[index]]$gradient[[pseudo_fold_index]]
          hessian[,index] <- Y_given_X_transfer_each_site[[index]]$hessian[[pseudo_fold_index]]
        }
        fit_Y_given_X[[fold]] <- SemiTransfer_NonPar(gradient, hessian)
        lambda <- c(lambda, fit_Y_given_X[[fold]]$fit$lambda)
      }
      lambda <- sort(unique(lambda))
      cv.error <- array(0, dim=c(2,length(lambda)))
      predict_Y_given_X_opt[[index.test]] <- array(0, c(NROW(X.test[[index.test]]),1))
      for (fold in 1:2){
        for (index in 1:ntask){
          Y_given_X_transfer_each_site[[index]] <- Nonpar_Per_Site(X=X[[index]] , Y=Y[[index]],
                                                                   split_index=split_index[[index]],
                                                                   grid = grid[[index.test]][[fold]], bandwidth_scale=bandwidth_scale)
        }
        ## nonpar transfer for Y_given_X and D_given_X
        ### transfer learning for Y_given_X (main node) indexed by fold is fitted using data not in this fold
        gradient <- hessian <- array(0, dim = c(NROW(grid[[index.test]][[fold]]), ntask))
        for (index in 1:ntask) {
          pseudo_fold_index <- switch(fold, '1'=2, '2'=1)
          gradient[,index] <- -Y_given_X_transfer_each_site[[index]]$gradient[[pseudo_fold_index]]
          hessian[,index] <- Y_given_X_transfer_each_site[[index]]$hessian[[pseudo_fold_index]]
        }
        fit_Y_given_X[[fold]] <- SemiTransfer_NonPar(gradient, hessian, lambda=lambda)
        ### prediction match (each site) on fold 1
        predict_Y_given_X[[fold]] <- get_prediction_nonpar(fit_Y_given_X[[fold]],
                                                           X=X[[index.test]],
                                                           grid[[index.test]][[fold]], task=index.test)
        predict_Y_given_X.test[[fold]] <- get_prediction_nonpar(fit_Y_given_X[[fold]],
                                                           X=X.test[[index.test]],
                                                           grid[[index.test]][[fold]], task=index.test)
        ### calculate error (each site) on fold
        cv.error[fold,] <- apply(predict_Y_given_X[[fold]][split_index[[index.test]]==fold,],2, function(t){mean((t-
                                                                                                                    Y[[index.test]][split_index[[index.test]]==fold])^2)})

      }
      for (fold in 1:2){
        predict_Y_given_X_opt[[index.test]][split_index.test[[index.test]]==fold] <-
          predict_Y_given_X.test[[fold]][split_index.test[[index.test]]==fold,which.min(cv.error[fold,])]
      }
      cv.bandwidth.error[k, index.test] <- (min(cv.error[1,])+min(cv.error[2,]))/2
    }
    predict_Y_given_X_bandwidth[[k]] <- predict_Y_given_X_opt
  }
  f.value_opt <-NULL
  for (index in 1:ntask){
    f.value_opt[[index]] <- predict_Y_given_X_bandwidth[[which.min(cv.bandwidth.error[,index])]][[index]]
  }
  f.value_opt
}
Y1 <- Y0 <- X1 <- X0 <- split_index1 <- split_index0 <-NULL
for (index in 1:ntask) {
  Y1[[index]] <- Y[[index]][D[[index]]==1]
  Y0[[index]] <- Y[[index]][D[[index]]==0]
  X1[[index]] <- X[[index]][D[[index]]==1,]
  X0[[index]] <- X[[index]][D[[index]]==0,]
  split_index1[[index]] <- split_index[[index]][D[[index]]==1]
  split_index0[[index]] <- split_index[[index]][D[[index]]==0]
}
mu1_opt <- transfer_Y_given_X(Y=Y1, X=X1, split_index = split_index1, split_index.test = split_index, X.test=X)
mu0_opt <- transfer_Y_given_X(Y=Y0, X=X0, split_index = split_index0, split_index.test = split_index, X.test=X)
D_given_X_opt <- transfer_Y_given_X(Y=D, X=X, split_index = split_index, split_index.test = split_index, X.test=X)

# each fit gradient and hessian for parametric
fit_each_site_nonpar_tranfer <- NULL
for (index in 1:ntask){
  fit_each_site_nonpar_tranfer[[index]] <- CATE_Per_Site(X[[index]], D[[index]], Y[[index]], nonpar_transfer = TRUE,
                                                         propensity_score = D_given_X_opt[[index]],
                                                         mu0 = mu0_opt[[index]],
                                                         mu1 = mu1_opt[[index]],
                                                         split_index = split_index[[index]], dim = 1)
}

# tranfer learning update with nonpar transfer (main node)
Semipara_Transfer <- function(){
  fit_both <- NULL
  lambda <- NULL
  for (dr.dim in 1:1){
    fit_both[[dr.dim]] <- list()
    for (fold in 1:2){
      ## Gradient and Hessian
      gradient <- hessian <- NULL
      for (index in 1:ntask) {
        gradient[[index]] <- fit_each_site_nonpar_tranfer[[index]]$gradient[[fold]][[dr.dim]]
        hessian[[index]] <- fit_each_site_nonpar_tranfer[[index]]$hessian[[fold]][[dr.dim]]
      }

      ## Initial value
      initial_value <- list()
      for (index in 1:ntask) {
        initial_value[[index]] <- fit_each_site_nonpar_tranfer[[index]]$coef_estimate[[fold]][[1]][-1]
      }
      fit_both[[dr.dim]][[fold]] <- SemiTransfer_Par(gradient, hessian, initial_value=initial_value,
                                                     type = "CATE")
      lambda <- c(lambda, fit_both[[dr.dim]][[fold]]$lambda)
    }
  }
  lambda <- sort(unique(lambda))
  for (dr.dim in 1:1){
    fit_both[[dr.dim]] <- list()
    for (fold in 1:2){
      ## Gradient and Hessian
      gradient <- hessian <- NULL
      for (index in 1:ntask) {
        gradient[[index]] <- fit_each_site_nonpar_tranfer[[index]]$gradient[[fold]][[dr.dim]]
        hessian[[index]] <- fit_each_site_nonpar_tranfer[[index]]$hessian[[fold]][[dr.dim]]
      }

      ## Initial value
      initial_value <- list()
      for (index in 1:ntask) {
        initial_value[[index]] <- fit_each_site_nonpar_tranfer[[index]]$coef_estimate[[fold]][[1]][-1]
      }
      fit_both[[dr.dim]][[fold]] <- SemiTransfer_Par(gradient, hessian, initial_value=initial_value,
                                                     type = "CATE", lambda=lambda)
    }
  }
  ## tuning optimal lambda
  ### get coefficients
  coef_candidate <- list()
  for (index in 1:ntask){
    coef_candidate[[index]] <- list()
    for (dr.dim in 1:1){
      coef_candidate[[index]][[dr.dim]] <- list()
      for (fold in 1:2){
        ncoef <- dr.dim*p-dr.dim*dr.dim
        coef_candidate[[index]][[dr.dim]][[fold]] <- fit_both[[dr.dim]][[fold]]$fit$gglasso.fit$beta[((index-1)*ncoef+1):(index*ncoef),]+
          fit_both[[dr.dim]][[fold]]$fit$gglasso.fit$beta[(ntask*ncoef+1):((ntask+1)*ncoef),]
      }
    }
  }
  ### cross-validation to tune on split dataset
  fit_tuned <- coef_est_both <- NULL
  error <- array(0, c(ntask, length(lambda)))
  for (index in 1:ntask){
    fit_tuned[[index]] <- CATE_tune_Per_Site(
      coef_candidate[[index]],
      X[[index]],
      D[[index]],
      Y[[index]],
      split_index = split_index[[index]],
      max.dim = max.dim,
      nfold = 2,
      lambda = lambda
    )
    error[index,] <- fit_tuned[[index]]$error
  }
  error.all.task <- apply(error,2,mean)
  for (index in 1:ntask){
    coef_est_both[[index]] <- (coef_candidate[[index]][[1]][[1]][,which.min(error.all.task)]+
                                 coef_candidate[[index]][[1]][[2]][,which.min(error.all.task)])/2
  }
  return(list(tuned=coef_est_both, untuned=(fit_both[[1]][[1]]$coef+fit_both[[1]][[2]]$coef)/2))
}
coef_semipara <- Semipara_Transfer()
coef_est_both <- coef_semipara$tuned
coef_est_both_untuned <- coef_semipara$untuned

# compare mse
effect.cbind <- apply(sapply(effect, c), 2, function(t) {
  t / t[1]
})
mse_par_transfer_tuned <- array(0, c(ntask, 1))
for (index in 1:ntask) {
  if (NCOL(coef_est[[index]]) == 1) {
    mse_par_transfer_tuned[index] <- mean((coef_est[[index]] - effect.cbind[-1, index]) ^
                                           2)
  } else {
    mse_par_transfer_tuned[index] <- NA
  }
}
mse_par_transfer <- apply((coef_est_untuned - effect.cbind[-1, ]) ^
                            2, 2, mean)
mse_nonpar_transfer_tuned <- array(0, c(ntask, 1))
for (index in 1:ntask){
  if (NCOL(coef_est_both[[index]])==1){
    mse_nonpar_transfer_tuned[index] <- mean((coef_est_both[[index]]-effect.cbind[-1,index])^2)
  } else {
    mse_nonpar_transfer_tuned[index] <- NA
  }
}
print(mse_nonpar_transfer_tuned)
mse_nonpar_transfer <- apply((coef_est_both_untuned-effect.cbind[-1,])^2,2,mean)
print(mse_nonpar_transfer)
mse_standard <- apply((coef_est_no_transfer - effect.cbind) ^ 2, 2, mean)
ceof_sai_transfer <- do.call(cbind, ceof_sai)
mse_sai_transfer<- apply((ceof_sai_transfer - effect.cbind) ^ 2, 2, mean)
print("Sai_Transfer") 
print(mse_sai_transfer)
res <- rbind("Para_Transfer"=c(mse_par_transfer),"Para_Transfer_Tuned"=c(mse_par_transfer_tuned),
             "NonPara_Transfer"=c(mse_nonpar_transfer), "NonPara_Transfer_Tuned"=c(mse_nonpar_transfer_tuned),
             "Baseline"=c(mse_standard), "Sai_Transfer"=mse_sai_transfer)
colnames(res) <- c("Task1", "Task2", "Task3", "Task4", "Task5")

  
  save(result = res,
    file = paste0(
      result_dir,
      "/",
      seed,
      ".RData"
    ))

}
args <- commandArgs(trailingOnly = TRUE)
n <- as.numeric(args[1])         # First argument passed
similarity <- as.numeric(args[2]) # Second argument passed
seed <- as.numeric(args[3])
dim <- as.numeric(args[4])
cat(seed, n, similarity)
simulation(n, similarity, seed, dim)


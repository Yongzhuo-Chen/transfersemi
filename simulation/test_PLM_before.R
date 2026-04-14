
setwd("../TransferSemi/R")
files <- list.files(pattern = "\\.R$")
lapply(files, source)
# multi source partial linear model
library(glmnet)
run_simulation <- function(seed, n, similarity, dim){
  
ntask <- 5
n <- n # vary this from 200 to 500
p <- dim
similarity <- similarity #vary this from 1, 0.8, 0.6, 0.4
set.seed(seed)

dictionary_mse = paste0("../../results_5_resotre_dim", dim,"/mse_n_",n,"_simi_",similarity)
if (!file.exists(dictionary_mse)) {
  dir.create(dictionary_mse, recursive = TRUE)
}
filename <- paste0(dictionary_mse,"/mse_data_seed_", seed, ".rds")
dictionary_estimate = paste0("results_5_resotre_dim", dim, "/est_n_",n,"_simi_",similarity)
if (!file.exists(dictionary_estimate)) {
  dir.create(dictionary_estimate, recursive = TRUE)
}
filename_estimates <- paste0(dictionary_estimate, "/estimate_data_seed_", seed, ".rds")
dictionary_time = paste0("time_5_restore_dim_", dim, "/_n_",n,"_simi_",similarity)
if (!file.exists(dictionary_time)) {
  dir.create(dictionary_time, recursive = TRUE)
}
#if (file.exists(filename)) {
#  cat("File for seed", seed, "already exists. Skipping this seed.\n")
#  return(NULL)  
#}
cat("Start the simulation for seed ",seed, "n", n, "similarity", similarity)
effect_common <- 2
X <- Y <- D <- effect <- NULL
for (index in 1:ntask) {
  X[[index]] <- matrix(rnorm(n * p), n, p)

  D[[index]] <- 0.25*(X[[index]][,1])^2+(X[[index]][,2])^2 + 
    rnorm(1)*(1-similarity)*((X[[index]][,3])^2+(X[[index]][,4])^2-2)*(index>3)+ rnorm(n)*0.5
  effect[[index]] <- effect_common+rnorm(1)*0.1*(1-similarity)+(1-similarity)*(index>4)*0.1 # changed from 0.05 to 0.1
  Y[[index]] <- D[[index]]*effect[[index]]+2*((rowMeans(X[[index]]))^2+4*(rowMeans(X[[index]]))^3)+ rnorm(n) #previous is 5


  #X = matrix(rnorm(n_obs*n_vars), nrow=n_obs, ncol=n_vars)
  #  d = X[,1]*X[,5]+ X[,7]^4 + rnorm(n_obs)
  #  y = theta[i]*d + sin(X[,2])+exp(X[,3])+(X[,6])^2 + rnorm(n_obs)
}

# generate split_index
split_index <- NULL
for (index in 1:ntask){
  split_index[[index]] <- sample(1:2, n, replace = TRUE)
}

# Method without Nonpar Transfer
# each site no nonpar transfer
##############################################################################################################################
##############################################################################################################################
##############################################################################################################################

Sai_transfer <- list()

for (index in 1:ntask){
  X_aux <- do.call(rbind, X[-index])
  Y_aux <- do.call(c, Y[-index])
  D_aux <- do.call(c, D[-index])
  lasso_X <- cbind(X_aux, D_aux)
  lasso_fit <- cv.glmnet(lasso_X, Y_aux, alpha = 1, intercept = FALSE)
  coef_vec_aux <- as.vector(coef(lasso_fit, s = "lambda.min"))

  pseudo.X <- cbind(X[[index]], D[[index]])
  pseudo_y <- Y[[index]] - pseudo.X%*%coef_vec_aux[-1]
  lambda_seq <- 10^seq(2, -3, by = -0.1)
  cv_fit <- cv.glmnet(x = (pseudo.X), y = pseudo_y, alpha = 1, lambda = lambda_seq, intercept = FALSE)
  coef_vec <- as.vector(coef(cv_fit, s = "lambda.min"))
  coef_axr  <- coef_vec[length(coef_vec)]
  Sai_transfer[[index]] <- coef_vec_aux[length(coef_vec)] + coef_axr
}
##############################################################################################################################
##############################################################################################################################
##############################################################################################################################

# Method of RsNet
##############################################################################################################################
##############################################################################################################################
##############################################################################################################################
Net_transfer <- list()
for (index in 1:ntask){
  proc <- process_for_rtl(X, D, Y, effect, target_indx = index, method="PLM")

  str(proc, max.level = 1)
  fit_src <- fit_sources(proc$X_list, proc$Z_list, proc$y_list, hidden = c(5,3), p = 1, epochs = 100)
  fit_tgt <- fit_target_ols(fit_src, proc$X0, proc$Z0, proc$y0)
  Net_transfer[[index]] <- fit_tgt$coef[1]
}

##############################################################################################################################
##############################################################################################################################
##############################################################################################################################

# Method of ARMUL
##############################################################################################################################
##############################################################################################################################
##############################################################################################################################
sample_size = length(Y[[1]])
ARMUL_transfer <- list()
ARMUL_D_res <- list()
ARMUL_Y_res <- list()
number_split=2
index_select <- sample(1:number_split, sample_size, replace = TRUE)

for (index in 1:ntask){
  # Train vanilla ARMUL
  sample_size <- length(Y[[index]])
  D_given_X <- Y_given_X <- rep(0, times=sample_size)
  for (split_index in 1:number_split){
    X_train <- lapply(X, function(t) t[index_select==split_index,])
    D_train <- lapply(D, function(t) t[index_select==split_index])
    Y_train <- lapply(Y, function(t) t[index_select==split_index])
    
    X_test <- lapply(X, function(t) t[index_select!=split_index,])
    D_test <- lapply(D, function(t) t[index_select!=split_index])
    Y_test <- lapply(Y, function(t) t[index_select!=split_index])
    
    
    models <- vanilla_train(X_train, D_train, link = "linear", T_global = 200, spline=TRUE)
    D_given_X[index_select!=split_index] <- vanilla_predict(models, X_test, task_id = index, link = "linear")
    models <- vanilla_train(X_train, Y_train, link = "linear", T_global = 200, spline=TRUE)
    Y_given_X[index_select!=split_index] <- vanilla_predict(models, X_test, task_id = index, link = "linear")
    
  } 
  D_residual <- D[[index]] - D_given_X
  Y_residual <- Y[[index]] - Y_given_X
  ARMUL_D_res[[index]] <- D_residual |> matrix(ncol=1)
  ARMUL_Y_res[[index]] <- Y_residual |> matrix(ncol=1)
}
ARMUL_coef <- rep(0, times=number_split)
for (index in 1:ntask){
  # Train vanilla ARMUL
  for(split_index in 1:number_split){
    D_res_train <- lapply(ARMUL_D_res, function(t) t[index_select == split_index, , drop = FALSE])
    Y_res_train <- lapply(ARMUL_Y_res, function(t) t[index_select == split_index,])
    D_res_test <- lapply(ARMUL_D_res, function(t) t[index_select != split_index, , drop = FALSE])
    models <- vanilla_train(D_res_train, Y_res_train, link = "linear", T_global = 200, spline=FALSE)
    ARMUL_coef[split_index] <- models$vanilla[index,,1]
    ARMUL_transfer[[index]] <- mean(ARMUL_coef)
  }
  
}
##############################################################################################################################
##############################################################################################################################
##############################################################################################################################

run_pERM_once_sameC <- function(X, D, Y, effect,
                                ntask,
                                C1, C2,
                                number_split = 2,
                                seed = 1,
                                r_fixed = 3,
                                nbasis_fixed = 5,
                                target_task = NULL,
                                info = FALSE) {
  set.seed(seed)

  sample_size  <- length(Y[[1]])
  index_select <- sample(1:number_split, sample_size, replace = TRUE)

  n <- sample_size
  D_given_Xs <- replicate(ntask, rep(0, n), simplify = FALSE)
  Y_given_Xs <- replicate(ntask, rep(0, n), simplify = FALSE)

  # --------------------------------
  # Stage 1: D~X and Y~X use SAME C1,C2
  # --------------------------------
  for (split_index in 1:number_split) {
    tr <- which(index_select == split_index)
    te <- which(index_select != split_index)

    X_tr_list <- lapply(seq_len(ntask), function(t) as.matrix(X[[t]][tr, , drop = FALSE]))
    X_te_list <- lapply(seq_len(ntask), function(t) as.matrix(X[[t]][te, , drop = FALSE]))
    D_tr_list <- lapply(seq_len(ntask), function(t) as.numeric(D[[t]][tr]))
    Y_tr_list <- lapply(seq_len(ntask), function(t) as.numeric(Y[[t]][tr]))

    dataD_tr <- lapply(seq_len(ntask), function(t) {
      list(X = X_tr_list[[t]], y = D_tr_list[[t]])
    })

    dataY_tr <- lapply(seq_len(ntask), function(t) {
      list(X = X_tr_list[[t]], y = Y_tr_list[[t]])
    })

    fitD <- pERM_torch(
      data = dataD_tr,
      r = r_fixed, nbasis = nbasis_fixed,
      C1 = C1, C2 = C2,
      info = info, link = "linear",
      X_test_list = X_te_list
    )

    fitY <- pERM_torch(
      data = dataY_tr,
      r = r_fixed, nbasis = nbasis_fixed,
      C1 = C1, C2 = C2,
      info = info, link = "linear",
      X_test_list = X_te_list
    )

    for (t in seq_len(ntask)) {
      D_given_Xs[[t]][te] <- fitD$test_preds[[t]]
      Y_given_Xs[[t]][te] <- fitY$test_preds[[t]]
    }
  }

  # --------------------------------
  # Residuals
  # --------------------------------
  pERM_D_res <- lapply(seq_len(ntask), function(t) {
    matrix(as.numeric(D[[t]] - D_given_Xs[[t]]), ncol = 1)
  })

  pERM_Y_res <- lapply(seq_len(ntask), function(t) {
    matrix(as.numeric(Y[[t]] - Y_given_Xs[[t]]), ncol = 1)
  })

  # --------------------------------
  # Stage 2: residual-on-residual uses SAME C1,C2
  # --------------------------------
  coef_mat <- matrix(0, nrow = number_split, ncol = ntask)
  peRMdata <- vector("list", ntask)

  for (split_index in 1:number_split) {
    tr <- which(index_select == split_index)

    for (t in seq_len(ntask)) {
      peRMdata[[t]] <- list(
        X = as.matrix(pERM_D_res[[t]][tr, , drop = FALSE]),
        y = as.numeric(pERM_Y_res[[t]][tr, 1])
      )
    }

    model <- pERM_torch(
      data = peRMdata,
      r = 1, nbasis = 1,
      C1 = C1, C2 = C2,
      info = info, link = "linear"
    )

    for (t in seq_len(ntask)) {
      coef_mat[split_index, t] <- model$step2[1, t]
    }
  }

  pERM_transfer <- vector("list", ntask)
  for (t in seq_len(ntask)) {
    pERM_transfer[[t]] <- mean(coef_mat[, t])
  }

  est_vec <- sapply(pERM_transfer, as.numeric)
  eff_vec <- sapply(effect, as.numeric)

  loss <- if (!is.null(target_task)) {
    (est_vec[target_task] - eff_vec[target_task])^2
  } else {
    mean((est_vec - eff_vec)^2)
  }

  list(
    loss = loss,
    transfer = pERM_transfer,
    est_vec = est_vec,
    C1 = C1,
    C2 = C2
  )
}
tune_pERM_global_sameC <- function(X, D, Y, effect,
                                   ntask,
                                   C1_grid = 10^seq(-4, 1, length.out = 6),
                                   C2_grid = 10^seq(-4, 1, length.out = 6),
                                   number_split = 2,
                                   seed = 1,
                                   r_fixed = 3,
                                   nbasis_fixed = 5,
                                   target_task = NULL,
                                   info = TRUE,
                                   verbose = TRUE) {
  best <- list(
    loss = Inf,
    C1 = NA,
    C2 = NA,
    transfer = NULL,
    est_vec = NULL
  )

  for (c1 in C1_grid) {
    for (c2 in C2_grid) {

      out <- tryCatch({
        run_pERM_once_sameC(
          X = X, D = D, Y = Y, effect = effect,
          ntask = ntask,
          C1 = c1, C2 = c2,
          number_split = number_split,
          seed = seed,
          r_fixed = r_fixed,
          nbasis_fixed = nbasis_fixed,
          target_task = target_task,
          info = info
        )
      }, error = function(e) NULL)

      if (is.null(out)) next

      if (verbose) {
        message(sprintf("pERM: C1=%.4e C2=%.4e loss=%.6f", c1, c2, out$loss))
      }

      if (is.finite(out$loss) && out$loss < best$loss) {
        best <- out
      }
    }
  }

  best
}
best_perm <- tune_pERM_global_sameC(
  X = X, D = D, Y = Y, effect = effect,
  ntask = ntask,
  C1_grid = 10^seq(-4, 1, length.out = 4),
  C2_grid = 10^seq(-4, 1, length.out = 4),
  number_split = 2,
  seed = seed,
  r_fixed = 3,
  nbasis_fixed = 5,
  target_task = NULL, 
  info = FALSE
)

best_perm$C1
best_perm$C2
best_perm$est_vec
best_perm$loss
best_perm_by_task <- vector("list", ntask)

for (index in 1:ntask) {
  best_perm_by_task[[index]] <- tune_pERM_global_sameC(
    X = X, D = D, Y = Y, effect = effect,
    ntask = ntask,
    C1_grid = 10^seq(-4, 1, length.out = 4),
    C2_grid = 10^seq(-4, 1, length.out = 4),
    number_split = 2,
    seed = seed,
    r_fixed = 3,
    nbasis_fixed = 5,
    target_task = index,
    info = FALSE,
    verbose = TRUE
  )
}
##############################################################################################################################
##############################################################################################################################
##############################################################################################################################


# Data Pooling method
##############################################################################################################################
##############################################################################################################################
##############################################################################################################################

split_index <- NULL
for (index in 1:ntask){
  split_index[[index]] <- sample(1:2, n, replace = TRUE)
}
pooled_res <- list()
pooled_X <- do.call(rbind, X)
pooled_Y <- do.call(c, Y)
pooled_D <- do.call(c, D)
pooled_temp <- PLM_Per_Site(X[[index]], D[[index]], Y[[index]], split_index=split_index[[index]])
for (index in 1:ntask){
  pooled_res[[index]] <- pooled_temp$coef_estimate |> mean()
}
print("The pooled results are:")  
print(pooled_res)
##############################################################################################################################
##############################################################################################################################
##############################################################################################################################
split_index <- NULL
for (index in 1:ntask){
  split_index[[index]] <- sample(1:2, n, replace = TRUE)
}
# Method without Nonpar Transfer
# each site no nonpar transfer
fit_each_site <- NULL
for (index in 1:ntask){
  fit_each_site[[index]] <- PLM_Per_Site(X[[index]], D[[index]], Y[[index]], split_index=split_index[[index]])
}
Para_Transfer <- function(){
  # tranfer learning update no nonpar transfer (main node)
  fit <- NULL
  lambda <- 10*10^(-seq(0,10, length.out=200))
  for (fold in 1:2){
    ## Gradient and Hessian
    gradient <- hessian <- NULL
    for (index in 1:ntask) {
      gradient[[index]] <- fit_each_site[[index]]$gradient[fold]
      hessian[[index]] <- fit_each_site[[index]]$hessian[fold]
    }
    
    ## Initial value
    initial_value <- list()
    for (index in 1:ntask) {
      initial_value[[index]] <- fit_each_site[[index]]$coef_estimate[fold]
    }
    
    fit[[fold]] <- SemiTransfer_Par(gradient, hessian, initial_value, type = "PLM", lambda=lambda)
    lambda <- c(lambda, fit[[fold]]$lambda)
  }
  lambda <- sort(unique(lambda))
  fit <- NULL
  for (fold in 1:2){
    ## Gradient and Hessian
    gradient <- hessian <- NULL
    for (index in 1:ntask) {
      gradient[[index]] <- fit_each_site[[index]]$gradient[fold]
      hessian[[index]] <- fit_each_site[[index]]$hessian[fold]
    }
    
    ## Initial value
    initial_value <- list()
    for (index in 1:ntask) {
      initial_value[[index]] <- fit_each_site[[index]]$coef_estimate[fold]
    }
    
    fit[[fold]] <- SemiTransfer_Par(gradient, hessian, initial_value, type = "PLM", lambda=lambda)
  }
  ## tuning optimal lambda
  ### get coefficients
  coef_candidate <- list()
  for (index in 1:ntask){
    coef_candidate[[index]] <- list()
    for (fold in 1:2){
      coef_candidate[[index]][[fold]] <- fit[[fold]]$fit$gglasso.fit$beta[index,]+
        fit[[fold]]$fit$gglasso.fit$beta[ntask+1,]
    }
  }
  ### cross-validation to tune on split dataset
  fit_tuned <- coef_est <-coef_est_tuned <- NULL
  error <- array(0, c(ntask, length(lambda)))
  for (index in 1:ntask){
    fit_tuned[[index]] <- PLM_tune_Per_Site(coef_candidate[[index]], X[[index]], D[[index]],
                                            Y[[index]], split_index=split_index[[index]], 
                                            nfold=2, lambda=lambda)
    error[index,] <- fit_tuned[[index]]$error
  }
  error.all.task <- apply(error,2,mean)
  for (index in 1:ntask){
    coef_est_tuned[[index]] <- (coef_candidate[[index]][[1]][which.min(error.all.task)]+
                                  coef_candidate[[index]][[2]][which.min(error.all.task)])/2
  }
  return(list(coef_est_tuned=coef_est_tuned, coef_est_untuned=(fit[[1]]$coef+fit[[2]]$coef)/2))
}
start_time <- Sys.time()
fit_para_transfer <- Para_Transfer()
coef_est_tuned <- fit_para_transfer$coef_est_tuned
coef_est <- fit_para_transfer$coef_est_untuned
end_time <- Sys.time()
time_para_transfer <- end_time - start_time
#initial value
coef_est_no_transfer <- NULL
for (index in 1:ntask) {
  coef_est_no_transfer <- c(coef_est_no_transfer, mean(fit_each_site[[index]]$coef_estimate))
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

## Nonparametric transfer
transfer_Y_given_X <- function(Y, X){
  bandwidth_scale_seq <- seq(0.5,1,length.out=8)
  cv.bandwidth.error <- array(0, c(length(bandwidth_scale_seq),ntask))
  predict_Y_given_X_bandwidth <- NULL
  predict_Y_given_X <- NULL
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
      lambda <- sort(unique(lambda), decreasing = TRUE)
      cv.error <- array(0, dim=c(2,length(lambda)))
      predict_Y_given_X_opt[[index.test]] <- array(0, c(NROW(X[[index.test]]),1))
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
        ### calculate error (each site) on fold 
        cv.error[fold,] <- apply(predict_Y_given_X[[fold]][split_index[[index.test]]==fold,],2, function(t){mean((t-
                                    Y[[index.test]][split_index[[index.test]]==fold])^2)})
        
      }
      for (fold in 1:2){
        predict_Y_given_X_opt[[index.test]][split_index[[index.test]]==fold] <-
          predict_Y_given_X[[fold]][split_index[[index.test]]==fold,which.min(cv.error[fold,])]
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
start_time <- Sys.time()
Y_given_X_opt <- transfer_Y_given_X(Y=Y, X=X)
D_given_X_opt <- transfer_Y_given_X(Y=D, X=X)

# nonparametric_transfer
Nonpara_Transfer <- function(){
  ## each fit gradient and hessian for parametric
  fit_each_site_nonpar_tranfer <- NULL
  for (index in 1:ntask){
    fit_each_site_nonpar_tranfer[[index]] <- PLM_Per_Site(X[[index]], D[[index]],
                                                          Y[[index]], split_index=split_index[[index]],
                                                          Y_given_X = Y_given_X_opt[[index]],
                                                          D_given_X = D_given_X_opt[[index]],
                                                          nonpar_transfer = TRUE)
  }
  
  # tranfer learning update with nonpar transfer (main node)
  fit_both <- lambda <-  NULL
  for (fold in 1:2){
    ## Gradient and Hessian
    gradient <- hessian <- NULL
    for (index in 1:ntask) {
      gradient[[index]] <- fit_each_site_nonpar_tranfer[[index]]$gradient[fold]
      hessian[[index]] <- fit_each_site_nonpar_tranfer[[index]]$hessian[fold]
    }
    
    ## Initial value
    initial_value <- list()
    for (index in 1:ntask) {
      initial_value[[index]] <- fit_each_site_nonpar_tranfer[[index]]$coef_estimate[fold]
    }
    
    fit_both[[fold]] <- SemiTransfer_Par(gradient, hessian, initial_value, type = "PLM")
    lambda <- c(lambda, fit_both[[fold]]$lambda)
  }
  ## tuning optimal lambda
  fit_both <- NULL
  lambda <- sort(unique(lambda))
  for (fold in 1:2){
    ## Gradient and Hessian
    gradient <- hessian <- NULL
    for (index in 1:ntask) {
      gradient[[index]] <- fit_each_site_nonpar_tranfer[[index]]$gradient[fold]
      hessian[[index]] <- fit_each_site_nonpar_tranfer[[index]]$hessian[fold]
    }
    
    ## Initial value
    initial_value <- list()
    for (index in 1:ntask) {
      initial_value[[index]] <- fit_each_site_nonpar_tranfer[[index]]$coef_estimate[fold]
    }
    
    fit_both[[fold]] <- SemiTransfer_Par(gradient, hessian, initial_value, type = "PLM", lambda=lambda)
  }
  
  ### get coefficients
  coef_candidate <- list()
  for (index in 1:ntask){
    coef_candidate[[index]] <- list()
    for (fold in 1:2){
      coef_candidate[[index]][[fold]] <- fit_both[[fold]]$fit$gglasso.fit$beta[index,]+
        fit_both[[fold]]$fit$gglasso.fit$beta[ntask+1,]
    }
  }
  ### cross-validation to tune on split dataset
  fit_tuned_both <- coef_est_both_tuned <- coef_est_both <- NULL
  error <- array(0, c(ntask, length(lambda)))
  for (index in 1:ntask){
    fit_tuned_both[[index]] <- PLM_tune_Per_Site(coef_candidate[[index]], X[[index]], D[[index]],
                                                 Y[[index]], split_index=split_index[[index]], 
                                                 Y_given_X = Y_given_X_opt[[index]],
                                                 D_given_X = D_given_X_opt[[index]],
                                                 nfold=2, lambda=lambda, nonpar_transfer=TRUE)
    error[index,] <- fit_tuned_both[[index]]$error
  }
  error.all.task <- apply(error,2,mean)
  for (index in 1:ntask){
    coef_est_both_tuned[[index]] <- (coef_candidate[[index]][[1]][which.min(error.all.task)]+
                                       coef_candidate[[index]][[2]][which.min(error.all.task)])/2
  }
  return(list(coef_est_both_tuned=coef_est_both_tuned, coef_est_both_untuned=(fit_both[[1]]$coef+fit_both[[2]]$coef)/2))
}
fit_nonpara_transfer <- Nonpara_Transfer()
coef_est_both_tuned <- fit_nonpara_transfer$coef_est_both_tuned
coef_est_both <- fit_nonpara_transfer$coef_est_both_untuned
end_time <- Sys.time()
time_nonpar_transfer <- end_time - start_time
# compare mse
mse_sai_transfer <- (unlist(effect)-unlist(Sai_transfer))^2
mse_net_transfer <- (unlist(effect)-unlist(Net_transfer))^2
mse_ARMUL_transfer <- (unlist(effect)-unlist(ARMUL_transfer))^2
mse_pERM_transfer <- (unlist(effect)-unlist(pERM_transfer))^2
mse_par_transfer <- (coef_est-unlist(effect))^2
mse_par_transfer_tuned <- (unlist(coef_est_tuned)-unlist(effect))^2
mse_nonpar_transfer <- (coef_est_both-unlist(effect))^2
mse_nonpar_transfer_tuned <- (unlist(coef_est_both_tuned)-unlist(effect))^2
mse_standard <- (coef_est_no_transfer-unlist(effect))^2
mse_pooled <- (unlist(effect)-unlist(pooled_res))^2
res <- data.frame(res=rbind(mse_sai_transfer, mse_net_transfer, mse_ARMUL_transfer, mse_pERM_transfer,mse_pooled, mse_par_transfer,mse_par_transfer_tuned, 
                            mse_nonpar_transfer, mse_nonpar_transfer_tuned, 
                            mse_standard))
row.names(res) <- c("Sai_Transfer","Net_Transfer","ARMUL_transfer", "pERM_Transfer","Pooled", "Para_Transfer", "Para_Transfer_Tuned","NonPara_Transfer", "NonPara_Transfer_Tuned", "Baseline")
colnames(res) <- c('Task1', 'Task2', 'Task3', 'Task4', 'Task5')
print(res)
saveRDS(res, file = filename)

results_list <- list(
  coef_est = coef_est,
  coef_est_tuned = coef_est_tuned,
  coef_est_both = coef_est_both,
  coef_est_both_tuned = coef_est_both_tuned,
  coef_est_no_transfer = coef_est_no_transfer,
  effect = effect,
  ARMUL_transfer=ARMUL_transfer
)
print("The results list:")
print(results_list)
# Save the list to a .RData file
saveRDS(results_list, file = filename_estimates)

time <- list(
  time_para_transfer = time_para_transfer,
  time_nonpar_transfer = time_nonpar_transfer
)

# save time as csv file
time_filename <- paste0(dictionary_time, "/time_data_seed_", seed, ".csv")
write.csv(time, file = time_filename, row.names = FALSE)
}


library(parallel)
library(pbmcapply)
# Number of simulations
num_simulations <- 100
seeds <- 1:100

num_cores <- as.numeric(Sys.getenv("SLURM_CPUS_PER_TASK", unset = 1))
if (num_cores <= 1) {  # Fallback if SLURM_CPUS_PER_TASK is not set
  num_cores <- detectCores()  # Detect all available cores on the node
}

cat("Number of cores used:", num_cores, "\n")


args <- commandArgs(trailingOnly = TRUE)
n <- as.numeric(args[1])         # First argument passed
similarity <- as.numeric(args[2]) # Second argument passed
seed <- as.numeric(args[3])
dim <- as.numeric(args[4])
cat("The dim is", dim, "\n")
cat(seed, n, similarity, dim)
cat("The dim is", dim, "\n")
run_simulation(seed, n, similarity, dim)


script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_arg) != 1L) stop("Run this simulation with Rscript.", call. = FALSE)
script_path <- normalizePath(sub("^--file=", "", script_arg[[1L]]), mustWork = TRUE)
source(file.path(dirname(script_path), "reproducibility_helpers.R"))
repo_root <- simulation_repo_root()

simulation <- function(n=n, similarity=similarity, seed=seed, dim=dim){
cate_root <- file.path(output_root, paste0("CATE_dim", dim))
scenario_dir <- paste0("CATE_", n, "_", similarity)
result_dir <- ensure_output_dir(file.path(cate_root, scenario_dir))
result_dir_pro <- ensure_output_dir(file.path(cate_root, "propensity_score", scenario_dir))
result_dir_mu <- ensure_output_dir(file.path(cate_root, "outcome_model", scenario_dir))
# multi source CATE
ntask <- 5
p <- dim
max.dim <- 1
cpu_device <- seed_reproducibly(seed)


effect_common <- c(1,-1,0.5,0.5,-0.5,-0.5,0,0)
X <- Y <- D <- effect <- propensity_score <- prob_Y <- NULL
for (index in 1:ntask) {
  X[[index]] <- matrix(runif(n * p, min = -1, max = 1), n, p)
  propensity_score[[index]] <- plogis(X[[index]][, 1] + 0.5 * (X[[index]][, 2]) ^
                                        2 * (index > 3))
  D[[index]] <- sapply(propensity_score[[index]], function(t) {
    rbinom(1, 1, t)
  })
  effect[[index]] <- effect_common + rnorm(1) * 0.01 + 0.8*(1 - similarity) * # 0.05 to 0.1
    (index > 4)# + 0.1*(1-similarity)*(index > 3)
  #effect[[index]][2:8] <- effect_common[2:8]+ rnorm(1) * 0.01 + 0.5 * (1 - similarity) * (index > 4)
  #effect[[index]] <- -effect[[index]] / effect[[index]][1]
  prob_Y[[index]] <- plogis((6*D[[index]]-1) * X[[index]] %*% effect[[index]] +
                              0.1 * (X[[index]] %*% effect[[index]]+1) ^ 2)
  Y[[index]] <- sapply(prob_Y[[index]], function(t) {
    rbinom(1, 1, t)
  })
}
split_index <- NULL
for (index in 1:ntask) {
  split_index[[index]] <- sample(1:2, n, replace = TRUE)
} 
fit_each_site <- NULL
for (index in 1:ntask) {
  fit_each_site[[index]] <- CATE_Per_Site(X[[index]], D[[index]], Y[[index]], split_index =
                                            split_index[[index]], dim = 1)
}
# Data Pooling Method
#############################################################################################################################
##############################################################################################################################
##############################################################################################################################
pooled_res <- NULL
pooled_D <- do.call(c, D)
pooled_Y <- do.call(c, Y)
pooled_X <- do.call(rbind, X)
pooled_fit <- CATE_Per_Site(pooled_X, pooled_D, pooled_Y, dim = 1)
for (index in 1:ntask){
  pooled_res[[index]] <- (pooled_fit$coef_estimate[[1]][[1]][-1] + pooled_fit$coef_estimate[[2]][[1]][-1]) * 0.5
}

# generate split_index
split_index <- NULL
for (index in 1:ntask) {
  split_index[[index]] <- sample(1:2, n, replace = TRUE)
}

# Method without Nonpar Transfer
# each site no nonpar transfer


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
  lasso_fit <- cv.glmnet(lasso_X, Y_aux, alpha = 1, lmabda=lambda_seq, intercept = FALSE)
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
  #ceof_sai[[index]] <- ceof_sai[[index]] / sqrt(sum(ceof_sai[[index]]^2))
  ceof_sai[[index]] <- ceof_sai[[index]] / (ceof_sai[[index]][1])
}
########################################################################
########################################################################
########################################################################

# Method of RsNet
##############################################################################################################################
##############################################################################################################################
##############################################################################################################################
Net_transfer <- list()
for (index in 1:ntask){
  proc <- process_for_rtl(X, X, Y, effect, target_indx = index)

  str(proc, max.level = 1)
  fit_src <- fit_sources(
    proc$X_list, proc$Z_list, proc$y_list,
    hidden = c(5,5), p = 1, epochs = 100,
    device = cpu_device
  )
  fit_tgt <- fit_target_ols(fit_src, proc$X0, proc$Z0, proc$y0)
  Net_transfer[[index]] <- fit_tgt$coef[1:p]
  Net_transfer[[index]] <- Net_transfer[[index]] / (Net_transfer[[index]][1])
}

##############################################################################################################################
##############################################################################################################################
##############################################################################################################################

# Method of ARMUL
##############################################################################################################################
##############################################################################################################################
##############################################################################################################################
ARMUL_transfer <- list()
ARMUL_D_res <- list()
ARMUL_Y_res <- list() 
pseudo.Y = list()
sample_size = length(Y[[1]])
number_split=2
index_select <- sample(1:number_split, sample_size, replace = TRUE)
split_index <- NULL
for (index in 1:ntask) {
  split_index[[index]] <- sample(1:2, n, replace = TRUE)
}
Y1 <- list(); Y0 <- list(); X1 <- list(); X0 <- list()
split_index1 <- list(); split_index0 <- list()
mu1_opt <- mu0_opt <- D_given_X_opt <- replicate(5, list(rep(0, times=sample_size)))
X_train <- list(); X_test <- list(); D_train <- list(); D_test <- list()
for (split_indx in 1:number_split){
  
  for (index in 1:ntask) {
    sample_size <- length(Y[[index]])
    D_given_X <- Y_given_X <- rep(0, times=sample_size)
    Y1[[index]] <- Y[[index]][D[[index]]==1 & index_select==split_indx]
    Y0[[index]] <- Y[[index]][D[[index]]==0 & index_select==split_indx]
    X1[[index]] <- X[[index]][D[[index]]==1 & index_select==split_indx,]
    X0[[index]] <- X[[index]][D[[index]]==0 & index_select==split_indx,]
    X_train[[index]] <- X[[index]][index_select==split_indx,]
    X_test[[index]] <- X[[index]][index_select!=split_indx,]
    D_train[[index]] <- D[[index]][index_select==split_indx]
    D_test[[index]] <- D[[index]][index_select!=split_indx]

  }
  mu1_model <- vanilla_train(X1, Y1, link = "logistic", T_global = 1000, spline=TRUE)
  mu0_model <- vanilla_train(X0, Y0, link = "logistic", T_global = 1000, spline=TRUE)
  D_given_X_model <- vanilla_train(X_train, D_train, link = "logistic", T_global = 1000, spline=TRUE)
  

  for (index in 1:ntask){
    mu1_opt[[index]][index_select!=split_indx] <- vanilla_predict(mu1_model, X_test, task_id = index, link = "logistic")
    mu0_opt[[index]][index_select!=split_indx] <- vanilla_predict(mu0_model, X_test, task_id = index, link = "logistic")
    D_given_X_opt[[index]][index_select!=split_indx] <- vanilla_predict(D_given_X_model, X_test, task_id = index, link = "logistic")
  }
}
propensity_score = D_given_X_opt
error <- sapply(1:ntask, function(t) {
  mean((propensity_score[[t]] - D[[t]])^2)
})
# save error as csv
error_df <- data.frame(
  Task = 1:ntask,
  MSE = error
)
write.csv(
  error_df,
  file = file.path(result_dir_pro, paste0("ARMUL_propensity_score_error_", seed, ".csv")),
  row.names = FALSE
)
coef_est <- list()
for(split_indx in 1:number_split){
  coef_est[[split_indx]] <- list()
  for (index in 1:ntask){
    pseudo.Y[[index]] <- (D[[index]][index_select!=split_indx]==1)/propensity_score[[index]][index_select!=split_indx] * 
      (Y[[index]][index_select!=split_indx] - mu1_opt[[index]][index_select!=split_indx])-
      (D[[index]][index_select!=split_indx]==0)/(1-propensity_score[[index]][index_select!=split_indx]) *
      (Y[[index]][index_select!=split_indx]- mu0_opt[[index]][index_select!=split_indx])+
      mu1_opt[[index]][index_select!=split_indx]-mu0_opt[[index]][index_select!=split_indx]
    X_train[[index]] <- X[[index]][index_select!=split_indx,]
  }
  models <- vanilla_train(X_train, pseudo.Y, link = "linear", T_global = 2000, spline=FALSE)
  for (index in 1:ntask){
    # Train vanilla ARMUL
    coef_est[[split_indx]][[index]] <- models$vanilla[,,1][index,] / models$vanilla[,,1][index,1] 
  }
}
ARMUL_transfer <- NULL

for (index in 1:ntask) {
  ARMUL_transfer <- rbind(
    ARMUL_transfer,
    0.5 * (
      coef_est[[1]][[index]] + coef_est[[2]][[index]]
    )
  )
}
ARMUL_transfer = t(ARMUL_transfer)
##############################################################################################################################
##############################################################################################################################
##############################################################################################################################
# Compute MAE for each task
MAE_mu1 <- numeric(ntask)
MAE_mu0 <- numeric(ntask)

for (t in 1:ntask) {

  err_mu1 <- Y[[t]] - mu1_opt[[t]]
  err_mu0 <- Y[[t]] - mu0_opt[[t]]

  MAE_mu1[t] <- mean(abs(err_mu1))
  MAE_mu0[t] <- mean(abs(err_mu0))
}

# Combine into one data.frame
MAE_df <- data.frame(
  task = 1:ntask,
  MAE_mu1 = MAE_mu1,
  MAE_mu0 = MAE_mu0
)

# Save one combined file
write.csv(
  MAE_df,
  file = file.path(result_dir_mu, paste0("ARMUL_MAE_all_tasks_", seed, ".csv")),
  row.names = FALSE
)



# Method of pERM
##############################################################################################################################
##############################################################################################################################
##############################################################################################################################
TrainTestError <- data.frame(
  task = 1:ntask,
  mu1_train = NA, mu1_test = NA,
  mu0_train = NA, mu0_test = NA,
  e_train = NA,  e_test  = NA,      # propensity score
  pseudo_train = NA, pseudo_test = NA
)

pERM_transfer <- list()
pERM_D_res <- list()
pERM_Y_res <- list() 
pseudo.Y = list()
peRMdata <- list()
Y1 <- list(); Y0 <- list(); X1 <- list(); X0 <- list()
index_select <- sample(1:number_split, sample_size, replace = TRUE)
split_index1 <- list(); split_index0 <- list(); X_train <- list(); X_test <- list(); D_train <- list()
propensity_score <- mu1_opt <- mu0_opt <- replicate(ntask, list(rep(0, times=n)))
for (split_indx in 1:number_split){
  for (index in 1:ntask) {
    Y1[[index]] <- Y[[index]][D[[index]]==1 & index_select==split_indx]
    Y0[[index]] <- Y[[index]][D[[index]]==0 & index_select==split_indx]
    X1[[index]] <- X[[index]][D[[index]]==1 & index_select==split_indx,]
    X0[[index]] <- X[[index]][D[[index]]==0 & index_select==split_indx,]
    X_train[[index]] <- X[[index]][index_select==split_indx,]
    X_test[[index]] <- X[[index]][index_select!=split_indx,]
    D_train[[index]] <- D[[index]][index_select==split_indx]
  }
  for (t in 1:ntask){
    peRMdata[[t]] <- list(X = as.matrix(X1[[t]]), y = as.matrix(Y1[[t]]))
  }
  pERM <- pERM_torch(
    peRMdata, r = 3, nbasis = 100, info = TRUE, link = "logistic",
    X_test_list = X_test, device = cpu_device
  )
  mu1_opt <- Map(function(p, pred) {
    p[index_select != split_indx] <- pred
    p
  }, mu1_opt, pERM$test_preds)
  # Save predicted mu1_opt
  
  for (t in 1:ntask){
    peRMdata[[t]] <- list(X = as.matrix(X0[[t]]), y = as.matrix(Y0[[t]]))
  }
  pERM <- pERM_torch(
    peRMdata, r = 3, nbasis = 10, info = TRUE, link = "logistic",
    X_test_list = X_test, device = cpu_device
  )
  mu0_opt <- Map(function(p, pred) {
    p[index_select != split_indx] <- pred
    p
  }, mu0_opt, pERM$test_preds)
  for (t in 1:ntask){
    peRMdata[[t]] <- list(X = as.matrix(X_train[[t]]), y = as.matrix(D_train[[t]]))
  }
  pERM <- pERM_torch(
    peRMdata, r = 3, nbasis = 10, info = TRUE, link = "logistic",
    X_test_list = X_test, device = cpu_device
  )
  # calculate error between predicted propensity score and true propensity score
  
  propensity_score <- Map(function(p, pred) {
    p[index_select != split_indx] <- pred
    p
  }, propensity_score, pERM$test_preds)
}
error <- sapply(1:ntask, function(t) {
  mean((propensity_score[[t]] - D[[t]])^2)
})
# save error as csv
error_df <- data.frame(
  Task = 1:ntask,
  MSE = error
)
# save propensity score as csv
propensity_score_df <- do.call(cbind, propensity_score)
colnames(propensity_score_df) <- paste0("Task", 1:ntask)
write.csv(
  error_df,
  file = file.path(result_dir_pro, paste0("pERM_propensity_score_error_", seed, ".csv")),
  row.names = FALSE
)
coef_est <- list()
for(split_indx in 1:number_split){
  coef_est[[split_indx]] <- list()
  for (index in 1:ntask){
    pseudo.Y[[index]] <- (D[[index]][index_select!=split_indx]==1)/propensity_score[[index]][index_select!=split_indx] * 
      (Y[[index]][index_select!=split_indx] - mu1_opt[[index]][index_select!=split_indx])-
      (D[[index]][index_select!=split_indx]==0)/(1-propensity_score[[index]][index_select!=split_indx]) *
      (Y[[index]][index_select!=split_indx]- mu0_opt[[index]][index_select!=split_indx])+
      mu1_opt[[index]][index_select!=split_indx]-mu0_opt[[index]][index_select!=split_indx]
    X_train[[index]] <- X[[index]][index_select!=split_indx,]
    X_test[[index]] <- X[[index]][index_select==split_indx,]
    peRMdata[[index]] <- list(X = as.matrix(X_train[[index]]), y = as.matrix(pseudo.Y[[index]]))
  }
  pERM <- pERM_torch(
    peRMdata, r = 2, nbasis = 1, info = TRUE, link = "logistic",
    X_test_list = X_test, device = cpu_device
  )
  for (index in 1:ntask){
    coef_est[[split_indx]][[index]] <- pERM$step2[,index] / pERM$step2[1,index] 
  }
}
pERM_transfer <- NULL

for (index in 1:ntask) {
  pERM_transfer <- rbind(
    pERM_transfer,
    0.5 * (
      coef_est[[1]][[index]] + coef_est[[2]][[index]]
    )
  )
}
pERM_transfer=t(pERM_transfer)
##############################################################################################################################
##############################################################################################################################
##############################################################################################################################
print("finished fitting pERM")


# Compute MSE for each task
MSE_mu1 <- numeric(ntask)
MSE_mu0 <- numeric(ntask)

for (t in 1:ntask) {

  # residuals for each model
  err_mu1 <- Y[[t]] - mu1_opt[[t]]
  err_mu0 <- Y[[t]] - mu0_opt[[t]]

  # MSE
  MSE_mu1[t] <- mean(err_mu1^2)
  MSE_mu0[t] <- mean(err_mu0^2)
}

# Combine into one data frame
MSE_df <- data.frame(
  task = 1:ntask,
  MSE_mu1 = MSE_mu1,
  MSE_mu0 = MSE_mu0
)

# Save one CSV with all MSE results
write.csv(
  MSE_df,
  file = file.path(result_dir_mu, paste0("pERM_MSE_all_tasks_", seed, ".csv")),
  row.names = FALSE
)









print("finished fitting other methods")

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
#effect.cbind <- apply(sapply(effect, c), 2, function(t) {
#  t / sqrt(sum(t^2))
#})
mse_par_transfer_tuned <- array(0, c(ntask, 1))
for (index in 1:ntask) {
  if (NCOL(coef_est[[index]]) == 1) {
    #coef_est[[index]] <- c(1, coef_est[[index]]) / sqrt(sum(c(1, coef_est[[index]]) ^ 2))
    mse_par_transfer_tuned[index] <- mean((coef_est[[index]] - effect.cbind[-1, index]) ^
                                           2)
  } else {
    mse_par_transfer_tuned[index] <- NA
  }
}
#coef_est_untuned <- rbind(1, coef_est_untuned)
#coef_est_untuned <- coef_est_untuned / apply(coef_est_untuned, 2, function(t) {
#  sqrt(sum(t ^ 2))
#})
mse_par_transfer <- apply((coef_est_untuned - effect.cbind[-1, ]) ^
                            2, 2, mean)
mse_nonpar_transfer_tuned <- array(0, c(ntask, 1))
for (index in 1:ntask){
  if (NCOL(coef_est_both[[index]])==1){
    #coef_est_both[[index]] <- c(1, coef_est_both[[index]]) / sqrt(sum(c(1, coef_est_both[[index]]) ^ 2))
    mse_nonpar_transfer_tuned[index] <- mean((coef_est_both[[index]]-effect.cbind[-1,index])^2)
  } else {
    mse_nonpar_transfer_tuned[index] <- NA
  }
}
print(mse_nonpar_transfer_tuned)
#coef_est_both_untuned <- rbind(1, coef_est_both_untuned)
#coef_est_both_untuned <-  sqrt(colSums(coef_est_both_untuned^2))
print(coef_est_both_untuned)
mse_nonpar_transfer <- apply((coef_est_both_untuned-effect.cbind[-1,])^2,2,mean)
print(mse_nonpar_transfer)
mse_standard <- apply((coef_est_no_transfer[-1,] - effect.cbind[-1,]) ^ 2, 2, mean)
ceof_sai_transfer <- do.call(cbind, ceof_sai)
mse_sai_transfer<- apply((ceof_sai_transfer[-1,] - effect.cbind[-1,]) ^ 2, 2, mean)
print("Sai_Transfer") 
print(mse_sai_transfer)
mse_ARMUL_transfer<- apply((ARMUL_transfer[-1,] - effect.cbind[-1,]) ^ 2, 2, mean)
ceof_net_transfer <- do.call(cbind, Net_transfer)
mse_net_transfer<- apply((ceof_net_transfer[-1,] - effect.cbind[-1,]) ^ 2, 2, mean)
print("Net_Transfer")
print(mse_net_transfer)
coef_pERM_transfer <- pERM_transfer
print("pERM_transfer")
print(coef_pERM_transfer)
mse_pERM_transfer<- apply((coef_pERM_transfer[-1,] - effect.cbind[-1,]) ^ 2, 2, mean)
print("pERM_transfer")
print(mse_pERM_transfer)
pooled_res <- do.call(cbind, pooled_res)
print(pooled_res)
mse_pooled <- apply((pooled_res - effect.cbind[-1,]) ^ 2, 2, mean)

res <- rbind("Para_Transfer"=c(mse_par_transfer),"Para_Transfer_Tuned"=c(mse_par_transfer_tuned),
             "NonPara_Transfer"=c(mse_nonpar_transfer), "NonPara_Transfer_Tuned"=c(mse_nonpar_transfer_tuned),
             "Baseline"=c(mse_standard), "Sai_Transfer"=mse_sai_transfer, "Net_Transfer"=mse_net_transfer,
              "ARMUL_transfer"=mse_ARMUL_transfer, "pERM_transfer"=mse_pERM_transfer, "Pooled"=mse_pooled)
colnames(res) <- c("Task1", "Task2", "Task3", "Task4", "Task5")

print(res)

result <- res
save(result,
     file = file.path(result_dir, paste0(seed, ".RData")))


}
usage <- "Rscript simulation/test_CATE.R <n> <similarity> <seed> <dim>"
cli <- parse_numeric_cli(c("n", "similarity", "seed", "dim"), usage)
validate_common_simulation_args(cli)
if (cli$dim != 8) {
  stop("dim must equal 8 for the CATE data-generating mechanism.", call. = FALSE)
}
n <- cli$n
similarity <- cli$similarity
seed <- cli$seed
dim <- cli$dim
output_root <- simulation_output_root(repo_root)
source_transfersemi(repo_root)
library(glmnet)
cat(seed, n, similarity)

simulation(n, similarity, seed, dim)


setwd("../TransferSemi/R")
files <- list.files(pattern = "\\.R$")
lapply(files, source)
# multi source partial linear model
library(glmnet)
run_simulation <- function(seed, n, similarity, dim, lambda_length){
  
ntask <- 5
n <- n # vary this from 200 to 500
p <- dim
similarity <- similarity #vary this from 1, 0.8, 0.6, 0.4
set.seed(seed)
df_fixed = 2

dictionary_mse = paste0("../../semi-transfer-learning/results_6_dim", dim,"/mse_n_",n,"_simi_",similarity, "lambda_len", lambda_length)
if (!file.exists(dictionary_mse)) {
  dir.create(dictionary_mse, recursive = TRUE)
}
filename <- paste0(dictionary_mse,"/mse_data_seed_", seed, ".rds")
dictionary_estimate = paste0("../../semi-transfer-learning/results_6_dim", dim, "/est_n_",n,"_simi_",similarity, "lambda_len", lambda_length)
if (!file.exists(dictionary_estimate)) {
  dir.create(dictionary_estimate, recursive = TRUE)
}
filename_estimates <- paste0(dictionary_estimate, "/estimate_data_seed_", seed, ".rds")
dictionary_time = paste0("../../semi-transfer-learning/time_6_dim", dim, "/_n_",n,"_simi_",similarity, "lambda_len", lambda_length)
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

# Method without Nonpar Transfer
# each site no nonpar transfer
fit_each_site <- NULL
for (index in 1:ntask){
  fit_each_site[[index]] <- PLM_Per_Site(X[[index]], D[[index]], Y[[index]], split_index=split_index[[index]])
}
Para_Transfer <- function(){
  # tranfer learning update no nonpar transfer (main node)
  fit <- NULL
  lambda <- 10*10^(-seq(0,10, length.out=lambda_length))
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
    lambda <- sort(unique(lambda), decreasing = TRUE)

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
    lambda <- sort(unique(lambda), decreasing = TRUE)
    print("lambda before semitransfer_PAR")
    print(lambda)
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
  lambda <- sort(unique(lambda), decreasing = TRUE)
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
time_para_transfer <- difftime(end_time, start_time, units="secs")
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
  lambda <- 10*10^(-seq(0,10, length.out=lambda_length))
  for (k in 1:length(bandwidth_scale_seq)){
    for (index.test in 1:ntask){
      bandwidth_scale <- bandwidth_scale_seq[k]
      ## each site for nonpar transfer
      Y_given_X_transfer_each_site <- NULL
      fit_Y_given_X <- list()
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
        fit_Y_given_X[[fold]] <- SemiTransfer_NonPar(gradient, hessian, lambda=lambda)
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
        #lambda <- sort(unique(lambda), decreasing = TRUE)
        fit_Y_given_X[[fold]] <- SemiTransfer_NonPar(gradient, hessian)
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
  lambda <- 10*10^(-seq(0,10, length.out=lambda_length))
  for (index in 1:ntask){
    fit_each_site_nonpar_tranfer[[index]] <- PLM_Per_Site(X[[index]], D[[index]],
                                                          Y[[index]], split_index=split_index[[index]],
                                                          Y_given_X = Y_given_X_opt[[index]],
                                                          D_given_X = D_given_X_opt[[index]],
                                                          nonpar_transfer = TRUE)
  }
  
  # tranfer learning update with nonpar transfer (main node)
  fit_both <-  NULL
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
    #lambda <- sort(unique(lambda), decreasing = TRUE)
    print("lambda before semitransfer_PAR")
    lambda <- sort(unique(lambda))
    print(lambda)
    fit_both[[fold]] <- SemiTransfer_Par(gradient, hessian, initial_value, type = "PLM", lambda=lambda)
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
time_nonpar_transfer <- difftime(end_time, start_time, units="secs")
# compare mse



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
lambda_length = as.numeric(args[5])
cat("The dim is", dim, "\n")
cat(seed, n, similarity, dim)
cat("The dim is", dim, "\n")
run_simulation(seed, n, similarity, dim, lambda_length)


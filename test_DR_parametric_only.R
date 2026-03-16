setwd("TransferSemi/R")
files <- list.files(pattern = "\\.R$")
lapply(files, source)
# multi source partial linear model
library(glmnet)
simulation <- function(seed, n, similarity, dim){

  # multi source Dimension reduction
  ntask <- 5
  #n <- 200 # vary this from 200 to 500
  p <- dim
  #similarity <- 1 #vary this from 1, 0.8, 0.6, 0.4
  max.dim<-1
  set.seed(seed)

  effect_common <- seq(-0.5, 0.5, length.out = p)

  effect <- NULL
  for (index in 1:ntask){
    effect[[index]] <- effect_common+rnorm(1)*0.05+0.1*(1-similarity)*(index>4)
  }

  X <- Y <- NULL
  for (index in 1:ntask) {
    X[[index]] <- matrix(runif(n * p, min = -1, max=1), n, p)
    Y[[index]] <-X[[index]] %*% effect[[index]]+1*(X[[index]] %*% effect[[index]])^2 + 1*(X[[index]] %*% effect[[index]])^3+ rnorm(n)*0.5
  }

  # generate split_index
  split_index <- NULL
  for (index in 1:ntask){
    split_index[[index]] <- sample(1:2, n, replace = TRUE)
  }

  # Method without Nonpar Transfer
  # each site no nonpar transfer
  fit_each_site <- NULL
  for (index in 1:ntask){
    fit_each_site[[index]] <- DR_Per_Site(X[[index]], Y[[index]], split_index=split_index[[index]], dim=1)
  }
  ######################################
  ######################################
  ######################################
  auxi_coef <- list()
  beta_Sai <- list()
  for (index in 1:ntask){
    pseudo.X <- do.call(rbind, X[-index])
    pseudo.Y <-  do.call(rbind, Y[-index])
    lambda_seq <- 10^seq(1, -3, by = -0.01)
    lasso_fit <- cv.glmnet(pseudo.X, pseudo.Y, lambda = lambda_seq, alpha = 0, intercept = FALSE)
    best_lambda <- lasso_fit$lambda.min
    beta_aux <- coef(lasso_fit, s = best_lambda)[-1]
    #fit <- MAVE::mave(pseudo.Y~pseudo.X, method="csopg",max.dim=1)
    #beta_aux <- fit$dir[[1]]
    
    auxi_coef[[index]] <- beta_aux
    
    lasso_fit <- cv.glmnet(X[[index]], Y[[index]] - X[[index]] %*% beta_aux, lambda = lambda_seq,alpha = 1, intercept = FALSE)
    beta <- coef(lasso_fit, s = "lambda.min")[-1]
    beta_hat <- beta_aux + beta
    beta_Sai[[index]] <- beta_hat / (beta_hat[1])
  }
  ######################################
  ######################################
  ######################################


  # ----------------------------
  # ARMUL fit: Y ~ X (per task)
  # ----------------------------
  # IMPORTANT: use spline=FALSE here so coefficients live in original p-dim
  armul_fit <- vanilla_train(
    X_list = X,
    y_list = Y,              # <-- fit Y on X
    link = "linear",
    penalty = "new",
    spline = FALSE,          # critical for comparing to effect in original p
    T_global = 2000,
    T_local  = 1,
    eta_global = 0.01,
    eta_local  = 0.01,
    verbose = FALSE
  )

  # Extract per-task coefficients (p x 1) and normalize like you do elsewhere
  beta_ARMUL <- lapply(1:ntask, function(j) {
      b <- armul_fit$vanilla[j,,1]
      b <- as.numeric(b)
      b / b[1]          # normalize first coef to 1
    })
    # ----------------------------
  # pERM fit: Y ~ X (all tasks jointly)
  # ----------------------------
  perm_data <- lapply(1:ntask, function(t) {
    list(X = as.matrix(X[[t]]),
        y = as.numeric(Y[[t]]))
  })

  # choose nbasis:
  # - nbasis=1 (or NULL) => no spline expansion, beta dim = p
  # - nbasis>1 => spline expansion, beta dim = p*nbasis
  nbasis_perm <- 1

  fit_perm_YX <- pERM_torch(
    data = perm_data,
    r = 3,
    nbasis = nbasis_perm,
    lr = 1e-2,
    max_iter = 2000,
    C1 = 1, C2 = 1,
    info = FALSE,
    link = "linear"
  )

  beta_pERM_mat <- fit_perm_YX$step2   # (p*nbasis) x ntask

  # Normalize each task's beta so first coordinate is 1 (same style as you do)
  beta_pERM_mat <- apply(beta_pERM_mat, 2, function(b) b / b[1])
  colnames(beta_pERM_mat) <- paste0("task", 1:ntask)
  # Data Pooling method
  ##############################################################################################################################
  ##############################################################################################################################
  ##############################################################################################################################


  pooled_res <- list()
  pooled_X <- do.call(rbind, X)
  pooled_Y <- do.call(c, Y)
  split_index_p <- do.call(c, split_index)
  pooled_temp <- DR_Per_Site(pooled_X, pooled_Y, split_index=split_index_p, dim=max.dim)
  print("The pooled results are:")  
  print(pooled_res)
  ##############################################################################################################################
  ##############################################################################################################################
  ##############################################################################################################################
  # tranfer learning update no nonpar transfer (main node)
  Para_transfer <- function(){
    fit <- NULL
    lambda <- NULL
    for (dr.dim in 1:max.dim){
      fit[[dr.dim]] <- list()
      for (fold in 1:2){
        ## Gradient and Hessian
        gradient <- hessian <- NULL
        for (index in 1:ntask) {
          gradient[[index]] <- fit_each_site[[index]]$gradient[[fold]][[dr.dim]]
          hessian[[index]] <- fit_each_site[[index]]$hessian[[fold]][[dr.dim]]
        }

        ## Initial value
        initial_value <- list()
        for (index in 1:ntask) {
          initial_value[[index]] <- c(t(fit_each_site[[index]]$coef_estimate[[fold]][[dr.dim]][-(1:dr.dim),]))
        }
        fit[[dr.dim]][[fold]] <- SemiTransfer_Par(gradient, hessian, initial_value, type = "DR")
        lambda <- c(lambda, fit[[dr.dim]][[fold]]$fit$gglasso.fit$lambda)
      }
    }
    lambda <- sort(unique(lambda))
    for (dr.dim in 1:max.dim){
      fit[[dr.dim]] <- list()
      for (fold in 1:2){
        ## Gradient and Hessian
        gradient <- hessian <- NULL
        for (index in 1:ntask) {
          gradient[[index]] <- fit_each_site[[index]]$gradient[[fold]][[dr.dim]]
          hessian[[index]] <- fit_each_site[[index]]$hessian[[fold]][[dr.dim]]
        }

        ## Initial value
        initial_value <- list()
        for (index in 1:ntask) {
          initial_value[[index]] <- c(t(fit_each_site[[index]]$coef_estimate[[fold]][[dr.dim]][-(1:dr.dim),]))
        }
        fit[[dr.dim]][[fold]] <- SemiTransfer_Par(gradient, hessian, initial_value, type = "DR", lambda=lambda)
      }
    }
    ## tuning optimal lambda
    ### get coefficients
    coef_candidate <- list()
    for (index in 1:ntask){
      coef_candidate[[index]] <- list()
      for (dr.dim in 1:max.dim){
        coef_candidate[[index]][[dr.dim]] <- list()
        for (fold in 1:2){
          ncoef <- dr.dim*p-dr.dim*dr.dim
          coef_candidate[[index]][[dr.dim]][[fold]] <- fit[[dr.dim]][[fold]]$fit$gglasso.fit$beta[((index-1)*ncoef+1):(index*ncoef),]+
            fit[[dr.dim]][[fold]]$fit$gglasso.fit$beta[(ntask*ncoef+1):((ntask+1)*ncoef),]
        }
      }
    }
    ### cross-validation to tune on split dataset
    fit_tuned <- coef_est <- NULL
    error <- array(0, c(ntask, length(lambda)))
    for (index in 1:ntask){
      fit_tuned[[index]] <- DR_tune_Per_Site(coef_candidate[[index]], X[[index]],
                                             Y[[index]], split_index=split_index[[index]],
                                             max.dim = max.dim, nfold=2, lambda=lambda)
      error[index,] <- fit_tuned[[index]]$error
    }
    error.all.task <- apply(error,2,mean)
    for (index in 1:ntask){
      coef_est[[index]] <- (coef_candidate[[index]][[1]][[1]][,which.min(error.all.task)]+
                              coef_candidate[[index]][[1]][[2]][,which.min(error.all.task)])/2
    }
    list(tuned=coef_est, untuned=(fit[[1]][[1]]$coef+fit[[1]][[2]]$coef)/2)
  }
  coef_para <- Para_transfer()
  coef_est <- coef_para$tuned
  coef_est_untuned <- coef_para$untuned

  #initial value
  coef_est_no_transfer <- NULL
  for (index in 1:ntask) {
    coef_est_no_transfer <- cbind(coef_est_no_transfer, 0.5*(fit_each_site[[index]]$coef_estimate[[1]][[1]]+fit_each_site[[index]]$coef_estimate[[2]][[1]]))
  }
  print(coef_est_no_transfer)

  # compare mse
  effect.cbind <-apply(sapply(effect, c), 2, function(t){t/t[1]})
  mse_par_transfer_tuned <- array(0, c(ntask, 1))
  mse_transfer_Sai <- array(0, c(ntask, 1))
  for (index in 1:ntask){
    if (NCOL(coef_est[[index]])==1){
      mse_par_transfer_tuned[index] <- sum((coef_est[[index]]-effect.cbind[-1,index])^2)
    } else {
      mse_par_transfer_tuned[index] <- NA
    }
    
  }
  for (index in 1:ntask) {
    mse_transfer_Sai[index] <- (beta_Sai[[index]][-1] - effect.cbind[-1,index])^2 |> sum()
    
  }
  print(mse_par_transfer_tuned)
  mse_par_transfer <- apply((coef_est_untuned-effect.cbind[-1,])^2,2,sum)
  print(mse_par_transfer)
  mse_standard <- apply((coef_est_no_transfer-effect.cbind)^2,2,sum)
  print(mse_standard)
  # beta_ARMUL: list of length ntask, each is length p numeric vector
  beta_ARMUL_mat <- do.call(cbind, beta_ARMUL)  # p x ntask
  storage.mode(beta_ARMUL_mat) <- "double"
  colnames(beta_ARMUL_mat) <- paste0("task", 1:ntask)
  # effect.cbind should be p x ntask
  effect.cbind <- apply(sapply(effect, c), 2, function(t) t / t[1])

  mse_ARMUL <- colSums((beta_ARMUL_mat - effect.cbind)^2)
  print(mse_ARMUL)


  effect.cbind <- apply(sapply(effect, c), 2, function(t) t / t[1])  # p x ntask

  mse_pERM <- sapply(1:ntask, function(j) {
    sum((beta_pERM_mat[, j] - effect.cbind[, j])^2)
  })
  print(mse_pERM)

  coef_est_pool <- NULL
  for (index in 1:ntask) {
    coef_est_pool<- cbind(coef_est_pool, 0.5*(pooled_temp$coef_estimate[[1]][[1]]+pooled_temp$coef_estimate[[2]][[1]]))
  }
  print(coef_est_pool)


  pool_mse <- apply((coef_est_pool-effect.cbind)^2,2,sum)


  res <- rbind("Para_Transfer"=c(mse_par_transfer),"Para_Transfer_Tuned"=c(mse_par_transfer_tuned),
               "Baseline"=c(mse_standard), "Sai_Transfer"=c(mse_transfer_Sai), "Pooled"=c(pool_mse), "ARMUL"=mse_ARMUL, "pERM"=mse_pERM)
  colnames(res) <- c("Task1", "Task2", "Task3", "Task4", "Task5")
  res <- cbind(res, seed=seed)
  res
dictionary_mse = paste0("DR_9_new/mse_n_",n,"_simi_",similarity)
if (!file.exists(dictionary_mse)) {
  dir.create(dictionary_mse, recursive = TRUE)
}

save(
  res,
  file = paste0(
    dictionary_mse,"/",
    seed,
    ".RData"
  )
)
print(res)
}

args <- commandArgs(trailingOnly = TRUE)
n <- as.numeric(args[1])         # First argument passed
similarity <- as.numeric(args[2]) # Second argument passed
seed <- as.numeric(args[3])
dim <- as.numeric(args[4])
cat(seed, n, similarity, dim)

simulation(seed, n, similarity, dim)






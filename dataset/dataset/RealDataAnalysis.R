

set.seed(1)





convert_age_one_hot <- function(combined){
  age_quantiles <- quantile(combined$age, probs = seq(0, 1, 0.25), na.rm = TRUE)
  combined$age_quantile <- cut(
    combined$age,
    breaks = age_quantiles,
    include.lowest = TRUE,
    labels = c("Q1", "Q2", "Q3", "Q4")
  )
  age_one_hot <- model.matrix(~ age_quantile - 1, data = combined)
  combined_one_hot <- cbind(combined[, !colnames(combined) %in% c("age", "age_quantile")], age_one_hot)
  combined_one_hot
}
plot_evaluation <- function(eval_input){
  mse_values <- sapply(eval_input, function(x) sapply(x$mse, function(y) y[[1]])) |> colMeans()
  value_function_values <- sapply(eval_input, function(x) sapply(x$value_function, function(y) y[[1]])) |> colMeans()
  
  # Prepare data for visualization
  library(ggplot2)
  library(reshape2)
  df <- data.frame(
    Index = rep(1:length(mse_values), times = 2),
    Type = c(rep(c("MSE"), times = length(mse_values)), rep(c("Value Function"), times = length(mse_values))),
    Value = c((mse_values),(value_function_values))
  )
  
  df_mse <- df[df$Type == "MSE", ]
  df_value_function <- df[df$Type == "Value Function", ]
  scale_factor <- max(df_value_function$Value) / max(df_mse$Value)
  ggplot() +
    geom_line(data = df_mse, aes(x = Index, y = Value, color = "MSE"), size = 1) +
    geom_point(data = df_mse, aes(x = Index, y = Value, color = "MSE"), size = 3) +
    geom_line(data = df_value_function, aes(x = Index, y = Value / scale_factor, color = "Value Function"), size = 1, linetype = "dashed") +
    geom_point(data = df_value_function, aes(x = Index, y = Value / scale_factor, color = "Value Function"), size = 3, shape = 16) +
    scale_y_continuous(
      name = "MSE",
      sec.axis = sec_axis(~ . * scale_factor, name = "Value Function")
    ) +
    scale_color_manual(
      values = c("MSE" = "blue", "Value Function" = "green"),
      name = "Type"
    ) +
    labs(
      title = "MSE and Value Function",
      x = "Index"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(hjust = 0.5),
      axis.title.y.left = element_text(color = "blue"),
      axis.title.y.right = element_text(color = "green"),
      legend.position = "top"
    )
}

format_result <- function(nested_list){
  result <- do.call(rbind, lapply(nested_list, function(item) {
    mse_values <- unlist(item$mse)
    value_function_values <- unlist(item$value_function)
    data.frame(
      mse_1 = mse_values[1],
      mse_2 = mse_values[2],
      value_function_1 = value_function_values[1],
      value_function_2 = value_function_values[2]
    )
  }))
  result
}

split_data <- function(data, train_ratio = 1.0) {
  train_indices <- seq_len(nrow(data))
  train_data <- data[train_indices, ]
  test_data <- train_data
  list(train = train_data, test = test_data)
}
split_into_tasks <- function(data, n_tasks = 5) {
  task_indices <- sample(rep(1:n_tasks, length.out = nrow(data)))
  tasks <- lapply(1:n_tasks, function(t) data[task_indices == t, ])
  tasks
}





cape <- read.csv("/Users/cyz/workspace/Liang/dataset/cape.csv")
ninr <- read.csv("/Users/cyz/workspace/Liang/dataset/ninr.csv")
cape_copy <- cape[, colnames(cape)[-c(4, 5, 6, 7, 10, 11)]]
ninr_copy <- ninr[, colnames(cape)[-c(4, 5, 6, 7, 10, 11)]]
cape_train_test <- split_data(cape_copy)
cape_train <- split_into_tasks(cape_train_test$train, 2)
cape_test <- cape_train

ninr_train_test <- split_data(ninr_copy)
ninr_train <- split_into_tasks(ninr_train_test$train, 2)
ninr_test <- ninr_train
combined <- rbind(cape_copy, ninr_copy)
combined <- na.omit(combined)






X = list()
D <- list()
task <- list()
Y <- list()
X_test = list()
D_test = list()
Y_test = list()

check_variability <- function(data) {
  sapply(data, function(column) length(unique(column)) > 1)
}
n_tasks=4
for (index in 1:2){
  cape_train[[index]] <- cape_train[[index]][apply(cape_train[[index]], 1, function(row) all(!is.na(row))), ]
  
  X_age <- convert_age_one_hot(cape_train[[index]][, c(5:19)]) 
  # X_age is after converted by age one hot
  X_age$yearmamsum <- as.factor(X_age$yearmamsum)
  
  yearmamsum_one_hot <- model.matrix(~ yearmamsum-1, data = X_age)
  X[[index]] <- cbind(X_age[, !colnames(X_age) %in% c("yearmamsum")], yearmamsum_one_hot)
  
  D[[index]] <- cape_train[[index]][, 3]
  Y[[index]] <- cape_train[[index]][, 4]
}

for (index in 3:4){
  ninr_train[[index-2]] <- ninr_train[[index-2]][apply(ninr_train[[index-2]], 1, function(row) all(!is.na(row))), ]
  
  X_age <- convert_age_one_hot(ninr_train[[index-2]][, c(5:19)]) 
  # X_age is after converted by age one hot
  X_age$yearmamsum <- as.factor(X_age$yearmamsum)
  
  yearmamsum_one_hot <- model.matrix(~ yearmamsum-1, data = X_age)
  X[[index]] <- cbind(X_age[, !colnames(X_age) %in% c("yearmamsum")], yearmamsum_one_hot)
  
  D[[index]] <- as.numeric(ninr_train[[index-2]][, 3])
  Y[[index]] <- as.numeric(ninr_train[[index-2]][, 4])
}
for(index in 1:4){
  #X[[index]] = X[[index]][ , !(colnames(X[[index]]) %in% c("racecauc"))]
  X[[index]] <- as.matrix( X[[index]])
}

for (index in 1:2){
  cape_test[[index]] <- cape_test[[index]][apply(cape_test[[index]], 1, function(row) all(!is.na(row))), ]
  
  X_age <- convert_age_one_hot(cape_test[[index]][, c(5:19)]) 
  # X_age is after converted by age one hot
  X_age$yearmamsum <- as.factor(X_age$yearmamsum)
  
  yearmamsum_one_hot <- model.matrix(~ yearmamsum-1, data = X_age)
  X_test[[index]] <- cbind(X_age[, !colnames(X_age) %in% c("yearmamsum")], yearmamsum_one_hot)
  
  D_test[[index]] <- cape_test[[index]][, 3]
  Y_test[[index]] <- cape_test[[index]][, 4]
}

for (index in 3:4){
  ninr_test[[index-2]] <- ninr_test[[index-2]][apply(ninr_test[[index-2]], 1, function(row) all(!is.na(row))), ]
  
  X_age <- convert_age_one_hot(ninr_test[[index-2]][, c(5:19)]) 
  # X_age is after converted by age one hot
  X_age$yearmamsum <- as.factor(X_age$yearmamsum)
  
  yearmamsum_one_hot <- model.matrix(~ yearmamsum-1, data = X_age)
  X_test[[index]] <- cbind(X_age[, !colnames(X_age) %in% c("yearmamsum")], yearmamsum_one_hot)
  
  D_test[[index]] <- as.numeric(ninr_test[[index-2]][, 3])
  Y_test[[index]] <- as.numeric(ninr_test[[index-2]][, 4])
}
for(index in 1:4){
  #X_test[[index]] = X_test[[index]][ , !(colnames(X_test[[index]]) %in% c("racecauc"))]
  
  X_test[[index]] <- as.matrix(X_test[[index]])
  # Delete raceauc
  
}



original_wd <- getwd()
setwd("/Users/cyz/workspace/Liang/TransferSemi_5/TransferSemi/R")
files <- list.files(pattern = "\\.R$")
a=lapply(files, source)
setwd(original_wd)
ntask <- 4
split_index <- list()
fit_each_site <- list()
# Min-max normalization function
normalize_min_max <- function(x) {
  (x - min(x)) / (max(x) - min(x))
}

# Apply the function to the matrix X[[index]]
continuous_variables <- c("bar1tot", "ben1tot", "se1tot", "sus1tot", "fear1tot", "fatal1tot", "know1tot")
for (index in 1:ntask) {
  n <- dim(X[[index]])[1]
  split_index[[index]] <- sample(1:2, n, replace = TRUE)
  X_test[[index]][, continuous_variables] <- apply(X_test[[index]][, continuous_variables], 2, normalize_min_max)
}
for (index in 1:ntask) {
  
  
  X[[index]][, continuous_variables] <- apply(X[[index]][, continuous_variables], 2, normalize_min_max)
  X[[index]][, continuous_variables] <- apply(X[[index]][, continuous_variables], 2, normalize_min_max)
  fit_each_site[[index]] <- CATE_Per_Site(X[[index]], D[[index]], 
                                          Y[[index]], split_index=split_index[[index]], dim = 1)
}

max.dim <- 1
p <- dim(X[[1]])[2]
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
        coef_candidate[[index]][[dr.dim]][[fold]] <- fit[[dr.dim]][[fold]]$fit$gglasso.fit$beta[((index - 1) * ncoef + 1):(index * ncoef), ] +
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
                            coef_candidate[[index]][[1]][[2]][, which.min(error.all.task)]) / 2
  }
  list(tuned = coef_est,
       untuned = (fit[[1]][[1]]$coef + fit[[1]][[2]]$coef) / 2)
}
coef_para <- Para_transfer()
coef_est <- coef_para$tuned
coef_est_untuned <- coef_para$untuned

source("/Users/cyz/workspace/Liang/dataset/prediction_per_site.R")
eval_para_transfer_tuned <- list()
split_index_test <- list()
for (index in 1:ntask) {
  n <- dim(X_test[[index]])[1]
  split_index_test[[index]] <- sample(1:2, n, replace = TRUE)
}
for (index in 1:ntask){
  eval_para_transfer_tuned[[index]] <- CATE_predict(X_test[[index]], D_test[[index]], Y_test[[index]],
                                                    c(1, coef_est[[index]]) |> matrix(),nonpar_transfer = FALSE,
                                                    number_split=2, split_index = split_index_test[[index]], dim=1)
}
eval_para_transfer_tuned
saveRDS(eval_para_transfer_tuned, file="/Users/cyz/workspace/Liang/dataset/para_transfer_tuned.RData")


eval_para_transfer_untuned <- list()
for (index in 1:ntask){
  eval_para_transfer_untuned[[index]] <- CATE_predict(X_test[[index]], D_test[[index]], Y_test[[index]],
                                                      c(1, coef_est_untuned[, index]) |> matrix(),nonpar_transfer = FALSE,
                                                      number_split=2, split_index = split_index_test[[index]], dim=1)
}
eval_para_transfer_untuned
saveRDS(eval_para_transfer_untuned, file="/Users/cyz/workspace/Liang/dataset/para_transfer_untuned.RData")


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

eval_no_transfer <- list()

for (index in 1:ntask){
  eval_no_transfer[[index]] <- CATE_predict(X_test[[index]], D_test[[index]], Y_test[[index]], coef_est_no_transfer[, index], split_index=NULL, number_split=2,nonpar_transfer=FALSE, propensity_score=NULL, mu0=NULL, mu1=NULL, dim=1)
}
eval_no_transfer
saveRDS(eval_para_transfer_untuned, file="/Users/cyz/workspace/Liang/dataset/no_transfer.RData")


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
                                                                   grid = grid[[index.test]][[fold]],
                                                                   bandwidth_scale=bandwidth_scale, method="np")
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

for (index in 1:ntask) {
  Y1[[index]] <- Y_test[[index]][D_test[[index]]==1]
  Y0[[index]] <- Y_test[[index]][D_test[[index]]==0]
  X1[[index]] <- X_test[[index]][D_test[[index]]==1,]
  X0[[index]] <- X_test[[index]][D_test[[index]]==0,]
  split_index1[[index]] <- split_index_test[[index]][D_test[[index]]==1]
  split_index0[[index]] <- split_index_test[[index]][D_test[[index]]==0]
}
mu1_opt_test <- transfer_Y_given_X(Y=Y1, X=X1, split_index = split_index1, split_index.test = split_index_test, X.test=X_test)
mu0_opt_test <- transfer_Y_given_X(Y=Y0, X=X0, split_index = split_index0, split_index.test = split_index_test, X.test=X_test)
D_given_X_opt_test <- transfer_Y_given_X(Y=D, X=X, split_index = split_index, split_index.test = split_index_test, X.test=X_test)



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


eval_semipara_transfer_untuned <- list()
for (index in 1:ntask){
  eval_semipara_transfer_untuned[[index]] <- CATE_predict(X_test[[index]], D_test[[index]], Y_test[[index]],
                                                          c(1, coef_est_both_untuned[,index]) |> matrix(),nonpar_transfer = TRUE,
                                                          number_split=2, propensity_score= D_given_X_opt_test[[index]], 
                                                          mu0 = mu0_opt_test[[index]], mu1 = mu1_opt_test[[index]],split_index = split_index_test[[index]], dim=1)
}

eval_semipara_transfer_tuned <- list()
for (index in 1:ntask){
  eval_semipara_transfer_tuned[[index]] <- CATE_predict(X_test[[index]], D_test[[index]], Y_test[[index]],
                                                        c(1, coef_est_both[[index]]) |> matrix(),nonpar_transfer = TRUE,
                                                        number_split=2, propensity_score= D_given_X_opt_test[[index]], 
                                                        mu0 = mu0_opt_test[[index]], mu1 = mu1_opt_test[[index]],split_index = split_index_test[[index]], dim=1)
}

eval_semipara_transfer_untuned
plot_evaluation(eval_semipara_transfer_untuned)

eval_semipara_transfer_tuned
plot_evaluation(eval_semipara_transfer_tuned)
format_result(eval_semipara_transfer_untuned)
format_result(eval_semipara_transfer_tuned)

res <- list(
  eval_para_transfer_tuned = eval_para_transfer_tuned,
  eval_para_transfer_untuned = eval_para_transfer_untuned,
  eval_no_transfer = eval_no_transfer,
  eval_semipara_transfer_untuned = eval_semipara_transfer_untuned,
  eval_semipara_transfer_tuned = eval_semipara_transfer_tuned
)
format_list_to_df <- function(eval_list) {
  # Initialize an empty data frame
  result_df <- data.frame(
    Model = character(),
    Subgroup = integer(),
    MSE = numeric(),
    Value_Function = numeric(),
    stringsAsFactors = FALSE
  )
  
  # Iterate over the main list
  for (model_name in names(eval_list)) {
    # Iterate over each subgroup in the current model
    for (i in seq_along(eval_list[[model_name]])) {
      mse_list <- eval_list[[model_name]][[i]]$mse
      value_list <- eval_list[[model_name]][[i]]$value_function
      
      # Iterate over mse and value_function pairs
      for (j in seq_along(mse_list)) {
        mse_value <- mse_list[[j]][[1]]
        value_function_value <- value_list[[j]][[1]]
        
        # Add a row to the result data frame
        result_df <- rbind(result_df, data.frame(
          Model = model_name,
          Subgroup = i,
          MSE = mse_value,
          Value_Function = value_function_value
        ))
      }
    }
  }
  
  return(result_df)
}

res <- format_list_to_df(res)
mean_mse_by_model <- aggregate(Value_Function ~ Model, data = res, FUN = mean)
mean_mse_by_model                                                                                                                                       



# Initialize an empty list to store data frames
all_dfs <- list()

model <- "para_transfer_tuned" 
for (index in 1:4) {
  file_name <- paste0("eval_", model, "_w_race.Rdata")
  a <- readRDS(paste0("/Users/cyz/workspace/Liang/dataset/", file_name))
  target <- a[[index]]$f_hat
  continuous_vars <- c("bar1tot", "ben1tot", "se1tot", "sus1tot", "fear1tot", "fatal1tot", "know1tot")
  selected_columns <- X_test[[index]][, continuous_vars, drop = FALSE]
  
  correlations <- sapply(1:ncol(selected_columns), function(i) cor(selected_columns[, i], target, method = "pearson"))
  names(correlations) <- continuous_vars
  
  n_task <- index
  
  
  # Create a data frame
  final_df <- data.frame(
    Variable = names(correlations),
    Correlation = correlations,
    n_task = n_task,
    model = model,
    stringsAsFactors = FALSE # Ensures string variables remain as character type
  )
  
  # Append the data frame to the list
  all_dfs[[index]] <- final_df
}

# Combine all data frames into one
combined_df <- do.call(rbind, all_dfs)

# Print the combined data frame
print(combined_df)

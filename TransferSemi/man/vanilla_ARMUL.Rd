\name{vanilla_train}
\alias{vanilla_train}
\alias{vanilla_predict}
\title{Fit and Predict with the Vanilla ARMUL Estimator}
\usage{
vanilla_train(
  X_list,
  y_list,
  link = "linear",
  penalty = "new",
  lbd = NULL,
  eta_global = 0.01,
  eta_local = 0.01,
  T_global = 100,
  T_local = 1,
  df = 10,
  spline = TRUE,
  boundary_expand = 0.40,
  clamp = FALSE,
  print_every = 100,
  verbose = TRUE
)

vanilla_predict(models, X_test_list, task_id, link = "linear")
}
\arguments{
  \item{X_list}{A list of task-specific design matrices.}
  \item{y_list}{A list of task-specific response vectors or matrices.}
  \item{link}{The response link, either \code{"linear"} or
  \code{"logistic"}.}
  \item{penalty}{The local penalty implementation.}
  \item{lbd}{A vector of task-specific penalty values, or \code{NULL} to use
  the estimator default.}
  \item{eta_global, eta_local}{Step sizes for the global and local updates.}
  \item{T_global, T_local}{Numbers of global and local update iterations.}
  \item{df}{Degrees of freedom for each spline basis.}
  \item{spline}{Whether to expand each covariate with a spline basis.}
  \item{boundary_expand}{Fraction by which to expand spline boundaries.}
  \item{clamp}{Whether to clamp new covariate values to the spline
  boundaries.}
  \item{print_every}{Iteration interval for progress messages.}
  \item{verbose}{Whether to print progress messages.}
  \item{models}{An object returned by \code{vanilla_train()}.}
  \item{X_test_list}{A list of task-specific test design matrices.}
  \item{task_id}{The task to predict.}
}
\value{
\code{vanilla_train()} returns a list containing task coefficients, the
shared coefficient, and the fitted spline transformations.
\code{vanilla_predict()} returns predictions for the requested task.
}
\description{
Fits the vanilla ARMUL estimator across a list of tasks and applies a fitted
task model to new observations.
}

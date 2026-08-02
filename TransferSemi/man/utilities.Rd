\name{ks}
\alias{ks}
\alias{get_grid_from_each_site}
\alias{get_prediction_nonpar}
\alias{convert}
\title{Utilities for Transfer-Learning Workflows}
\usage{
ks(xx, yy, xx.test, bandwidth_scale = 1)

get_grid_from_each_site(
  X, total_sample_size, var = 1, method = c("noise", "grid")
)

get_prediction_nonpar(fit_Y_given_X, X, grid, task)

convert(coef, dim = 1)
}
\arguments{
  \item{xx}{A training covariate matrix.}
  \item{yy}{A training response vector.}
  \item{xx.test}{Covariate values at which to evaluate the kernel smoother.}
  \item{bandwidth_scale}{A multiplicative kernel-bandwidth factor.}
  \item{X}{A covariate matrix.}
  \item{total_sample_size}{The total sample size used to scale grid noise.}
  \item{var}{The grid-noise scale.}
  \item{method}{The grid construction method.}
  \item{fit_Y_given_X}{A fitted nonparametric transfer object containing
  predictions.}
  \item{grid}{The prediction grid associated with the fitted object.}
  \item{task}{The task index to predict.}
  \item{coef}{A matrix of vectorized task coefficients.}
  \item{dim}{The sufficient dimension used to reshape coefficients.}
}
\value{
\code{ks()} returns kernel-smoothed predictions.
\code{get_grid_from_each_site()} returns an evaluation grid.
\code{get_prediction_nonpar()} maps observations to predictions at their
nearest grid points. \code{convert()} returns task coefficients reshaped as
matrices.
}
\description{
Provides kernel smoothing, evaluation-grid, nearest-grid prediction, and
coefficient-formatting helpers used by the repository workflows.
}

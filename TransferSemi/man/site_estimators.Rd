\name{CATE_Per_Site}
\alias{CATE_Per_Site}
\alias{CATE_tune_Per_Site}
\alias{DR_Per_Site}
\alias{DR_tune_Per_Site}
\alias{Nonpar_Gradient_Per_Site}
\alias{Nonpar_Per_Site}
\alias{PLM_Per_Site}
\alias{PLM_tune_Per_Site}
\title{Fit and Tune Site-Level Estimators}
\usage{
CATE_Per_Site(
  X, D, Y, split_index = NULL, number_split = 2,
  nonpar_transfer = FALSE, propensity_score = NULL, mu0 = NULL,
  mu1 = NULL, dim = 1, real_data = FALSE
)

CATE_tune_Per_Site(
  coef_candidate, X, D, Y, split_index, max.dim, nfold, lambda
)

DR_Per_Site(
  X, Y, split_index = NULL, number_split = 2,
  nonpar_transfer = FALSE, f.value = NULL, EX = NULL, dim = 1
)

DR_tune_Per_Site(
  coef_candidate, X, Y, split_index, max.dim, nfold, lambda
)

Nonpar_Gradient_Per_Site(
  X, Y, Y_given_X, split_index = NULL, number_split = 2,
  grid, bandwidth_scale = 1, method = "ks"
)

Nonpar_Per_Site(
  X, Y, split_index = NULL, number_split = 2,
  grid, bandwidth_scale = 1, method = "ks"
)

PLM_Per_Site(
  X, D, Y, split_index = NULL, number_split = 2,
  nonpar_transfer = FALSE, D_given_X = NULL, Y_given_X = NULL
)

PLM_tune_Per_Site(
  coef_candidate, X, D, Y, Y_given_X = NULL, D_given_X = NULL,
  split_index, nfold, lambda, nonpar_transfer = FALSE
)
}
\arguments{
  \item{X}{A site-specific covariate matrix.}
  \item{D}{A site-specific treatment or exposure vector.}
  \item{Y}{A site-specific response vector.}
  \item{split_index}{Fold labels for sample splitting. If \code{NULL}, the
  estimator generates labels using R's current random-number state.}
  \item{number_split}{The number of sample-splitting folds.}
  \item{nonpar_transfer}{Whether externally estimated nonparametric nuisance
  quantities are supplied.}
  \item{propensity_score}{Estimated treatment propensity scores.}
  \item{mu0, mu1}{Estimated conditional outcomes under the two treatment
  levels.}
  \item{dim}{The requested sufficient dimension.}
  \item{real_data}{Whether to use the data-specific preprocessing branch.}
  \item{coef_candidate}{Candidate coefficient paths indexed by dimension and
  fold as required by the corresponding tuning routine.}
  \item{max.dim}{The largest sufficient dimension to evaluate.}
  \item{nfold}{The number of tuning folds.}
  \item{lambda}{The candidate regularization path.}
  \item{f.value}{Externally estimated regression-function values.}
  \item{EX}{Externally estimated conditional covariate means.}
  \item{Y_given_X, D_given_X}{Estimated conditional response and exposure
  means.}
  \item{grid}{Evaluation points for a nonparametric estimator.}
  \item{bandwidth_scale}{A multiplicative kernel-bandwidth factor.}
  \item{method}{The nonparametric estimation method.}
}
\value{
The site fitting functions return lists of the fitted gradients, Hessians,
coefficients, folds, and relevant nuisance estimates. The tuning functions
return selected path indices and aggregated validation errors.
}
\description{
Fits the site-level components used by the conditional average treatment
effect, sufficient dimension reduction, nonparametric, and partially linear
transfer-learning workflows. Companion functions select tuning paths by
held-out error.
}

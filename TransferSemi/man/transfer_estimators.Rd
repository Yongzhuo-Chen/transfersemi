\name{SemiTransfer_Par}
\alias{SemiTransfer_Par}
\alias{SemiTransfer_NonPar}
\title{Combine Site-Level Estimates Across Tasks}
\usage{
SemiTransfer_Par(
  gradient, hessian, initial_value,
  type = c("DR", "PLM", "ATE"), lambda = NULL
)

SemiTransfer_NonPar(
  gradient, hessian, lambda = NULL, gradient.fit = TRUE
)
}
\arguments{
  \item{gradient}{Site-level gradient estimates. For the nonparametric
  estimator, rows correspond to evaluation points and columns to tasks.}
  \item{hessian}{Site-level Hessian estimates in the layout expected by the
  selected estimator.}
  \item{initial_value}{A list of task-specific initial coefficient values.}
  \item{type}{The semiparametric model label.}
  \item{lambda}{An optional regularization path passed to \pkg{gglasso}.}
  \item{gradient.fit}{A compatibility argument for the nonparametric
  estimator.}
}
\value{
\code{SemiTransfer_Par()} returns the fitted cross-validated group-lasso
object, its regularization path, and task coefficients.
\code{SemiTransfer_NonPar()} returns the fitted group-lasso object, its path,
and task predictions at the supplied evaluation points.
}
\description{
Constructs the quadratic pseudo-regression problems used to combine
site-level parametric or nonparametric estimates and fits their grouped
regularization paths.
}

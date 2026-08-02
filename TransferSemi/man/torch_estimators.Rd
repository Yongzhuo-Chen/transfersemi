\name{pERM_torch}
\alias{pERM_torch}
\alias{compute_val_loss}
\alias{fit_sources}
\alias{fit_target_ols}
\alias{process_for_rtl}
\title{Fit Torch-Based Transfer-Learning Estimators}
\usage{
pERM_torch(
  data, r = 3, nbasis = 5, lr = 1e-2, max_iter = 200,
  C1 = 0.001, C2 = 0.001, info = FALSE, tol = 1e-3,
  link = c("linear", "logistic"), X_test = NULL, X_test_list = NULL,
  seed = NULL, device = NULL
)

compute_val_loss(y_true, y_pred, link = "linear")

fit_sources(
  X_list, Z_list, y_list, hidden = c(5, 5), p = 2,
  lr = 1e-3, weight_decay = 0, epochs = 1000, verbose = TRUE,
  device = NULL, test_frac = 0.2, seed = 1, patience = 30,
  min_delta = 0, restore_best = TRUE
)

fit_target_ols(
  fitted_sources, X0, Z0, y0, ridge = 0, add_intercept = FALSE
)

process_for_rtl(X, D, Y, effect, target_indx = 1, method = "CATE")
}
\arguments{
  \item{data}{A list of tasks, each containing a design matrix \code{X} and
  response \code{y}.}
  \item{r}{The representation rank.}
  \item{nbasis}{The number of spline basis functions per covariate.}
  \item{lr}{The optimizer learning rate.}
  \item{max_iter}{The maximum number of pERM iterations per stage.}
  \item{C1, C2}{Penalty-scale constants for the two pERM stages.}
  \item{info}{Whether to print pERM progress messages.}
  \item{tol}{The relative convergence tolerance.}
  \item{link}{The response link.}
  \item{X_test}{One test matrix to evaluate with every task model.}
  \item{X_test_list}{A list of task-specific test matrices.}
  \item{seed}{A random seed. When non-\code{NULL}, both R and torch are
  seeded before random initialization.}
  \item{device}{A torch device. \code{NULL} selects the CPU; pass an explicit
  device to opt into another backend.}
  \item{y_true, y_pred}{Observed responses and corresponding predictions.}
  \item{X_list, Z_list, y_list}{Lists of source-domain exposure matrices,
  covariate matrices, and response matrices.}
  \item{hidden}{Widths of the representation network's hidden layers.}
  \item{p}{The representation dimension.}
  \item{weight_decay}{Optimizer weight decay.}
  \item{epochs}{The maximum number of source-training epochs.}
  \item{verbose}{Whether to print source-training progress.}
  \item{test_frac}{The within-source holdout fraction used for early
  stopping.}
  \item{patience}{The number of non-improving epochs allowed.}
  \item{min_delta}{The minimum holdout-loss improvement.}
  \item{restore_best}{Whether to restore parameters from the best epoch.}
  \item{fitted_sources}{An object returned by \code{fit_sources()}.}
  \item{X0, Z0, y0}{Target-domain exposure matrix, covariate matrix, and
  response.}
  \item{ridge}{The target regression's ridge penalty.}
  \item{add_intercept}{Whether to add an unpenalized intercept.}
  \item{X, D, Y}{Lists of covariates, exposures, and responses by task.}
  \item{effect}{A list of task-specific reference effects retained in the
  prepared output.}
  \item{target_indx}{The target task index.}
  \item{method}{The data layout, with \code{"CATE"} using covariates as the
  exposure block.}
}
\value{
\code{pERM_torch()} returns fitted coefficient matrices and training
predictions, plus test predictions when requested. \code{fit_sources()}
returns the fitted representation model and split metadata.
\code{fit_target_ols()} returns target coefficients, standard errors, and
regression diagnostics. \code{process_for_rtl()} returns source and target
inputs in the layout required by these routines. \code{compute_val_loss()}
returns a scalar validation loss.
}
\description{
Fits the torch-based pERM and representation-transfer estimators. Explicit
seeds initialize both R and torch, and CPU execution is the default for
portable reproducibility.
}

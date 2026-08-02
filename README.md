# TransferSemi reproducibility guide

This repository contains the R implementation, simulation entry points,
pseudo-data analysis, precomputed artifacts, and figure notebooks for
TransferSemi. Run all commands below from the repository root. The scripts now
resolve the root independently, but a fixed launch location makes logs and
verification easier to compare.

## 1. Software requirements

- R 4.1 or newer. The code uses the native R pipe (`|>`).
- A Unix-like shell for the provided submission scripts.
- Slurm and an environment-modules installation only for cluster submission.
  Local `Rscript` commands do not require Slurm.
- Package dependencies: `gglasso`, `glmnet`, `MAVE`, `Matrix`, `np`, `pracma`,
  `splines`, `stats`, and `torch`.
- Workflow and notebook dependencies: `cowplot`, `data.table`, `dplyr`,
  `forcats`, `ggplot2`, `gridExtra`, `knitr`, `Hmisc`, `patchwork`,
  `reshape2`, `rmarkdown`, `scales`, `stringr`, `tibble`, and `tidyr`.
- Pandoc for rendering the R Markdown notebooks. Check it with
  `Rscript -e 'stopifnot(rmarkdown::pandoc_available())'`.
- A compiler and the platform-specific development tools required if R must
  build any dependency from source. `TransferSemi` itself contains no compiled
  code; its non-R runtime requirement is the LibTorch/LibLantern installation
  managed by the `torch` package.

Restore the exact R package versions recorded in `renv.lock`:

```bash
Rscript -e 'if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv")'
Rscript -e 'renv::restore()'
Rscript -e 'stopifnot(torch::torch_is_installed()); print(torch::torch_device("cpu"))'
```

The lockfile was generated and tested with R 4.3.3, R package `torch` 0.16.3,
CPU LibTorch 2.7.1, and LibLantern 0.1.0.9004. The neural estimators require
that backend combination; `renv` restores the R package but does not itself
guarantee that the external LibTorch/LibLantern binaries are present. If
`torch::torch_is_installed()` is false after `renv::restore()`, install the
backend with `torch::install_torch()` and rerun the check above. Consult the
official
[R torch installation guide](https://torch.mlverse.org/docs/articles/installation/)
when a site requires a different installation method.

The committed `renv.lock` records package versions from the working cluster
environment used for the reproducibility checks. To update it after an
intentional dependency change, run `renv::snapshot()` from the repository
root and review the lockfile diff before committing it.

## 2. Build, check, and install the R package

With the dependencies installed:

```bash
R CMD build TransferSemi
R CMD check --no-manual TransferSemi_0.1.0.tar.gz
R CMD INSTALL TransferSemi_0.1.0.tar.gz
```

The simulations source the package implementation directly from
`TransferSemi/R`, while the build/check commands validate the distributable
package metadata and namespace.

## 3. Local one-seed smoke runs

Simulation output defaults to `semi-transfer-learning/`. To keep verification
separate from tracked artifacts, set `TRANSFERSEMI_OUTPUT_ROOT`; a relative
value is resolved beneath the repository root and directories are created
automatically.

```bash
export TRANSFERSEMI_OUTPUT_ROOT=outputs/smoke
Rscript simulation/test_CATE.R 100 0 1 8
Rscript simulation/test_DR_parametric_only.R 100 0 1 8
Rscript simulation/test_PLM.R 100 0 1 8 100
Rscript simulation/PLM_fintune.R 200 0 1 8
```

These are computational analyses, not short unit tests. No runtime estimate is
claimed here.

The historical/development entry points remain available:

```bash
export TRANSFERSEMI_OUTPUT_ROOT=outputs/smoke-legacy
Rscript simulation/test_PLM_before.R 100 0 1 8
Rscript simulation/PLM_time.R 100 0 1 8 100
```

For one pseudo-data replicate without overwriting tracked results:

```bash
TRANSFERSEMI_REAL_OUTPUT_DIR=outputs/smoke/real \
  Rscript real_data/RealDataAnalysis.R 1
TRANSFERSEMI_CORR_OUTPUT_DIR=outputs/smoke/corr \
  Rscript real_data/correlations.R
```

The correlation workflow is substantially larger than a startup check and
requires the full package dependency set.

## 4. Slurm submission

All submission drivers default to one seed so an accidental command does not
enqueue the historical full grid. Use an isolated output root for a smoke run
so the supplied reference artifacts are not overwritten.

```bash
TRANSFERSEMI_OUTPUT_ROOT=outputs/slurm-smoke \
  N_SEEDS=1 bash scripts/submit_all.sh
```

At clusters that require an explicit Slurm account or QoS, set the standard
`SBATCH_ACCOUNT` and `SBATCH_QOS` environment variables for the command. The
submission drivers also export the resolved repository root because Slurm runs
a copied worker script from its spool directory.

Request 100 seeds for every configured simulation grid explicitly:

```bash
N_SEEDS=100 bash scripts/submit_all.sh
```

The tracked DR artifacts establish 100-replicate coverage for their settings,
and the main PLM tree is nearly complete at 100 replicates. The tracked CATE
and fine-tuning artifacts contain only seed 1, so the repository does not prove
that their historical manuscript runs used 100 replicates; author confirmation
is required for that historical claim.

Restricted/pseudo-data jobs are a separate opt-in workflow:

```bash
N_REAL_SEEDS=1 bash scripts/submit_real_data_jobs.sh
N_REAL_SEEDS=150 bash scripts/submit_real_data_jobs.sh
```

They can also be included in the master submission with
`SUBMIT_REAL_DATA=1`, for example:

```bash
SUBMIT_REAL_DATA=1 N_SEEDS=1 N_REAL_SEEDS=1 bash scripts/submit_all.sh
```

Logs are created beneath `logs/`.

## 5. Script and output map

| Entry point | Purpose | Canonical output beneath `TRANSFERSEMI_OUTPUT_ROOT` |
|---|---|---|
| `simulation/test_CATE.R` | CATE simulation | `CATE_dim<dim>/CATE_<n>_<similarity>/`, with nuisance diagnostics under `propensity_score/` and `outcome_model/` |
| `simulation/test_DR_parametric_only.R` | Parametric DR simulation | `DR_9_new/mse_n_<n>_simi_<similarity>/` |
| `simulation/test_PLM.R` | Main PLM simulation | `results_11_dim<dim>/` |
| `simulation/PLM_fintune.R` | PLM fine-tuning | `results_finetune_new<dim>/` and `results_finetune_new_time<dim>/` |
| `simulation/test_PLM_before.R` | Legacy PLM implementation | `results_5_resotre_dim<dim>/` |
| `simulation/PLM_time.R` | Development timing/grid workflow | `results_6_dim<dim>/` and `time_6_dim<dim>/_n_<n>_simi_<similarity>lambda_len<lambda_length>/` |
| `real_data/create_pseudo_data.R` | Generate public pseudo-data from local restricted inputs | `real_data/cape_pseudo.csv` and `real_data/ninr_pseudo.csv`, or an explicit output directory |
| `real_data/RealDataAnalysis.R` | Seeded public pseudo-data analysis | `real_data/result_real_data/`, or `TRANSFERSEMI_REAL_OUTPUT_DIR` |
| `real_data/correlations.R` | Pseudo-data correlation artifacts | `real_data/corr/`, or `TRANSFERSEMI_CORR_OUTPUT_DIR` |

Shell workers in `scripts/` call these R entry points. The `submit_*.sh`
drivers enumerate parameter grids; `submit_all.sh` coordinates the primary
drivers; `time_submit.sh` is a separate development timing submission.

## 6. Canonical repository paths and supplied artifacts

- Package implementation: `TransferSemi/R/`
- Simulation entry points: `simulation/`
- Cluster drivers/workers: `scripts/`
- Canonical pseudo-data: `real_data/cape_pseudo.csv` and
  `real_data/ninr_pseudo.csv`
- Bundled real-data-workflow results: `real_data/result_real_data/` (the
  serialized objects do not embed input provenance)
- Correlation outputs: `real_data/corr/` after running the workflow
- Simulation artifacts: `semi-transfer-learning/`
- Self-contained MSE plotting data:
  `semi-transfer-learning/MSE_visualization_data.rds` (PLM, CATE, and DR
  task-level results used by `visualization_github/MSE_visualization.Rmd`)
- Figure sources: `visualization_github/`
- Newly generated notebook artifacts: `outputs/derived/` and
  `outputs/figures/`

The audited checkout contains:

| Artifact tree | Files | Coverage note |
|---|---:|---|
| `semi-transfer-learning/CATE_dim8` | 38 | Seed 1 results for 12 settings plus nuisance diagnostics; not a full replicate grid |
| `semi-transfer-learning/DR_9_new` | 2,200 | 100 files in each of 22 tracked settings |
| `semi-transfer-learning/results_4_dim8` | 2,400 | Precomputed legacy PLM artifacts |
| `semi-transfer-learning/results_5_dim8` | 2,200 | Precomputed PLM artifacts |
| `semi-transfer-learning/results_11_dim8` | 3,591 | Main PLM artifacts; some settings are incomplete |
| `semi-transfer-learning/MSE_visualization_data.rds` | 1 | Precomputed PLM, CATE, and DR inputs for every plot in `MSE_visualization.Rmd`; raw simulation directories are not needed to render this notebook |
| `semi-transfer-learning/results_finetune_new8` | 22 | Seed 1 fine-tuning results and summaries |
| `semi-transfer-learning/results_finetune_new_time8` | 11 | Seed 1 timing summaries |
| `real_data/result_real_data` | 141 | Missing seeds 7, 9, 12, 36, 53, 65, 77, 91, and 148 from 1–150 |

The checkout does **not** contain
`results_before_dim8`, `results_compare_linear_dim8`, `results_6_dim8`,
`time_6_dim8`, `time_6_dim20`, or generated
`real_data/corr` artifacts. Notebooks that require them now fail or skip with an
explicit message instead of silently substituting another dataset.

## 7. Render figures in clean R processes

Run each notebook in its own R process:

```bash
Rscript -e 'rmarkdown::render("visualization_github/MSE_visualization.Rmd", envir=new.env(parent=globalenv()))'
Rscript -e 'rmarkdown::render("visualization_github/PLM_Visualization_PLM.Rmd", envir=new.env(parent=globalenv()))'
Rscript -e 'rmarkdown::render("visualization_github/finetune_visualize.Rmd", envir=new.env(parent=globalenv()))'
Rscript -e 'rmarkdown::render("visualization_github/read_real_analysis.Rmd", envir=new.env(parent=globalenv()))'
Rscript -e 'rmarkdown::render("visualization_github/sim_visualization_CATE.Rmd", envir=new.env(parent=globalenv()))'
Rscript -e 'rmarkdown::render("visualization_github/sim_visualization_DR.Rmd", envir=new.env(parent=globalenv()))'
Rscript -e 'rmarkdown::render("visualization_github/time_visualize.Rmd", envir=new.env(parent=globalenv()))'
```

Notebooks write derived data and figures beneath `outputs/` and no longer
change the process working directory. Rendering a notebook whose listed input
tree is absent is expected to stop with its documented preflight message.
`MSE_visualization.Rmd` is the exception: it reads the supplied
`semi-transfer-learning/MSE_visualization_data.rds`, so all of its plots can be
rendered without rerunning or retaining the simulation result trees.

## 8. Pseudo-data and restricted-data limitations

The original CAPE and NINR participant-level datasets are restricted and are
not distributed here. The supplied pseudo-data contain 1,638 CAPE rows and
1,244 NINR rows; the manuscript summary values describe the restricted
analysis cohorts and must not be interpreted as dimensions of the pseudo-data
files.

### 8.1 Generation procedure



The procedure is independent column-wise marginal synthesis, not permutation
of intact rows and not additive noise applied to intact records:

- character and factor fields sample observed values with replacement;
- logical and numeric binary fields use Bernoulli draws at their observed
  marginal proportions;
- other numeric and integer fields sample observed nonmissing values with
  replacement, so their original missingness is not reintroduced;
- the named phone, print, and print-plus-phone treatment indicators and their
  control comparisons are reconstructed from the sampled treatment;
- selected age, binary, and score fields are coerced to their intended types;
- `resp21` is replaced by a Bernoulli draw from a logistic model with intercept
  -0.2, treatment coefficients 0.25/0.35/0.45, coefficients 0.15 for
  standardized age and `ben1tot`, and Gaussian linear-predictor noise with
  standard deviation 0.4.

Column names/order and study row counts are retained. Because most columns are
sampled independently, multivariable dependence is generally not preserved
except for the explicit treatment rules and generated outcome relationship.

This algorithm is not a formal privacy mechanism. It can reuse exact observed
values, levels, ranges, marginal frequencies, and identifiers if they are
present in an input column. It implements no differential privacy,
k-anonymity, identifier screening, outlier suppression, or disclosure-risk
assessment. The supplied public files should therefore not be described as
anonymized or privacy-guaranteed; their release authorization is a data-owner
decision outside this code.

### 8.2 What the public pseudo-data reproduce

| Repository output | Public pseudo-data scope | Restricted-data scope |
|---|---|---|
| Seed-specific `RealDataAnalysis.R` result files | Re-runnable from the supplied pseudo CSVs; these validate the analysis code on synthetic marginal data. | They do not reproduce restricted-cohort numerical estimates. |
| `combined_err.pdf` and `maximum_real_data.pdf` | `read_real_analysis.Rmd` can create pseudo-data analogues from newly generated pseudo-data result files. | Any manuscript values based on original CAPE/NINR require the restricted inputs and an author-confirmed workflow. |
| `corr.pdf` and `combined_err_by_summary.pdf` | Re-runnable pseudo-data analogues after `real_data/correlations.R` generates its inputs. | They are not evidence that restricted-data correlations or comparisons were regenerated. |
| Embedded notebook summaries and comparison matrices | Re-runnable summaries of the selected pseudo-data result directory. | Restricted cohort descriptive or inferential tables require the original data. |

For a fresh pseudo-data render, point both producers and the notebook at the
same isolated directories:

```bash
export TRANSFERSEMI_REAL_OUTPUT_DIR=outputs/pseudo-run/results
export TRANSFERSEMI_CORR_OUTPUT_DIR=outputs/pseudo-run/corr
Rscript real_data/RealDataAnalysis.R 1
Rscript real_data/correlations.R
Rscript -e 'rmarkdown::render("visualization_github/read_real_analysis.Rmd", envir=new.env(parent=globalenv()))'
```



## 9. Serialization note

Several correlation artifacts retain legacy names ending in `.Rdata` even
though they are written with `saveRDS()`. Read those files with `readRDS()`,
not `load()`. Files written with `save()` use `.RData` and are read with
`load()`.

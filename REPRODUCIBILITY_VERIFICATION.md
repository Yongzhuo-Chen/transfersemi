# Reproducibility verification

Initial verification date: 2026-07-16. Slurm follow-up date: 2026-07-21.
Pseudo-data follow-up date: 2026-07-29.
Commands were run from the repository root unless another working directory is
shown. A `PASS` label means the requested deterministic repository fix was
implemented and checked. It does not imply that unavailable scientific inputs
or historical random states were reconstructed. The dated follow-up below
supersedes the earlier environment-specific missing-package results where the
two records differ.

## Slurm follow-up verification (2026-07-21)

All submitted jobs explicitly used account `sai.zhang` and the requested QoS
`sai.zhang-b`. Generated files and logs were isolated below the ignored path
`outputs/reproduction_smoke/2026-07-21/`; no supplied result artifact was
overwritten.

| Check | Label | Evidence at the time of this record |
|---|---|---|
| Compute-node environment | PASS | Job 37748339 completed 0:0; R 4.3.3 loaded `gglasso`, `MAVE`, `Matrix`, `np`, `pracma`, `torch`, and `glmnet`, and `torch::torch_is_installed()` returned true. |
| R package build/install/check | PASS | Job 37749653 completed 0:0. Build and isolated install succeeded. Exact `R CMD check --no-manual` finished with 0 errors, 1 warning, and 1 note. |
| Same-seed CPU torch check | PASS | Job 37749769 completed 0:0; two independent `pERM_torch()` fits were exactly equal for both `step1` and `step2`. |
| DR one-seed computation | PASS | Job 37749015 completed 0:0 in 00:12:19 and wrote the expected RData file. |
| CATE one-seed computation | PASS | Job 37748908 completed 0:0 in 00:23:15 and wrote the expected result RData plus four nuisance-diagnostic CSV files. |
| PLM one-seed computation | PASS | Job 37749028 completed 0:0 in 00:21:51 and wrote the expected MSE RDS, estimate RDS, and timing CSV. |
| PLM fine-tuning completion | NOT TESTED | Corrected job 37749029 was still running; the supplied seed-1 timing indicates this is a multi-hour workflow. |
| Timing, real-data, and correlation numerical completion | NOT TESTED | These optional/development workflows were not submitted in this follow-up. |
| Full configured seed grids | NOT TESTED | Only representative seed-1 cases were used; no 47-job or historical multi-seed grid was enqueued. |

The first CATE attempt, job 37748463, failed 2:0 before R execution because
Slurm executes a spool copy of a worker and `${BASH_SOURCE[0]}` therefore
resolved below `/var/spool/slurmd`. The three waiting jobs were canceled before
they could encounter the same failure. All six worker scripts now prefer the
exported `TRANSFERSEMI_REPO_ROOT`, fall back to a validated
`SLURM_SUBMIT_DIR`, and validate repository markers. All six submitters export
the resolved root. The corrected CATE, DR, PLM, and fine-tuning jobs all reached
their actual numerical code.

The completed DR output exactly matched the supplied seed-1 result for all six
non-torch method rows. The pERM row differed, with maximum absolute difference
0.6200129. The historical torch initialization state was not recorded, whereas
the revised run seeds torch; no historical RNG state was invented to force a
match. The separately executed same-seed test demonstrates repeatability of the
revised pERM implementation.

The completed CATE result has the expected 10-by-5 method/task shape and only
finite values. Eight method rows exactly match the supplied seed-1 result;
`Net_Transfer` and `pERM_transfer` differ, with maximum absolute differences
6.145494 and 66.338741 respectively. Its ARMUL diagnostic CSV files match the
supplied files byte-for-byte; the pERM diagnostics differ. The completed PLM
MSE result has the expected 11-by-5 shape, finite values, and matching method
and task names; all three expected output files are present. These differences
are reported, not silently substituted. CATE reported 29 warnings and PLM
reported at least 50 warnings at shutdown, but the scripts did not print the
warning messages themselves; their contents therefore remain unknown without
a rerun configured for immediate warnings.

## Pseudo-data follow-up verification (2026-07-29)

The author supplied the original pseudo-data generator from a separate working
copy. Its statistical algorithm was preserved in
`real_data/create_pseudo_data.R`; only input validation, root discovery,
directory creation, canonical output names, and removal of the hard-coded
author path were added. Restricted `cape.csv` and `ninr.csv` files are ignored
by Git and are not present in the repository.

The portable generator was run against the author-identified restricted local
inputs with outputs isolated below `outputs/pseudo-regeneration/`. Under R
4.3.3, both outputs were byte-identical to the canonical public CSV files:

- CAPE, 1,638 rows by 25 columns:
  `0afa6e8d20650bd0d83d79b73b8211f42aaacdfaa76771d9ac778367769cd773`
- NINR, 1,244 rows by 27 columns:
  `5ca5d3f61437a530b0a88248c5d7797b9ae7cb0f6261d993da214e172f0c6925`

This comparison verifies the supplied generator's provenance for the two CSV
files; it does not verify the input provenance of the bundled serialized
real-data result objects or reproduce restricted-data scientific estimates.

## Reviewer issues

### Issue 1: CATE simulation output directories — PASS

- `simulation/test_CATE.R` and both CATE-reading notebooks now use
  `semi-transfer-learning/CATE_dim8/` for dimension 8.
- Final results use `CATE_<n>_<similarity>/<seed>.RData`.
- Propensity diagnostics use `propensity_score/CATE_<n>_<similarity>/`.
- Outcome-model diagnostics use `outcome_model/CATE_<n>_<similarity>/`.
- Every directory is created through `ensure_output_dir()`, which calls
  `dir.create(..., recursive = TRUE, showWarnings = FALSE)`.
- The old `TransferSemi/R/CATE_repro_test8/`, top-level `CATE_pro_dim8/`, and
  empty `CATE_mu_dim8/` paths are absent.
- The 38 supplied CATE artifacts were relocated to the canonical tree. The
  36 old package artifacts and two propensity artifacts were compared with
  their new files; all 38 content checksums matched. The broader relocation
  check, including 22 fine-tuning artifacts, reported 60 files and zero
  checksum mismatches.
- `TransferSemi/R/` now contains only `.R` source files.

The earlier local CATE attempt stopped at a missing `torch` dependency. In the
2026-07-21 compute environment, corrected job 37748908 passed dependency
loading, completed the full simulation, and wrote the result plus all four
nuisance diagnostics in the configured canonical layout.

### Issue 2: broken visualization paths — PASS

- `visualization_github/MSE_visualization.Rmd` now reads the single supplied
  `semi-transfer-learning/MSE_visualization_data.rds` object. It validates the
  PLM, CATE, and DR components and their required columns before plotting, and
  it does not read any raw simulation result directory.
- Direct validation found 11,997 PLM rows, 17,048 CATE rows, and 8,393 DR rows.
  The 12 PLM compatibility partitions each contain only their advertised
  `(n, similarity)` setting; their 999/1,000-row coverage exactly reflects the
  contents of the supplied saved object.
- `visualization_github/read_real_analysis.Rmd` now reads seeded results from
  `real_data/result_real_data/` and correlation artifacts from
  `real_data/corr/`.
- The nonexistent `dataset/result17`, `dataset/corr`, and
  `transfer-learning/dataset/combined_err.pdf` paths were removed.
- All notebook figures and derived files are written below `outputs/figures/`
  or `outputs/derived/`, whose directories are created in setup chunks.
- Producer/consumer timing paths were aligned to
  `time_6_dim<dim>/_n_<n>_simi_<similarity>lambda_len<lambda_length>/`.
- Code extracted from all seven notebooks parses successfully.
- Input-contract checks successfully loaded all 12 supplied CATE scenarios,
  1,200 DR files used by the DR notebook, 1,200 base PLM files, and 1,197 main
  PLM comparison files.

On 2026-08-02, SLURM job 38555173 rendered all 36 stages of
`MSE_visualization.Rmd` successfully using the saved RDS data and produced the
self-contained HTML plus 22 PDF figures and seven negative-transfer CSV files.
The compatibility files used by the original PLM mean/maximum chunks were
checked to contain separate `(n, similarity)` partitions. Complete rendering
of notebooks with other documented missing inputs is not claimed.

### Issue 3: absolute author-specific paths — PASS

- Repository runtime code now derives roots from the executing R script,
  exported `TRANSFERSEMI_REPO_ROOT`, validated `SLURM_SUBMIT_DIR`,
  `${BASH_SOURCE[0]}` for direct shell execution, or repository markers in
  notebook setup chunks.
- A final search of source and workflow files found no `setwd()`, `/home/`,
  `/Users/`, Windows drive path, OneDrive path, `~/Pictures/`, or fragile `../`
  result path.
- Simulation, real-data, and submission entry points were also invoked from
  `/tmp`; they resolved repository files correctly. The submission dry run
  still generated 47 expected calls, and the R entry points reached their
  first unavailable dependency rather than failing to locate repository code.
- A relative `TRANSFERSEMI_OUTPUT_ROOT=outputs/relative_smoke` was verified to
  resolve below the repository, not below the caller's `/tmp` directory.

### Issue 4: `/corr` output-directory bug — PASS

- `real_data/correlations.R` defines one output root, defaulting to
  `real_data/corr/`, with optional `TRANSFERSEMI_CORR_OUTPUT_DIR` override.
- It creates the directory recursively before writes and routes every
  correlation `save()`, `saveRDS()`, and `write.csv()` call through it.
- The duplicated block that reassigned `out_dir <- "/corr"` was removed.
- A startup attempt with a temporary override created only that temporary
  directory and stopped at missing `glmnet`; filesystem root `/corr` remained
  absent.

### Issue 5: complete the R package DESCRIPTION — PASS

Deterministic metadata and source-layout work passed:

- `TransferSemi/DESCRIPTION` now has a real title, description, existing
  version, anonymous author/maintainer metadata, R minimum, license, Imports,
  Suggests, and LibTorch/LibLantern system requirements.
- At the author's request, the package author and maintainer are recorded as
  `Anonymous`, with the non-personal placeholder address
  `anonymous@example.com`. The package and repository licenses use the same
  anonymous attribution.
- `TransferSemi/LICENSE` was added from the repository's MIT license.
- `NAMESPACE` uses 21 explicit exports and explicit `glmnet` and `stats`
  imports.
- Package-level `library()` calls were removed; package implementation calls
  use namespaces.
- The false `hello()` manual was replaced by package/API documentation.
- All six Rd files parse, all exports have definitions and aliases, and
  `R CMD build` succeeds.
- The built tarball has 25 entries and contains only DESCRIPTION, LICENSE,
  NAMESPACE, R source, and Rd documentation; no result CSV/RDS/RData artifact
  is included.

The 2026-07-21 compute-node follow-up supersedes the earlier dependency failure.
`R CMD build`, an isolated `R CMD INSTALL`, and exact
`R CMD check --no-manual` all completed. The final check status was 0 errors,
1 warning, and 1 note. The warning reports an unused `method` argument in the
exported but workflow-unused `Nonpar_Gradient_Per_Site()` branch. The note also
reports that branch plus the pre-existing `train_idx` and `x` bindings in
branches not exercised by the documented workflows. These scientific/code
ambiguities remain listed under A6 rather than being changed without evidence
of the intended method. Redundant, unused `library(labelled)` calls were removed
from three notebooks and `labelled` was removed from `Suggests`; dependency
checking then passed without forced-Suggests relaxation.

### Issue 6: environment specification — PASS

- The author directed that the working R 4.3 cluster environment be used as
  the snapshot source. `renv` 1.2.3 was installed from CRAN and the actual
  `renv::init()` and `renv::snapshot()` operations completed with exit status
  0; no lockfile content was manually constructed.
- `.Rprofile`, `renv.lock`, `renv/activate.R`, and `renv/settings.json` now
  define the project environment. `.renvignore` excludes generated result
  trees from dependency discovery, and `renv/library/` is ignored.
- `renv.lock` records R 4.3.3 and 90 package records. Direct dependency
  discovery found 26 packages (including `renv`), with none missing from the
  source environment.
- A follow-up `renv::snapshot()` reported that the lockfile was already up to
  date, and `renv::status()` reported: `No issues found -- the project is in a
  consistent state.`
- `renv::restore()` completed with exit status 0 and reported that the project
  library was already synchronized with the lockfile.
- The activated project loaded R package `torch` 0.16.3 and verified a working
  CPU LibTorch 2.7.1 / LibLantern 0.1.0.9004 backend.
- README documents `renv::restore()`, the external backend caveat, exact tested
  backend versions, and the torch installation check.

### Issue 7: simulation seed ranges — PASS

- All primary submission drivers validate `N_SEEDS`, default it to 1, and loop
  from 1 through that value.
- `N_SEEDS=1 bash scripts/submit_all.sh` produced 47 stubbed `sbatch` calls:
  12 CATE, 12 DR, 11 fine-tuning, and 12 PLM.
- `N_SEEDS=100 bash scripts/submit_all.sh` produced 4,700 stubbed calls.
- Timing and real-data jobs were absent from the default master dry run.
- `N_REAL_SEEDS=1` and `N_REAL_SEEDS=150` produced 1 and 150 stubbed real-data
  calls respectively.
- Invalid values such as `N_SEEDS=0` and `N_REAL_SEEDS=x` exit with status 2
  before submitting a job.
- README distinguishes smoke submission from an explicitly requested 100-seed
  grid and does not claim that the seed-1-only CATE/fine-tuning artifacts prove
  their historical manuscript replicate counts.

### Issue 8: legacy scripts — PASS

- `simulation/test_PLM_before.R` is retained with a legacy/provenance header,
  safe paths, validated arguments, and documented legacy output names.
- `simulation/PLM_time.R` is retained as a development/timing workflow because
  it is called by `scripts/PLM_time.sh` and `scripts/time_submit.sh`.
- `simulation/PLM_fintune.R` remains an active fine-tuning workflow, with all
  output moved out of package source.
- README maps the PLM, CATE, DR, fine-tuning, timing, and real-data entry points
  to their output contracts.

### Issue 9: pseudo-data documentation — PASS

- SHA-256 confirmed each top-level pseudo-data copy was byte-identical to its
  `real_data/` counterpart:
  - CAPE: `0afa6e8d20650bd0d83d79b73b8211f42aaacdfaa76771d9ac778367769cd773`
  - NINR: `5ca5d3f61437a530b0a88248c5d7797b9ae7cb0f6261d993da214e172f0c6925`
- The duplicate top-level files were removed; only
  `real_data/cape_pseudo.csv` and `real_data/ninr_pseudo.csv` remain canonical.
- All code reads the canonical files.
- `real_data/create_pseudo_data.R` preserves the author-supplied algorithm and
  seeds while accepting explicit restricted input paths and using a canonical,
  auto-created repository-relative output directory.
- The generator independently resamples column marginals, reconstructs named
  treatment fields, and regenerates `resp21`; it is not intact-row permutation
  or additive noise. Most joint dependence is not preserved.
- README documents the exact seeds and outcome model, the historical behavior
  that drops missingness for non-binary numeric fields, and the absence of a
  formal privacy/disclosure guarantee.
- README maps the public workflow to the named pseudo-data analogues
  `combined_err.pdf`, `maximum_real_data.pdf`, `corr.pdf`, and
  `combined_err_by_summary.pdf`. It explicitly claims no numbered or numerical
  restricted-data paper figure/table is reproduced from pseudo-data.
- `read_real_analysis.Rmd` honors the same real-result and correlation output
  overrides as their producer scripts, allowing a clean pseudo-data run to be
  rendered without substituting bundled results.
- The bundled serialized real-data results do not record input provenance, and
  the documentation does not claim otherwise.

### README reproduction guide — PASS

README now provides a numbered, repository-root workflow for software setup,
package build/check/install, local one-seed runs, configurable Slurm grids,
real-data commands, canonical inputs/outputs, precomputed coverage, clean
notebook rendering, missing inputs, serialization format, restricted-data
limitations, and pseudo-data scope. No runtime estimate was invented.

## Additional repository-wide issues

### A1: shell jobs hide failures or depend on caller paths — PASS

All 13 shell scripts use a Bash shebang, strict mode, quoted script-derived
paths, validated parameters, and executable mode 0755. `bash -n`, `shellcheck`,
and stubbed submission runs pass. A clean-environment CATE worker returned the
underlying R failure status 1 and did not execute its trailing completion date.

The managed test shell's environment-module implementation itself initially
failed with status 255 because sandboxed socket operations were denied.
Compute-node testing then exposed a separate real defect: Slurm's spool copy
made `${BASH_SOURCE[0]}` point outside the repository. Workers now use the
exported root or validated `SLURM_SUBMIT_DIR`, submitters propagate that root,
and corrected jobs for all four primary workflow families reached numerical
execution. `bash -n`, `shellcheck`, direct outside-CWD testing, and simulated
spool-path testing all pass.

### A2: fine-tuning outputs inside package source — PASS

Twenty-two fine-tuning artifacts were moved to
`semi-transfer-learning/results_finetune_new8/`. Their checksums match the old
package-internal copies. New fine-tuning and timing writes use
`semi-transfer-learning/` (or `TRANSFERSEMI_OUTPUT_ROOT`) exclusively.

### A3: torch randomness and hardware choice — PASS

The code seeds both R and torch and defaults both torch estimators to CPU, with
an explicit device override. All tensors created by `pERM_torch()` use the
selected device. Job 37749769 ran two independent fits with identical data and
seed and obtained exact equality for both returned coefficient stages.

### A4: deterministic real-results notebook indexing/name errors — PASS

Task loops now use their loop index, pooled value-function data use the pooled
object, stale variables and the `elected_columns` typo were removed, and result
files are sorted by numeric seed. The clean render processed all 141 available
seed files before stopping at missing `ggplot2`; the generated base summaries
contain 8,742 rows, 141 seeds, and nine missing seeds exactly as documented.

### A5: missing visualization inputs and incomplete grids — REQUIRES AUTHOR INPUT

The repository still lacks `results_before_dim8`,
`results_compare_linear_dim8`, `results_6_dim8`, `time_6_dim8`,
`time_6_dim20`, and generated `real_data/corr` inputs. These omissions still
affect the separate PLM-comparison, timing, and real-data notebooks, but no
longer prevent `MSE_visualization.Rmd` from rendering. Real-data outputs lack
seeds 7, 9, 12, 36, 53, 65, 77, 91, and 148. No files were synthesized or
silently substituted.

### A6: scientific/correctness ambiguities — REQUIRES AUTHOR INPUT

Potential numerical-method defects recorded in the audit were deliberately not
changed, including captured spline-basis state in ARMUL, undefined/questionable
utility branches, `lmabda` in the CATE call, hard-coded fold assumptions, and
the pooled PLM split indices. Correcting them could change reported numbers and
requires author confirmation and expected-value tests.

### A7: generated log and unexplained placeholders — REQUIRES AUTHOR INPUT

The tracked Slurm log was removed and generated logs are ignored. The empty
tracked `client` and `server` files were retained because their purpose cannot
be inferred; the author should confirm whether they should be removed.

### A8: misleading serialized-file extensions — PASS

The legacy `.Rdata` files written with `saveRDS()` are consistently read with
`readRDS()` and are explicitly documented. They were not broadly renamed
because doing so offers no numerical benefit and would change an established
file contract.

## Commands run and observed results

### Static source checks

```bash
Rscript --vanilla -e 'for (f in c(list.files("TransferSemi/R", full.names=TRUE, pattern="[.]R$"), list.files("simulation", full.names=TRUE, pattern="[.]R$"), list.files("real_data", full.names=TRUE, pattern="[.]R$"))) parse(f)'
Rscript --vanilla -e 'for (f in list.files("visualization_github", full.names=TRUE, pattern="[.]Rmd$")) { out<-tempfile(fileext=".R"); knitr::purl(f,out,quiet=TRUE); parse(out) }'
bash -n scripts/*.sh
shellcheck scripts/*.sh
git diff --check
```

All completed with exit status 0. The R check parsed 24 source files; the Rmd
check extracted and parsed all seven notebooks.

Final path searches used `rg` over R, Rmd, shell, and configuration files for
the reviewer patterns, `setwd(`, old CATE roots, and fragile `../` result paths.
No active source hit remained. Historical strings remain only where the audit
describes the baseline problem.

### Package build, documentation, install, and check

Working directory: `/tmp/chen.yongzhuo/transfersemi_repro_build`.

```bash
R CMD build <repo-root>/TransferSemi
for f in <repo-root>/TransferSemi/man/*.Rd; do R CMD Rd2txt "$f" >/dev/null; done
R CMD INSTALL --library=/tmp/chen.yongzhuo/transfersemi_repro_library TransferSemi_0.1.0.tar.gz
R CMD check --no-manual TransferSemi_0.1.0.tar.gz
```

- Build: exit 0; generated `TransferSemi_0.1.0.tar.gz`.
- Rd conversion: exit 0 for all six files.
- Export/definition/alias checks: exit 0 after using the corrected scanner;
  21 exports, no missing definition, no missing alias, no extra API alias.
- Install: exit 1; six required dependencies unavailable; no installed package
  remained in the temporary library.
- Check: exit 1 at dependency checking; generated
  `TransferSemi.Rcheck/00check.log`. The check also warned that the managed
  environment could not reach CRAN and Bioconductor package indices. Later
  check stages were not reached, so there is no verified package-code warning
  or note count.

An initial custom alias scanner incorrectly inspected only top-level Rd nodes
and produced a false missing-alias report. A line-based Rd alias scanner was
then run and passed. No repository change was based on the false result.

### Argument validation

Missing-argument invocations were run for all six simulation entry points,
`RealDataAnalysis.R`, and `correlations.R`. Each returned exit 1 with its Usage
message. A temporary output root remained absent, proving validation happened
before directory creation. CATE dimension 7 also returned exit 1 with the
dimension-8 requirement and created no output.

### Initial local numerical smoke attempts (2026-07-16)

```bash
TRANSFERSEMI_OUTPUT_ROOT=/tmp/chen.yongzhuo/transfersemi_smoke/plm \
  Rscript --vanilla simulation/test_PLM.R 100 0 1 8 100
TRANSFERSEMI_OUTPUT_ROOT=/tmp/chen.yongzhuo/transfersemi_smoke/cate \
  Rscript --vanilla simulation/test_CATE.R 100 0 1 8
TRANSFERSEMI_OUTPUT_ROOT=/tmp/chen.yongzhuo/transfersemi_smoke/dr \
  Rscript --vanilla simulation/test_DR_parametric_only.R 100 0 1 8
```

All three returned exit 1 at `there is no package called 'torch'` in that local
environment. Each created only its requested empty output root; no result file
was generated. The later compute-node results are recorded in the dated Slurm
follow-up and supersede this as the current execution test.

```bash
TRANSFERSEMI_REAL_OUTPUT_DIR=/tmp/chen.yongzhuo/transfersemi_smoke/real \
  Rscript --vanilla real_data/RealDataAnalysis.R 1
TRANSFERSEMI_CORR_OUTPUT_DIR=/tmp/chen.yongzhuo/transfersemi_smoke/corr \
  Rscript --vanilla real_data/correlations.R
```

Both returned exit 1 at missing `glmnet` in that local environment. The
correlation command created its temporary output directory and no file; `/corr`
was not created. Neither optional workflow received a full numerical rerun in
the Slurm follow-up.

### Notebook render attempts

Each notebook was launched separately with:

```bash
Rscript --vanilla -e 'rmarkdown::render("<notebook>.Rmd", envir=new.env(parent=globalenv()), quiet=TRUE)'
```

Observed first blockers:

| Notebook | Exit | First blocker |
|---|---:|---|
| `MSE_visualization.Rmd` | 1 | missing `dplyr` |
| `PLM_Visualization_PLM.Rmd` | 1 | missing `dplyr` |
| `finetune_visualize.Rmd` | 1 | missing `dplyr` |
| `read_real_analysis.Rmd` | 1 | missing `ggplot2` after processing 141 result files |
| `sim_visualization_CATE.Rmd` | 1 | missing `ggplot2` |
| `sim_visualization_DR.Rmd` | 1 | missing `ggplot2` |
| `time_visualize.Rmd` | 1 | missing `data.table` |

No HTML file was generated. The read-real attempt generated the ignored files
`outputs/derived/read_real_analysis/raw_data.RData` and
`Mean_Mean_model_summaries.RData`. An initial non-escalated render attempt was
blocked by the managed filesystem when knitr tried to create temporary
`*.knit.md` files; it was repeated with repository-write permission and reached
the dependency errors above.

### Submission dry runs

A shell `sbatch()` stub was exported; no real job was enqueued.

```bash
N_SEEDS=1 bash scripts/submit_all.sh
N_SEEDS=100 bash scripts/submit_all.sh
N_REAL_SEEDS=1 bash scripts/submit_real_data_jobs.sh
N_REAL_SEEDS=150 bash scripts/submit_real_data_jobs.sh
```

All exited 0 and produced 47, 4,700, 1, and 150 stub calls respectively.

### Artifact and coverage checks

- Relocation comparison: 60 files checked, zero checksum mismatch.
- CATE canonical tree: 38 files = 12 result RData + 24 outcome diagnostics +
  two propensity diagnostics.
- Fine-tuning canonical tree: 22 files.
- DR tree: 2,200 files.
- Main PLM tree: 3,591 files.
- Real-data tree: 141 files.
- CATE input-contract test: 12 scenarios, 120 method rows, exit 0.
- DR input-contract test: 12 notebook scenarios, 1,200 files, 8,400 method
  rows, exit 0.
- Corrected PLM input-contract test: 1,200 base files and 1,197 comparison
  files, exit 0. An earlier diagnostic incorrectly required `Pooled` in the
  base tree; inspection showed that replacement is intentionally supplied by
  the comparison tree, and the corrected contract passed.

### Initial local environment record (2026-07-16)

- R 4.3.3 (2024-02-29), x86_64-conda-linux-gnu.
- Red Hat Enterprise Linux 9.8.
- OpenBLAS 0.3.27; LAPACK 3.12.0.
- Pandoc available: yes.
- Installed relevant packages: `splines` 4.3.3, `stats` 4.3.3, `knitr` 1.49,
  `rmarkdown` 2.29, `scales` 1.3.0, `tibble` 3.2.1.
- Required analysis packages absent include `gglasso`, `MAVE`, `Matrix`, `np`,
  `pracma`, `torch`, `glmnet`, `dplyr`, `ggplot2`, and `data.table`.
- `renv` absent; `torch` namespace absent.

### Compute-node environment record (2026-07-21)

- R 4.3.3 (2024-02-29), x86_64-pc-linux-gnu, from module `R/4.3`.
- Ubuntu 22.04.5 LTS; GCC and GNU Fortran 11.4.0.
- Required implementation packages available: `gglasso`, `MAVE`, `Matrix`,
  `np`, `pracma`, `torch`, and `glmnet`.
- `torch::torch_is_installed()` returned true and CPU tensor/optimization tests
  completed.
- All package dependencies and remaining Suggests were available after removal
  of the unused `labelled` notebook load.

### Locked environment record (2026-07-29)

- R 4.3.3, `renv` 1.2.3, and R package `torch` 0.16.3.
- CPU LibTorch 2.7.1 and LibLantern 0.1.0.9004; backend tensor creation passed.
- `renv::snapshot()`, `renv::restore()`, and `renv::status()` passed through
  the committed `.Rprofile` activation.

## File-by-file modification summary

- `.gitignore`: ignores package/check artifacts, notebook outputs, and generated
  logs.
- `.renvignore`, `.Rprofile`, `renv.lock`, and `renv/`: define and maintain the
  locked R environment while excluding generated artifacts and the local
  project library from version control.
- `README.md`: replaced the truncated guide with the complete reproduction
  workflow and limitations.
- `REPRODUCIBILITY_AUDIT.md`: baseline issue validation, affected lines,
  proposed fixes, and verification plan; created before implementation edits.
- `REPRODUCIBILITY_VERIFICATION.md`: this executed verification record.
- `TransferSemi/DESCRIPTION`: completed package metadata and dependencies.
- `TransferSemi/NAMESPACE`: explicit API exports and stats imports.
- `TransferSemi/LICENSE`: package-local MIT license.
- `TransferSemi/R/ARMUL.R`: removed package-load `library(splines)` calls.
- `TransferSemi/R/pERM.R`: explicit CPU/device handling and optional R/torch
  seeding; tensors consistently use the selected device.
- `TransferSemi/R/reNet.R`: namespace-qualified torch API, CPU default, and
  torch seeding paired with the existing R seed.
- `TransferSemi/man/TransferSemi-package.Rd`: package documentation.
- `TransferSemi/man/site_estimators.Rd`: site estimator API documentation.
- `TransferSemi/man/torch_estimators.Rd`: torch estimator/device/seed
  documentation.
- `TransferSemi/man/transfer_estimators.Rd`: transfer-combination API
  documentation.
- `TransferSemi/man/utilities.Rd`: utility API documentation.
- `TransferSemi/man/vanilla_ARMUL.Rd`: ARMUL API documentation.
- `TransferSemi/man/hello.Rd`: removed because the documented function did not
  exist.
- `simulation/reproducibility_helpers.R`: shared root, argument, output, source,
  and seed helpers.
- `simulation/test_CATE.R`: canonical CATE paths, diagnostics subdirectories,
  argument validation, CPU device, and reproducible seeding.
- `simulation/test_DR_parametric_only.R`: rooted output, validation, CPU device,
  and portable filename construction.
- `simulation/test_PLM.R`: rooted output, validation, CPU device, seeding, and
  removal of unused parallel scaffolding.
- `simulation/PLM_fintune.R`: fine-tuning output moved from package source,
  stable CV initialization, rooted timing output, and validation.
- `simulation/PLM_time.R`: rooted result/timing output, validated lambda length,
  and removal of unused parallel scaffolding.
- `simulation/test_PLM_before.R`: legacy label, safe output roots, validation,
  and CPU device.
- `real_data/RealDataAnalysis.R`: stable root, canonical pseudo-data, validated
  seed, output override, directory creation, and torch seed when available.
- `real_data/create_pseudo_data.R`: preserved author-supplied pseudo-data
  algorithm and seeds with explicit restricted inputs, canonical outputs,
  validation, and recursive directory creation.
- `real_data/correlations.R`: stable root, canonical inputs, single relative
  correlation output root, and all writes routed through it.
- `scripts/CATE.sh`, `DR.sh`, `PLM_finetune.sh`, `PLM_time.sh`,
  `my_job_script.sh`, `run_real_analysis.sh`: strict workers with validated
  environment variables, Slurm-spool-safe repository discovery, and rooted R
  entry points.
- `scripts/submit.sh`, `submit_CATE.sh`, `submit_DR.sh`,
  `submit_PLM_finetune.sh`: configurable validated seed ranges, explicit
  repository-root propagation to workers, and auto-created log paths.
- `scripts/submit_all.sh`: primary-grid coordinator; timing separate and real
  data opt-in.
- `scripts/submit_real_data_jobs.sh`: validated `N_REAL_SEEDS` and corrected
  historical-target documentation.
- `scripts/time_submit.sh`: configurable seed count and rooted timing worker.
- `visualization_github/MSE_visualization.Rmd`: self-contained saved-data input
  with structural validation, all supplied PLM/CATE/DR plots, rooted
  derived/figure outputs, deterministic per-setting PLM partitions, and no raw
  simulation-tree or optional `ggh4x` dependency.
- `visualization_github/read_real_analysis.Rmd`: actual real/correlation paths,
  numeric seed ordering, corrected task/pooling indices and stale names, and
  rooted figure outputs.
- `visualization_github/sim_visualization_CATE.Rmd`: canonical CATE input,
  numeric seed parsing, no home path, and rooted outputs.
- `visualization_github/sim_visualization_DR.Rmd`: canonical DR input, numeric
  seed parsing, corrected maximum-plot object, and rooted outputs.
- `visualization_github/PLM_Visualization_PLM.Rmd`: stable roots, explicit
  missing-input messages, rooted outputs, and no unused `labelled` dependency.
- `visualization_github/finetune_visualize.Rmd`: stable roots, canonical
  fine-tuning/timing contracts, explicit missing-input messages, and rooted
  outputs; its unused `labelled` dependency was removed.
- `visualization_github/time_visualize.Rmd`: producer-aligned timing path,
  explicit lambda length, corrected plot reference, and rooted outputs.
- `real_datacape_pseudo.csv`, `real_dataninr_pseudo.csv`: removed byte-identical
  duplicates.
- `scripts/logs_CATE/CATE_29725324.log`: removed generated run log.
- `TransferSemi/R/CATE_repro_test8/` ->
  `semi-transfer-learning/CATE_dim8/`: 36 artifacts relocated, with outcome
  diagnostics placed under `outcome_model/`.
- `CATE_pro_dim8/` ->
  `semi-transfer-learning/CATE_dim8/propensity_score/`: two artifacts relocated.
- `TransferSemi/R/results_finetune_new8/` ->
  `semi-transfer-learning/results_finetune_new8/`: 22 artifacts relocated.

## Author input required

1. Data-owner confirmation of redistribution/disclosure acceptability and
   confirmation of which tracked real-data outputs came from pseudo versus
   original data.
2. Historical CATE and fine-tuning replicate counts.
3. Missing result trees for the separate PLM-comparison and timing notebooks,
   and missing real-data seeds, or the intended manuscript subset if omissions
   were deliberate.
4. Scientific intent for the numerical ambiguities listed in audit A6.
5. Intended disposition of the empty tracked `client` and `server` files.

## Tests not completed

- Full 100-seed numerical simulations were not run.
- CATE, DR, and PLM seed 1 completed. Fine-tuning job 37749029 was still running
  when this record was finalized, so its complete artifacts are not claimed.
- Package build/install/check and same-seed CPU torch equality completed; CUDA
  and cross-platform numerical tests were not run.
- `MSE_visualization.Rmd` was rendered completely from its supplied saved-data
  object. Full follow-up renders of notebooks with other missing result trees
  were not run and still require author-provided inputs.
- Real-data, correlation, and development timing workflows were not submitted
  in the follow-up run.
- Restricted-original-data analysis reproduction was not attempted. Restricted
  inputs were used only for the isolated pseudo-data regeneration/hash check.
- `renv::init()`, `renv::snapshot()`, `renv::restore()`, activation, status,
  and backend checks were performed. The restore was a synchronized-library
  no-op; a separate destructive clean-library restore was not run.

## Exact remaining verification commands

Run from the repository root in an environment allowed to install packages:

```bash
Rscript -e 'if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv")'
Rscript -e 'renv::restore()'
Rscript -e 'stopifnot(torch::torch_is_installed()); print(torch::torch_device("cpu"))'

R CMD build TransferSemi
R CMD check --no-manual TransferSemi_0.1.0.tar.gz
R CMD INSTALL TransferSemi_0.1.0.tar.gz

export TRANSFERSEMI_OUTPUT_ROOT=outputs/verification
Rscript simulation/test_PLM.R 100 0 1 8 100
Rscript simulation/test_CATE.R 100 0 1 8
Rscript simulation/test_DR_parametric_only.R 100 0 1 8

TRANSFERSEMI_REAL_OUTPUT_DIR=outputs/verification/real \
  Rscript real_data/RealDataAnalysis.R 1
TRANSFERSEMI_CORR_OUTPUT_DIR=real_data/corr \
  Rscript real_data/correlations.R

Rscript real_data/create_pseudo_data.R \
  "$CAPE_ORIGINAL" "$NINR_ORIGINAL" outputs/pseudo-regeneration

Rscript -e 'rmarkdown::render("visualization_github/MSE_visualization.Rmd", envir=new.env(parent=globalenv()))'
Rscript -e 'rmarkdown::render("visualization_github/PLM_Visualization_PLM.Rmd", envir=new.env(parent=globalenv()))'
Rscript -e 'rmarkdown::render("visualization_github/finetune_visualize.Rmd", envir=new.env(parent=globalenv()))'
Rscript -e 'rmarkdown::render("visualization_github/read_real_analysis.Rmd", envir=new.env(parent=globalenv()))'
Rscript -e 'rmarkdown::render("visualization_github/sim_visualization_CATE.Rmd", envir=new.env(parent=globalenv()))'
Rscript -e 'rmarkdown::render("visualization_github/sim_visualization_DR.Rmd", envir=new.env(parent=globalenv()))'
Rscript -e 'rmarkdown::render("visualization_github/time_visualize.Rmd", envir=new.env(parent=globalenv()))'

Rscript --vanilla -e 'sessionInfo()'
```

Before the separate PLM-comparison, fine-tuning, and timing notebooks can
complete, provide or regenerate the missing result trees documented above.
`MSE_visualization.Rmd` does not require those trees. Do not replace missing
inputs with different result sets without author confirmation.

# Reproducibility audit

This audit was created before implementation changes. File and line references in
this document refer to the clean baseline at commit `3091da4` (`master`). The
review text supplied with the task is treated as the authoritative issue list.

## Baseline inspection

- The repository contained 10,658 tracked files: 23 R scripts, 13 shell scripts,
  7 R Markdown notebooks, an R package nested under `TransferSemi/`, four
  pseudo-data CSV copies, and 10,402 precomputed artifacts under
  `semi-transfer-learning/`.
- `git status --short` was empty before this audit was created.
- All 23 `.R` files parsed successfully with R 4.3.3. Code extracted from all
  seven `.Rmd` files also parsed successfully. `bash -n scripts/*.sh` passed.
  These are syntax checks, not runtime tests.
- The active R 4.3.3 library has `splines`, `tibble`, `scales`, `knitr`, and
  `rmarkdown`, but lacks most analysis dependencies, including `glmnet`,
  `gglasso`, `MAVE`, `np`, `pracma`, `torch`, and `pbmcapply`.
- No `renv.lock`, `renv/`, `.Rprofile`, or R project file was present. No lockfile
  will be invented.
- Precomputed artifact coverage was inspected rather than assumed. The primary
  DR tree contains 100 files for each of 22 settings. The main PLM tree generally
  contains 100 files per setting, but three settings contain 99. The package-
  internal CATE tree contains only seed 1 for 12 settings. The real-data tree
  contains 141 of the apparent 150 seeds.

## Reviewer issue 1: CATE simulation output directories

**Validity: valid.**

Affected baseline locations:

- `simulation/test_CATE.R:8-19` initially creates
  `semi-transfer-learning/CATE_dim<dim>/`, plus separate top-level
  `CATE_pro_dim<dim>/` and `CATE_mu_dim<dim>/` trees.
- `simulation/test_CATE.R:219-224` overwrites `result_dir` with
  `CATE_repro_test<dim>/` after the script has changed into `TransferSemi/R`.
  Diagnostic writes at lines 247-250 and 390-393 and the final result write at
  lines 770-771 therefore go into the package source. Propensity diagnostics are
  written at lines 187 and 326 to a different top-level tree. `result_dir_mu` is
  created but never used.
- `visualization_github/sim_visualization_CATE.Rmd:42-94,216` and
  `visualization_github/MSE_visualization.Rmd:292-344,933` read the canonical
  `semi-transfer-learning/CATE_dim8/` tree, which contained no tracked files.
- `TransferSemi/R/CATE_repro_test8/` contained 36 generated files;
  `CATE_pro_dim8/` contained two; `CATE_mu_dim8/` and the canonical scenario
  directories were empty.

Proposed deterministic fix:

- Make `semi-transfer-learning/CATE_dim<dim>/` the only CATE result root.
- Keep final per-seed `.RData` files in `CATE_<n>_<similarity>/`, and put nuisance
  diagnostics in documented subdirectories beneath the same CATE root.
- Relocate the existing generated CATE artifacts out of `TransferSemi/R/` and
  the two top-level auxiliary trees without changing their contents.
- Construct paths from a stable repository root with `file.path()` and create
  every output directory with
  `dir.create(..., recursive = TRUE, showWarnings = FALSE)`.

Verification plan:

- Search for all four old CATE root names and confirm only documentation/history
  references remain.
- Confirm the package `R/` directory contains only R source files.
- Parse the simulation and notebooks, inventory the relocated files, and compare
  checksums across the moves.
- Attempt a one-seed CATE run when dependencies are available; otherwise record
  the dependency failure rather than claim a runtime pass.

## Reviewer issue 2: broken visualization paths

**Validity: valid.**

Affected baseline locations:

- `visualization_github/MSE_visualization.Rmd:50-51` immediately overwrites a
  valid comparison root with nonexistent `../results_11_dim8`.
- The same notebook changes working directories at lines 102, 138, 453, 504,
  801, and 1045, then often prepends the old relative root again (for example,
  lines 109-112), producing doubled or context-dependent paths.
- `visualization_github/read_real_analysis.Rmd:49` reads nonexistent
  `../semi-transfer-learning/dataset/result17`; the actual tracked results are
  in `real_data/result_real_data/`.
- Correlation reads at lines 304, 315, 341, 343, and 437 alternate between
  nonexistent `./data/corr/` and
  `../semi-transfer-learning/dataset/corr/`. `real_data/correlations.R` is
  intended to create `real_data/corr/`, although that directory is not present
  until the analysis runs.
- Figure writes at lines 168 and 639 target nonexistent directories; line 639
  also uses the inconsistent `transfer-learning` name.

Proposed deterministic fix:

- Use repository-rooted `file.path()` values throughout all notebooks and remove
  stateful `setwd()` calls.
- Point PLM comparison input to
  `semi-transfer-learning/results_11_dim8`, real-data replicates to
  `real_data/result_real_data`, and correlation inputs to `real_data/corr`.
- Use an auto-created `outputs/figures/` and `outputs/derived/` tree for rendered
  artifacts rather than writing into source or input directories.
- Add explicit preflight errors or guarded sections for genuinely absent inputs;
  do not silently map an unknown manuscript input to a different result set.

Verification plan:

- Extract and parse notebook code after editing.
- Statistically inspect every literal repository path and confirm it either
  exists as an input or is created before output.
- Render notebooks whose dependencies and tracked inputs are available; list
  missing inputs and packages for the rest.

## Reviewer issue 3: absolute author-specific and fragile paths

**Validity: valid.**

Affected baseline locations:

- `visualization_github/sim_visualization_CATE.Rmd:365` writes to
  `~/Pictures/combined_CATE_group_plot.pdf`.
- `visualization_github/finetune_visualize.Rmd:241,368,413` uses filesystem-root
  paths beginning `/semi-transfer-learning`.
- `real_data/correlations.R:1270` uses `/corr` (also reviewer issue 4).
- All six simulation entry points use `setwd("../TransferSemi/R")` at their first
  or second line. `real_data/RealDataAnalysis.R:1,19-23,128-129,777-778` and
  `real_data/correlations.R:171,173-182` similarly assume a particular working
  directory. Every worker shell script assumes submission from `scripts/`.
- Numerous notebooks use `setwd()` and `../` paths whose meaning changes during
  a render.

No `/home/`, `/Users/`, `C:\\`, or OneDrive path was found in tracked source.

Proposed deterministic fix:

- Derive the root from the executing R script path for R entry points, from
  `${BASH_SOURCE[0]}` for shell scripts, and by walking upward to stable repository
  markers in R Markdown setup chunks.
- Replace path concatenation with `file.path()`, remove `setwd()` from analyses,
  quote shell paths/arguments, and document that copyable commands are launched
  from the repository root even though scripts remain location-aware.

Verification plan:

- Repeat the repository-wide absolute-path and `setwd()` search.
- Invoke entry points with missing/invalid arguments from the repository root and
  confirm they fail clearly before creating output.
- Use a stub `sbatch` to inspect resolved submission paths without scheduling
  jobs.

## Reviewer issue 4: `/corr` output-directory bug

**Validity: valid.**

Affected baseline locations:

- `real_data/correlations.R:291-293` first creates a relative `corr` directory.
- `real_data/correlations.R:1270-1309` later replaces it with absolute `/corr`
  and duplicates many writes. Other outputs at lines 776-777, 1161-1166,
  1201-1208, 1228, 1253, and 1265 are written to the current directory instead
  of the declared output directory.

Proposed deterministic fix:

- Define one `real_data/corr/` path from the repository root, create it once, and
  route all correlation artifacts through it. Remove the duplicate absolute-path
  save block while retaining one write for every distinct artifact.

Verification plan:

- Search for `/corr` and bare output writes, parse the script, and perform a
  startup/runtime check when dependencies permit.

## Reviewer issue 5: complete the R package DESCRIPTION

**Validity: valid.**

Affected baseline locations:

- `TransferSemi/DESCRIPTION:3,5-9` contains package-skeleton placeholders;
  line 12 is stale generated `Packaged` metadata. There are no dependency fields.
- Root `LICENSE:1-20` is MIT for Anonymous Authors, but the package has no license
  file and its DESCRIPTION license is a placeholder.
- Required package implementation dependencies are evidenced by code references:
  `Matrix`, `MAVE`, `gglasso`, `np`, `pracma`, `splines`, `stats`, and `torch`.
  Workflow-only packages additionally include `glmnet`, `pbmcapply`, `ggplot2`,
  `reshape2`, `dplyr`, `tidyr`, `tibble`, `stringr`, `cowplot`, `patchwork`,
  `labelled`, `data.table`, `scales`, `gridExtra`, `forcats`, `knitr`, and
  `rmarkdown`.
- `TransferSemi/R/reNet.R:1` and `TransferSemi/R/ARMUL.R:2,43` attach packages at
  package-load/source time.
- `TransferSemi/NAMESPACE:1` exports every alphabetic object. The only manual,
  `TransferSemi/man/hello.Rd`, documents a nonexistent `hello()`.
- Generated results beneath `TransferSemi/R/` are included by `R CMD build`.

The repository deliberately uses anonymous authorship in both `LICENSE` and Git
metadata. That existing identity can be carried into package metadata; a real
author or non-placeholder maintainer address cannot be inferred and remains
author input.

Proposed deterministic fix:

- Replace skeleton fields with a title and description inferred from the code and
  README, preserve version `0.1.0`, use the repository's existing anonymous
  identity, declare `MIT + file LICENSE`, and add the package license file.
- Declare implementation packages in `Imports` without invented version bounds;
  put analysis/notebook-only packages in `Suggests`. Declare `R (>= 4.1.0)` because
  `TransferSemi/R/ARMUL.R:161` uses the native pipe introduced in R 4.1.
- Remove top-level `library()` calls, use namespace imports/qualification, replace
  the wildcard export with explicit exports, and replace the false hello manual
  with documentation for the actual API.
- Move generated artifacts out of the package source.

Verification plan:

- Parse package sources, run `R CMD build TransferSemi`, inspect tarball contents,
  and run `R CMD check` on the tarball. If Imports cannot be installed, report the
  check's dependency error exactly and do not label installation as passed.

## Reviewer issue 6: environment specification

**Validity: valid, including the review-text inconsistency.**

The review itself states that the dependency/environment heading was followed by
duplicated CATE-path text. No separate reviewer-response document exists in the
repository, so there is nothing to edit.

Repository findings:

- No renv project or lockfile exists.
- The code implies R >= 4.1.0 through the native pipe; the inspected environment
  is R 4.3.3. No narrower or exact author-intended R version can be inferred.
- Package and workflow dependencies are enumerated under issue 5.
- `torch` code requires its LibTorch/LibLantern runtime. No required torch or
  LibTorch version is recorded, so none will be fabricated. CPU execution is the
  reproducible default to document; CUDA is optional and hardware dependent.
- The current library is not a complete, valid analysis environment and `renv`
  itself is not installed. A genuine snapshot therefore cannot be made here.

Proposed deterministic fix:

- Add explicit R, package, LibTorch/LibLantern, and source-build toolchain
  installation instructions to README, including an official torch installation
  check and CPU setup.
- State clearly that no lockfile is supplied and that dependency versions are not
  recoverable from the repository. Do not add `renv.lock`.
- Record the actually observed `sessionInfo()` in the final verification report.

Verification plan:

- Run and record `R --version`, `sessionInfo()`, installed dependency checks,
  package build/check, and torch availability checks. Mark restoration and
  environment-level runtime tests NOT TESTED when dependencies are unavailable.

Post-audit update (2026-07-29): the author subsequently directed that the
working cluster environment be treated as the snapshot source. This new input
superseded the baseline constraint above: R 4.3.3 had all discovered project
dependencies and a working torch backend, and `renv` 1.2.3 was installed from
CRAN before running the real `renv::init()` and `renv::snapshot()` operations.

## Reviewer issue 7: simulation seed ranges

**Validity: valid.**

Affected baseline locations:

- `scripts/submit.sh:20`, `submit_CATE.sh:19`, `submit_DR.sh:19`, and
  `submit_PLM_finetune.sh:17` hard-code seed 1 only.
- Main PLM and DR scripts contain unused 1:100 constants, and their precomputed
  primary result trees mostly contain 100 seeds. The current CATE and fine-tuning
  artifacts contain seed 1 only, so their manuscript replicate count is not
  proven by repository outputs.
- `scripts/submit_real_data_jobs.sh:3-9` says 100 in comments/messages but loops
  over 150; only 141 corresponding outputs are present.

Proposed deterministic fix:

- Validate and honor `N_SEEDS` (default 1) in simulation submitters. Make
  `N_SEEDS=1 bash scripts/submit_all.sh` the smoke submission and
  `N_SEEDS=100 bash scripts/submit_all.sh` the explicit 100-seed grid.
- Keep restricted real-data submission separate and configurable with
  `N_REAL_SEEDS`, documenting the baseline script's inferred 150 target and the
  nine missing precomputed seeds rather than claiming completeness.
- Remove unused arrays and unused pseudo-parallel constants.

Verification plan:

- Run shell syntax checks and a stub-`sbatch` dry run for `N_SEEDS=1` and a
  count-only dry run for `N_SEEDS=100`; do not enqueue real jobs during audit.

## Reviewer issue 8: legacy scripts

**Validity: valid.**

Affected baseline locations:

- `simulation/test_PLM_before.R` has no caller and writes to inconsistent,
  misspelled roots such as `results_5_resotre_dim`.
- `simulation/PLM_time.R` is invoked by `scripts/PLM_time.sh` and
  `scripts/time_submit.sh`, so it is a timing/development workflow rather than an
  unreferenced file.
- `simulation/PLM_fintune.R` is called by the fine-tuning submission workflow but
  writes some outputs inside the package source and other outputs to a different
  root.
- The README does not identify which scripts produce PLM, CATE, DR, real-data,
  fine-tuning, or timing artifacts.

Proposed deterministic fix:

- Retain scripts to avoid losing potentially useful scientific code, add clear
  legacy/development headers, make their paths safe, and document their status.
- List the primary manuscript-facing entry points and supplementary/legacy
  scripts in README. Do not represent unverified legacy outputs as manuscript
  results.

Verification plan:

- Search all shell and documentation references, verify each documented command
  points to an existing file, and parse every retained script.

## Reviewer issue 9: pseudo-data documentation

**Validity: valid.**

Affected baseline locations and evidence:

- SHA-256 proves `real_datacape_pseudo.csv` is byte-identical to
  `real_data/cape_pseudo.csv`
  (`0afa6e8d20650bd0d83d79b73b8211f42aaacdfaa76771d9ac778367769cd773`).
- SHA-256 proves `real_dataninr_pseudo.csv` is byte-identical to
  `real_data/ninr_pseudo.csv`
  (`5ca5d3f61437a530b0a88248c5d7797b9ae7cb0f6261d993da214e172f0c6925`).
- `real_data/RealDataAnalysis.R:128-129,777-778` and
  `real_data/correlations.R:181-182` use the copies under `real_data/`.
- At baseline, no generator or documentation explained permutation,
  simulation, noise, dependence preservation, or whether the tracked real-data
  result files came from pseudo or restricted original data.
- README lines 19-22 describe restricted originals but do not explain the
  supplied pseudo-data scope. Its original-cohort sample sizes (lines 28-29) do
  not match the pseudo CSV row counts (1,638 CAPE and 1,244 NINR data rows).

Follow-up evidence supplied by the author on 2026-07-28:

- The generator used to create the public files was supplied from a separate
  working copy. It uses independent column-wise marginal resampling, seeds
  1001 (CAPE) and 2001 (NINR), explicit treatment-field reconstruction, and a
  generated logistic `resp21` outcome.
- It is neither a permutation of intact rows nor additive noise applied to
  intact records. Most joint dependence is not preserved.
- The supplied script hard-coded an author path and malformed top-level output
  names. It also contains no formal disclosure-control assessment.
- Running the supplied algorithm against the restricted local inputs reproduced
  both canonical CSV files byte-for-byte.

Proposed deterministic fix:

- Retain only the canonical `real_data/` copies and ensure all code uses them.
- Add a repository-relative `real_data/create_pseudo_data.R` that preserves the
  supplied statistical algorithm and seeds, accepts explicit restricted input
  paths, creates its output directory, and never embeds an author path.
- Ignore the restricted original filenames so they cannot be accidentally
  committed.
- Document the exact generator, its lack of formal privacy guarantees, and the
  distinction between named pseudo-data analogue figures and restricted-data
  paper results. Do not invent paper figure/table numbers absent from the
  repository or claim provenance for serialized artifacts that do not record
  it.

Verification plan:

- Recompute checksums before removing duplicates, search every pseudo-data
  reference afterward, and validate the canonical CSV paths and dimensions.
- Parse the portable generator and run it against the restricted local inputs
  into an isolated output directory. Compare generated and canonical files
  byte-for-byte and record the R version actually used.

## README reproduction guide

**Validity: valid and incomplete in the baseline.**

`README.md` ends at line 93 in an unclosed code block and tells a root user to run
the nonexistent `correlations.R`. It lacks software installation, package setup,
seed-grid commands, output contracts, local/SLURM distinctions, notebook render
commands, precomputed-result use, and restricted-data limitations. It also says
`submit_all.sh` submits real data although that call is commented out.

Proposed fix: replace it with a numbered, root-oriented workflow containing all
items requested by the review. Runtime estimates will only be included if
measured or recoverable from a clearly identified log; none will be invented.

Verification plan: copy/check every command path, run non-mutating or smoke
commands where dependencies permit, and cross-check documented outputs against
the producing code.

## Additional repository-wide findings

### A1. Shell jobs can hide failures and resolve paths incorrectly

**Validity: valid.** Worker scripts lack strict mode; because `date` follows
`Rscript`, a failed analysis can still leave a zero job status. Slurm log
directories do not exist in a clean clone, and all shell files were mode 0644.

Proposed fix: use strict mode, validate exported variables, anchor paths to each
script, create log directories before `sbatch`, invoke submitters directly from
the master script, quote all expansions, and mark shell scripts executable.
Verify with `bash -n`, `shellcheck` when available, and stub-`sbatch` dry runs.

### A2. Fine-tuning outputs are inside the package and split across roots

**Validity: valid.** `simulation/PLM_fintune.R:15-24` writes under
`TransferSemi/R/results_finetune_new8`, while lines 454-476 write timing data at
another root; tracked timing data are under
`semi-transfer-learning/results_finetune_new_time8`.

Proposed fix: relocate and route both trees under `semi-transfer-learning/` and
update consumers. Verify no non-R artifacts remain under `TransferSemi/R`.

### A3. Torch randomness and hardware choice are not controlled

**Validity: valid.** Base `set.seed()` does not seed `torch_randn` in
`TransferSemi/R/pERM.R:110` or network initialization in `reNet.R`.
`reNet.R:75-77` silently selects CUDA when available.

Proposed deterministic fix: add explicit seed arguments to torch-based APIs,
seed both R and torch, and make CPU the documented/default reproducibility
device while allowing an explicit override. Verify identical same-seed outputs
in two clean processes when torch is available. Do not claim cross-platform
bitwise identity without testing it.

### A4. Real-results notebook contains deterministic indexing/name errors

**Validity: valid.** `read_real_analysis.Rmd:21-27` loops over tasks but always
indexes `[[1]]` and assigns pooled value-function data from `mse`. Lines 342-349
use stale `a`/`index` variables and misspell `selected_columns` as
`elected_columns`. `list.files(...)[1:100]` at lines 49-50 is unsorted and does
not define which successful replicates are intended.

Proposed fix: correct the loop indices and variable names, sort result filenames
by numeric seed, and default summaries to the explicitly reported available
files. The exact manuscript subset remains author input. Verify by running the
data-combination chunks against the tracked 141 files when dependencies permit.

### A5. Missing visualization inputs and incomplete precomputed grids

**Validity: valid, but not mechanically recoverable.** Missing inputs include
`results_compare_linear_dim8`, `results_before_dim8`, `results_6_dim8`, dim-20
timing results, and `real_data/corr` until generated. Main PLM result settings
`n=100, similarity=0.8`, `n=200, similarity=0`, and
`n=200, similarity=0.8` each lack one seed (96, 11, and 31 respectively).
Real-data seeds 7, 9, 12, 36, 53, 65, 77, 91, and 148 are absent.

Proposed fix: add accurate preflight messages and document missing inputs. Do
not synthesize files or substitute scientifically different result trees.
Verification status for affected complete renders will be REQUIRES AUTHOR INPUT.

### A6. Package implementation has scientific/correctness ambiguities

**Validity: confirmed, but changes are outside a deterministic reproducibility
path repair unless the author confirms intent.** Confirmed examples include the
captured spline-basis loop variables in `ARMUL.R:67-100`, undefined/incorrect
branches in `utils.R:69-131`, `Nonpar_Gradient_Per_Site.R:12-15`, and
`CATE_Per_Site.R:45-70`, hard-coded fold assumptions, the misspelled `lmabda`
argument in `test_CATE.R:91`, and questionable pooled split indices in
`test_PLM.R:911`. Several corrections would alter numerical results.

Proposed action: document these as author-review items and do not silently change
the statistical implementation in this reproducibility pass. Syntax/package
metadata/path fixes can proceed independently.

### A7. Generated log and unexplained placeholders are tracked

**Validity: partly valid.** `scripts/logs_CATE/CATE_29725324.log` is a run-specific
generated log and should not be source. Top-level `client` and `server` are empty
tracked files whose intended purpose cannot be inferred.

Proposed fix: remove/ignore generated logs. Retain the unexplained empty files and
flag them for author input rather than guessing their role.

### A8. Misleading serialized-file extensions

**Validity: valid but non-blocking.** `real_data/correlations.R` writes RDS
serialization with names ending `.Rdata`; consumers correctly use `readRDS()`.
Renaming all tracked/untracked contracts would be broad and offers no numerical
benefit.

Proposed action: document that these are RDS-format files despite their legacy
extensions. A future author-approved format migration can rename producers and
consumers together.

## Planned verification record

The final `REPRODUCIBILITY_VERIFICATION.md` will give every numbered reviewer
issue and every additional issue above exactly one of `PASS`, `FAIL`,
`NOT TESTED`, or `REQUIRES AUTHOR INPUT`. It will list each command actually run,
its exit status and relevant output, and any generated files. Full 100-seed
simulation grids will not be run as part of this audit.

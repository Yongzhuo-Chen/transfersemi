#!/usr/bin/env bash

# Shared R environment setup for Slurm jobs. The generic `module load R` can
# drift as the cluster default changes; R/4.3 is the environment used for the
# reproducibility checks and has the required torch installation on HiPerGator.
load_transfersemi_r_module() {
  local r_module=${TRANSFERSEMI_R_MODULE:-R/4.3}
  if command -v module >/dev/null 2>&1; then
    module load "$r_module"
  fi
  command -v Rscript >/dev/null 2>&1 || {
    echo "Rscript was not found on PATH after loading ${r_module}." >&2
    exit 127
  }
}

check_transfersemi_torch() {
  Rscript -e 'if (!requireNamespace("torch", quietly = TRUE)) stop("R package torch is required; install torch or set TRANSFERSEMI_R_MODULE to an R module that provides it.", call. = FALSE)'
}

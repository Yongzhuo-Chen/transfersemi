#!/usr/bin/env bash
#SBATCH --job-name=render_visualizations
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=08:00:00

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ -n ${TRANSFERSEMI_REPO_ROOT:-} ]]; then
  REPO_ROOT=$TRANSFERSEMI_REPO_ROOT
elif [[ -n ${SLURM_SUBMIT_DIR:-} ]]; then
  REPO_ROOT=$SLURM_SUBMIT_DIR
else
  REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
fi
REPO_ROOT=$(cd -- "$REPO_ROOT" && pwd)
[[ -f "$REPO_ROOT/TransferSemi/DESCRIPTION" && -d "$REPO_ROOT/visualization_github" ]] || {
  echo "Could not locate the TransferSemi repository root: $REPO_ROOT" >&2
  exit 2
}

# shellcheck source=scripts/slurm_r_env.sh
source "$REPO_ROOT/scripts/slurm_r_env.sh"
load_transfersemi_r_module

cd -- "$REPO_ROOT"

render_one() {
  local notebook=$1
  echo "Rendering ${notebook}"
  Rscript -e 'args <- commandArgs(trailingOnly = TRUE); rmarkdown::render(args[[1]], envir = new.env(parent = globalenv()))' "$notebook"
}

if [[ -n ${VISUALIZATION_NOTEBOOK:-} ]]; then
  notebooks=("$VISUALIZATION_NOTEBOOK")
else
  notebooks=(
    "visualization_github/MSE_visualization.Rmd"
    "visualization_github/PLM_Visualization_PLM.Rmd"
    "visualization_github/finetune_available_visualization.Rmd"
    "visualization_github/finetune_strategy_comparison.Rmd"
    "visualization_github/sim_visualization_CATE.Rmd"
    "visualization_github/sim_visualization_DR.Rmd"
  )

  if [[ ${RENDER_REAL_DATA:-0} == 1 ]]; then
    notebooks+=("visualization_github/read_real_analysis.Rmd")
  fi

  if [[ ${RENDER_TIME:-0} == 1 ]]; then
    notebooks+=("visualization_github/time_visualize.Rmd")
  fi
fi

for notebook in "${notebooks[@]}"; do
  [[ -f "$REPO_ROOT/$notebook" ]] || {
    echo "Visualization notebook not found: $notebook" >&2
    exit 2
  }
  render_one "$notebook"
done

echo "Visualization rendering finished."

#!/usr/bin/env bash
#SBATCH --job-name=render_simulated_results
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=08:00:00

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ -n ${TRANSFERSEMI_REPO_ROOT:-} ]]; then
  REPO_ROOT=$TRANSFERSEMI_REPO_ROOT
elif [[ -f "$SCRIPT_DIR/../TransferSemi/DESCRIPTION" ]]; then
  REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
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
RESULTS_ROOT=${TRANSFERSEMI_SIMULATION_RESULTS_ROOT:-${TRANSFERSEMI_OUTPUT_ROOT:-semi-transfer-learning}}
if [[ $RESULTS_ROOT != /* ]]; then
  RESULTS_ROOT="$REPO_ROOT/$RESULTS_ROOT"
fi
[[ -d "$RESULTS_ROOT" ]] || {
  echo "Newly simulated results root does not exist: $RESULTS_ROOT" >&2
  echo "Set TRANSFERSEMI_SIMULATION_RESULTS_ROOT to the output root used for the simulation run." >&2
  exit 2
}
RESULTS_ROOT=$(cd -- "$RESULTS_ROOT" && pwd)

required_dirs=(
  results_11_dim8
  CATE_dim8
  DR_9_new
  results_finetune_new8
  results_finetune_new_time8
)
for directory in "${required_dirs[@]}"; do
  [[ -d "$RESULTS_ROOT/$directory" ]] || {
    echo "Missing newly simulated result directory: $RESULTS_ROOT/$directory" >&2
    exit 2
  }
done

# shellcheck source=scripts/slurm_r_env.sh
source "$REPO_ROOT/scripts/slurm_r_env.sh"
load_transfersemi_r_module

AGGREGATE_FILE="$REPO_ROOT/outputs/derived/figures/MSE_visualization_data.rds"
echo "Building plotting data only from raw seed-level results under: $RESULTS_ROOT"
Rscript "$REPO_ROOT/visualization_github/build_simulated_visualization_data.R" \
  "$RESULTS_ROOT" "$AGGREGATE_FILE"

export TRANSFERSEMI_VISUALIZATION_MODE=simulated
export TRANSFERSEMI_RESULTS_ROOT="$RESULTS_ROOT"
export TRANSFERSEMI_MSE_VISUALIZATION_DATA="$AGGREGATE_FILE"
export TRANSFERSEMI_FIGURE_COLLECTION=figures
export RENDER_REAL_DATA=0
export RENDER_TIME=${RENDER_TIME:-0}

echo "Rendering simulated-result figures to: $REPO_ROOT/outputs/figures"
bash "$REPO_ROOT/scripts/render_visualizations.sh"

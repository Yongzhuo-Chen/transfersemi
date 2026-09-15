#!/usr/bin/env bash
#SBATCH --job-name=render_previous_results
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

export TRANSFERSEMI_VISUALIZATION_MODE=previous
export TRANSFERSEMI_RESULTS_ROOT="$REPO_ROOT/semi-transfer-learning"
export TRANSFERSEMI_MSE_VISUALIZATION_DATA="$REPO_ROOT/semi-transfer-learning/MSE_visualization_data.rds"
export TRANSFERSEMI_FIGURE_COLLECTION=figures_previous_results
export RENDER_REAL_DATA=${RENDER_REAL_DATA:-1}
export RENDER_TIME=${RENDER_TIME:-1}

echo "Rendering figures from repository-supplied results to: $REPO_ROOT/outputs/figures_previous_results"
bash "$REPO_ROOT/scripts/render_visualizations.sh"

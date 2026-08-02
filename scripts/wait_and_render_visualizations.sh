#!/usr/bin/env bash
#SBATCH --job-name=wait_render_visualizations
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=2-00:00:00

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
CHECK_INTERVAL_SECONDS=${CHECK_INTERVAL_SECONDS:-300}
SIM_JOB_REGEX='^(CATE|DR|PLM_finetune|PLM_test)$'

cd -- "$REPO_ROOT"

echo "Waiting for simulation jobs to finish before rendering visualizations."
while true; do
  running_jobs=$(squeue -h -u "${USER:-chen.yongzhuo}" -o "%j" | grep -Ec "$SIM_JOB_REGEX" || true)
  if [[ $running_jobs -eq 0 ]]; then
    break
  fi
  date
  echo "Still waiting on ${running_jobs} simulation jobs."
  sleep "$CHECK_INTERVAL_SECONDS"
done

echo "Simulation jobs cleared; rendering visualizations."
bash "$REPO_ROOT/scripts/render_visualizations.sh"

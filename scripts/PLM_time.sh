#!/usr/bin/env bash
#SBATCH --job-name=PLM_time  # Job name
#SBATCH --mail-type=ALL   # Mail events (NONE, BEGIN, END, FAIL, ALL)
#SBATCH --ntasks=1   # Number of tasks
#SBATCH --cpus-per-task=1
#SBATCH --mem=4gb   # Memory per CPU
#SBATCH --time=4-00:00:00   # Time limit hh:mm:ss

set -euo pipefail


# Record the time and compute node the job ran on
date
hostname
pwd

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ -n ${TRANSFERSEMI_REPO_ROOT:-} ]]; then
  REPO_ROOT=$TRANSFERSEMI_REPO_ROOT
elif [[ -n ${SLURM_SUBMIT_DIR:-} ]]; then
  REPO_ROOT=$SLURM_SUBMIT_DIR
else
  REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
fi
REPO_ROOT=$(cd -- "$REPO_ROOT" && pwd)
[[ -f "$REPO_ROOT/TransferSemi/DESCRIPTION" && -d "$REPO_ROOT/simulation" ]] || {
  echo "Could not locate the TransferSemi repository root: $REPO_ROOT" >&2
  exit 2
}
: "${n:?n must be exported by the submitter}"
: "${similarity:?similarity must be exported by the submitter}"
: "${seed:?seed must be exported by the submitter}"
: "${dim:?dim must be exported by the submitter}"

# shellcheck source=scripts/slurm_r_env.sh
source "$REPO_ROOT/scripts/slurm_r_env.sh"
load_transfersemi_r_module
check_transfersemi_torch
cd -- "$REPO_ROOT"
# Run the R script with environment variables for n, similarity, and seed
Rscript "$REPO_ROOT/simulation/PLM_time.R" "$n" "$similarity" "$seed" "$dim" 100

date

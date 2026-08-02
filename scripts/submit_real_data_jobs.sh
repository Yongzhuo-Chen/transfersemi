#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
LOG_DIR="$REPO_ROOT/logs"
mkdir -p -- "$LOG_DIR"
N_REAL_SEEDS=${N_REAL_SEEDS:-1}
[[ $N_REAL_SEEDS =~ ^[1-9][0-9]*$ ]] || { echo "N_REAL_SEEDS must be a positive integer." >&2; exit 2; }

# Existing artifacts imply a historical target of 150 seeds; request it explicitly with N_REAL_SEEDS=150.
for ((seed = 1; seed <= N_REAL_SEEDS; seed++)); do
  # Submit the job with the current seed
  sbatch --output="$LOG_DIR/realdata_%j.log" --error="$LOG_DIR/realdata_%j.log" \
    "--export=ALL,seed=$seed,TRANSFERSEMI_REPO_ROOT=$REPO_ROOT" "$SCRIPT_DIR/run_real_analysis.sh"
done

echo "Submitted jobs for seeds 1 to $N_REAL_SEEDS."

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
LOG_DIR="$REPO_ROOT/logs"
mkdir -p -- "$LOG_DIR"
N_SEEDS=${N_SEEDS:-1}
[[ $N_SEEDS =~ ^[1-9][0-9]*$ ]] || { echo "N_SEEDS must be a positive integer." >&2; exit 2; }
START_SEED=${START_SEED:-1}
[[ $START_SEED =~ ^[1-9][0-9]*$ ]] || { echo "START_SEED must be a positive integer." >&2; exit 2; }
END_SEED=$((START_SEED + N_SEEDS - 1))
# Define arrays for n and similarity values
n_values=(200)
similarity_values=(0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0)
dim=8
# Loop over each combination of n, similarity, and seed
for n in "${n_values[@]}"; do
  for similarity in "${similarity_values[@]}"; do
    for ((seed = START_SEED; seed <= END_SEED; seed++)); do
      echo "Submitting job for n=${n}, similarity=${similarity}, and seed=${seed}"
      sbatch --output="$LOG_DIR/%x_%j.log" --error="$LOG_DIR/%x_%j.log" \
        "--export=ALL,n=$n,similarity=$similarity,seed=$seed,dim=$dim,TRANSFERSEMI_REPO_ROOT=$REPO_ROOT" \
        "$SCRIPT_DIR/PLM_finetune.sh"
    done
  done
done

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
n_values=(100 200)
similarity_values=(0 0.2 0.4 0.6 0.8 1)
dim=8
lambda_length_values=(100)

# Loop over each combination
for n in "${n_values[@]}"; do
  for similarity in "${similarity_values[@]}"; do
    for lambda_length in "${lambda_length_values[@]}"; do
      for ((seed = START_SEED; seed <= END_SEED; seed++)); do
        echo "Submitting job for n=${n}, similarity=${similarity}, lambda_length=${lambda_length}, seed=${seed}"
        sbatch --output="$LOG_DIR/%x_%j.log" --error="$LOG_DIR/%x_%j.log" \
          "--export=ALL,n=$n,similarity=$similarity,seed=$seed,dim=$dim,lambda_length=$lambda_length,TRANSFERSEMI_REPO_ROOT=$REPO_ROOT" \
          "$SCRIPT_DIR/my_job_script.sh"
      done
    done
  done
done

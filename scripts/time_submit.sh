#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
LOG_DIR="$REPO_ROOT/logs"
mkdir -p -- "$LOG_DIR"
N_SEEDS=${N_SEEDS:-1}
[[ $N_SEEDS =~ ^[1-9][0-9]*$ ]] || { echo "N_SEEDS must be a positive integer." >&2; exit 2; }

# Define arrays for n and similarity values
n_values=(100 200)
similarity_values=(0)
dim_values=(20)
# Loop over each combination of n, similarity, and seed
for n in "${n_values[@]}"; do
  for similarity in "${similarity_values[@]}"; do
    for ((seed = 1; seed <= N_SEEDS; seed++)); do
      for dim in "${dim_values[@]}"; do
        echo "Submitting job for n=${n}, similarity=${similarity}, and seed=${seed}"
        sbatch --output="$LOG_DIR/%x_%j.log" --error="$LOG_DIR/%x_%j.log" \
          "--export=ALL,n=$n,similarity=$similarity,seed=$seed,dim=$dim,TRANSFERSEMI_REPO_ROOT=$REPO_ROOT" \
          "$SCRIPT_DIR/PLM_time.sh"
      done
    done
  done
done

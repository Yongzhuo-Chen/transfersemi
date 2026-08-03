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
RENDER_AFTER=${RENDER_AFTER:-0}
[[ $RENDER_AFTER == 0 || $RENDER_AFTER == 1 ]] || { echo "RENDER_AFTER must be 0 or 1." >&2; exit 2; }
job_ids=()

# Define arrays for n and similarity values
n_values=(100 200)
similarity_values=(0)
dim_values=(20)
# Loop over each combination of n, similarity, and seed
for n in "${n_values[@]}"; do
  for similarity in "${similarity_values[@]}"; do
    for ((seed = START_SEED; seed <= END_SEED; seed++)); do
      for dim in "${dim_values[@]}"; do
        echo "Submitting job for n=${n}, similarity=${similarity}, and seed=${seed}"
        submission=$(sbatch --parsable --output="$LOG_DIR/%x_%j.log" --error="$LOG_DIR/%x_%j.log" \
          "--export=ALL,n=$n,similarity=$similarity,seed=$seed,dim=$dim,TRANSFERSEMI_REPO_ROOT=$REPO_ROOT" \
          "$SCRIPT_DIR/PLM_time.sh")
        job_id=${submission%%;*}
        [[ $job_id =~ ^[0-9]+$ ]] || { echo "Unexpected sbatch response: $submission" >&2; exit 2; }
        job_ids+=("$job_id")
        echo "Submitted batch job $job_id"
      done
    done
  done
done

if [[ $RENDER_AFTER == 1 ]]; then
  dependency=$(IFS=:; echo "${job_ids[*]}")
  submission=$(sbatch --parsable \
    "--dependency=afterok:$dependency" \
    "--export=ALL,VISUALIZATION_NOTEBOOK=visualization_github/time_visualize.Rmd,TRANSFERSEMI_REPO_ROOT=$REPO_ROOT" \
    --output="$LOG_DIR/render_time_after_plm_%j.log" \
    --error="$LOG_DIR/render_time_after_plm_%j.log" \
    "$SCRIPT_DIR/render_visualizations.sh")
  render_job_id=${submission%%;*}
  [[ $render_job_id =~ ^[0-9]+$ ]] || { echo "Unexpected render sbatch response: $submission" >&2; exit 2; }
  echo "Submitted dependent timing visualization job $render_job_id"
fi

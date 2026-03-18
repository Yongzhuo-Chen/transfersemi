#!/bin/bash

# Loop through seeds 1 to 100
for seed in {1..150}; do
  # Submit the job with the current seed
  sbatch --export=seed=$seed run_real_analysis.sh
done

echo "Submitted jobs for seeds 1 to 100."

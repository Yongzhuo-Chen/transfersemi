#!/bin/bash

# Define arrays for n and similarity values
n_values=(100 200)
similarity_values=(0)
dim=(20)
# Loop over each combination of n, similarity, and seed
for n in "${n_values[@]}"; do
  for similarity in "${similarity_values[@]}"; do
    for seed in {1..100}; do
      for dim in "${dim[@]}"; do
        echo "Submitting job for n=${n}, similarity=${similarity}, and seed=${seed}"
        sbatch --export=n=$n,similarity=$similarity,seed=$seed,dim=$dim PLM_time.sh
      done
    done
  done
done
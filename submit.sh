#!/bin/bash
#SBATCH --job-name=submit  # Job name
#SBATCH --account=<HPC_ACCOUNT>
#SBATCH --qos=<HPC_QOS>
#SBATCH --mail-type=ALL   # Mail events (NONE, BEGIN, END, FAIL, ALL)
#SBATCH --ntasks=1   # Number of tasks
#SBATCH --cpus-per-task=1
#SBATCH --mem=4gb   # Memory per CPU
#SBATCH --output=logs/%x_%j.log
#SBATCH --error=logs/%x_%j.log
#SBATCH --time=4-00:00:00   # Time limit hh:mm:ss
# Define arrays for n and similarity values
n_values=(100 200)
similarity_values=(0 0.2 0.4 0.6 0.8 1)
dim=8
lambda_length_values=(100)

# Loop over each combination
for n in "${n_values[@]}"; do
  for similarity in "${similarity_values[@]}"; do
    for lambda_length in "${lambda_length_values[@]}"; do
      for seed in {1..100}; do
        echo "Submitting job for n=${n}, similarity=${similarity}, lambda_length=${lambda_length}, seed=${seed}"
        sbatch --export=n=$n,similarity=$similarity,seed=$seed,dim=$dim,lambda_length=$lambda_length my_job_script.sh
      done
    done
  done
done

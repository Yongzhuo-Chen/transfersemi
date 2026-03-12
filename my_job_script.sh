#!/bin/bash
#SBATCH --job-name=PLM_test_liang  # Job name
#SBATCH --account=sai.zhang
#SBATCH --qos=sai.zhang-b
#SBATCH --mail-type=ALL   # Mail events (NONE, BEGIN, END, FAIL, ALL)
#SBATCH --ntasks=1   # Number of tasks
#SBATCH --cpus-per-task=1
#SBATCH --mem=8gb   # Memory per CPU
#SBATCH --output=logs/%x_%j.log
#SBATCH --error=logs/%x_%j.log
#SBATCH --time=4-00:00:00   # Time limit hh:mm:ss



# Record the time and compute node the job ran on
date; hostname; pwd

# Load R module
module load R

# Run the R script with environment variables for n, similarity, and seed
Rscript test_PLM.R $n $similarity $seed $dim $lambda_length

date

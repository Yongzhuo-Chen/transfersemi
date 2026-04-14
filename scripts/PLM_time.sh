#!/bin/bash
#SBATCH --job-name=PLM_time  # Job name
#SBATCH --mail-type=ALL   # Mail events (NONE, BEGIN, END, FAIL, ALL)
#SBATCH --ntasks=1   # Number of tasks
#SBATCH --cpus-per-task=1
#SBATCH --mem=4gb   # Memory per CPU
#SBATCH --output=logs/%x_%j.log
#SBATCH --error=logs/%x_%j.log
#SBATCH --time=4-00:00:00   # Time limit hh:mm:ss



# Record the time and compute node the job ran on
date; hostname; pwd

# Load R module
module load R
cd ../simulation
# Run the R script with environment variables for n, similarity, and seed
Rscript PLM_time.R $n $similarity $seed $dim 100

date

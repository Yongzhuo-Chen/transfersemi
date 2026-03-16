#!/bin/bash
#SBATCH --job-name=DR  # Job name
#SBATCH --account=<HPC_ACCOUNT>
#SBATCH --qos=<HPC_QOS>
#SBATCH --mail-type=ALL   # Mail events (NONE, BEGIN, END, FAIL, ALL)
#SBATCH --ntasks=1   # Number of tasks
#SBATCH --cpus-per-task=1
#SBATCH --mem=4gb   # Memory per CPU
#SBATCH --output=logs_DR/%x_%j.log
#SBATCH --error=logs_DR/%x_%j.log
#SBATCH --time=4-00:00:00   # Time limit hh:mm:ss



# Record the time and compute node the job ran on
date; hostname; pwd

# Load R module
module load R

# Run the R script with environment variables for n, similarity, and seed
Rscript test_DR_parametric_only.R $n $similarity $seed $dim 

date

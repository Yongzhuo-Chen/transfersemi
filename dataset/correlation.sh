#!/bin/bash
#SBATCH --job-name=corr  # Job name
#SBATCH --account=sai.zhang
#SBATCH --qos=sai.zhang-b
#SBATCH --mail-type=ALL                      # Mail events (NONE, BEGIN, END, FAIL, ALL)
#SBATCH --mail-user=chen.yongzhuo@ufl.edu    # Email notifications
#SBATCH --ntasks=1   # Number of tasks
#SBATCH --cpus-per-task=1
#SBATCH --mem=96gb   # Memory per CPU
#SBATCH --time=48:05:00   # Time limit hh:mm:ss
#SBATCH --output=logs/corr_%j.log
#SBATCH --error=logs/corr_%j.log

# Record the time and compute node the job ran on
date; hostname; pwd

# Load R module
module load R

# Run the R script with environment variables for n, similarity, and seed
Rscript correlations.R 

date

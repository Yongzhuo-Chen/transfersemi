#!/bin/bash
#SBATCH --job-name=PLM_test_liang  # Job name
#SBATCH --account=muxuan.liang
#SBATCH --qos=muxuan.liang-b
#SBATCH --ntasks=1   # Number of tasks
#SBATCH --cpus-per-task=1
#SBATCH --mem=8gb   # Memory per CPU
#SBATCH --time=2-00:00:00   # Time limit hh:mm:ss
#SBATCH --output=logs/realdata_%j.log
#SBATCH --error=logs/realdata_%j.log

# Record the time and compute node the job ran on
date; hostname; pwd

# Load R module
module load R

# Run the R script with environment variables for n, similarity, and seed
Rscript RealDataAnalysis.R $seed

date

#!/bin/bash
#SBATCH --job-name=PLM_test_liang  # Job name
#SBATCH --account=sai.zhang
#SBATCH --qos=sai.zhang-b
#SBATCH --mail-type=ALL   # Mail events (NONE, BEGIN, END, FAIL, ALL)
#SBATCH --ntasks=1   # Number of tasks
#SBATCH --cpus-per-task=1
#SBATCH --mem=32gb   # Memory per CPU
#SBATCH --output=logs_PLM_compare/%x_%j.log
#SBATCH --error=logs_PLM_compare/%x_%j.log
#SBATCH --time=4-00:00:00   # Time limit hh:mm:ss



# Record the time and compute node the job ran on
date; hostname; pwd

# Load R module
module load R
export R_LIBS_USER="/orange/muxuan.liang/yongzhuo/Rlibs/4.3"

# Run the R script with environment variables for n, similarity, and seed
Rscript PLM_compare.R $n $similarity $seed $dim

date

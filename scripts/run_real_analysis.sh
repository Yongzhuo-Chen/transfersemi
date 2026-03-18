#!/bin/bash
#SBATCH --job-name=real_data_analysis
#SBATCH --account=muxuan.liang
#SBATCH --qos=muxuan.liang-b
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=2-00:00:00
#SBATCH --output=logs/realdata_%j.log
#SBATCH --error=logs/realdata_%j.log

date
hostname
pwd

module load R

cd "$SLURM_SUBMIT_DIR/../real_data" || exit 1

echo "Running seed=$seed"
Rscript RealDataAnalysis.R "$seed"

date

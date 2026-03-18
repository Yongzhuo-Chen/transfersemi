#!/bin/bash

set -e

echo "===== MASTER SUBMISSION START ====="
date
hostname
pwd



mkdir -p ../logs

echo "Submitting jobs..."

# Submit each job script
sbatch submit_CATE.sh
sbatch submit_DR.sh
sbatch submit_PLM_finetune.sh
#sbatch submit_real_data_jobs.sh
sbatch submit.sh
#sbatch time_submit.sh

echo "===== ALL JOBS SUBMITTED ====="
date

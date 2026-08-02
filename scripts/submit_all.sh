#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

echo "===== MASTER SUBMISSION START ====="
date
hostname
pwd
echo "Submitting jobs..."

# Submission drivers run directly and enqueue their worker jobs.
bash "$SCRIPT_DIR/submit_CATE.sh"
bash "$SCRIPT_DIR/submit_DR.sh"
bash "$SCRIPT_DIR/submit_PLM_finetune.sh"
bash "$SCRIPT_DIR/submit.sh"

# Timing experiments are a separate development workflow; run time_submit.sh explicitly.

# Restricted real data are opt-in: set SUBMIT_REAL_DATA=1 to enqueue them.
if [[ ${SUBMIT_REAL_DATA:-0} == 1 ]]; then
  bash "$SCRIPT_DIR/submit_real_data_jobs.sh"
fi

echo "===== ALL JOBS SUBMITTED ====="
date

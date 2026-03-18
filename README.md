# TransferSemi: Reproducibility Code

This repository contains code and data to reproduce the simulation results, real data analysis, and figures in the paper.

---

## 📂 Repository Structure

- `scripts/`  
  Shell scripts for running experiments.  
  Running `submit_all.sh` will submit all simulation and real data jobs.

- `simulation/`  
  Simulation code for PLM, CATE, and DR settings.

- `TransferSemi/`  
  Implementation of the proposed method and comparison methods.

- `real_data/`  
  Code for real data analysis.  
  ⚠️ Due to data restrictions, the original dataset is not included.  
  Pseudo-code and analysis pipeline are provided.

- `visualization_github/`  
  R Markdown (`.Rmd`) files for generating figures in the paper.

- `semi-transfer-learning/`  
  Precomputed simulation results used for visualization.  
  These allow direct reproduction of figures without rerunning simulations.

---

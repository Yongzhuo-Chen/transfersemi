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
  Due to data restrictions, the original dataset cannot be shared.  
  We provide pseudo-code and the full analysis pipeline.

  ### 📊 Real Data Description

  We analyze two breast cancer screening datasets:

  - **CAPE** ($n=1487$)  
  - **NINR** ($n=1169$)

  These datasets include demographic characteristics, screening history, and psychosocial measures related to mammography behavior.

  #### Variables

  - **Age**: Categorized into four groups (≤50, 50–55, 55–70, ≥70)  
  - **Race (Caucasian)**: Binary indicator  
  - **Currently working for pay**: Binary indicator  
  - **Mammogram history (past 2–5 years)**: 0, 1, or ≥2 screenings  
  - **Family history of breast cancer**: Binary indicator  

  #### Psychosocial Scales

  All scales are reported as **median (IQR)**:

  - **Barriers** — perceived obstacles to screening  
  - **Benefits** — perceived advantages of screening  
  - **Self-efficacy** — confidence in obtaining screening  
  - **Susceptibility** — perceived risk  
  - **Fear** — emotional response  
  - **Fatalism** — belief in predetermined outcomes  
  - **Knowledge** — understanding of breast cancer and screening  

  #### Summary Statistics

  | Variable | CAPE (n=1487) | NINR (n=1169) |
  |----------|--------------|--------------|
  | **Age, No. (%)** | | |
  | ≤50 | 711 (47.81) | 1 (0.09) |
  | 50–55 | 351 (23.60) | 254 (21.73) |
  | 55–70 | 366 (24.61) | 520 (44.48) |
  | ≥70 | 59 (3.97) | 394 (33.70) |
  | **Race-Caucasian (%)** | 83.12 | 45.68 |
  | **Currently working (%)** | 78.95 | 29.94 |
  | **Mammogram (past 2–5 years, %)** | | |
  | 0 year | 19.77 | 19.42 |
  | 1 year | 21.05 | 19.93 |
  | ≥2 years | 59.18 | 60.62 |
  | **Family history (%)** | 14.73 | 12.15 |
  | **Barriers (median, IQR)** | 45 (37–49) | 32 (26–38) |
  | **Benefits (median, IQR)** | 16 (15–18) | 30 (27–33) |
  | **Self-efficacy (median, IQR)** | 40 (38–43) | 42 (40–49) |
  | **Susceptibility (median, IQR)** | 12 (10–15) | 6 (5–7) |
  | **Fear (median, IQR)** | 22 (18–28) | 21 (16–29) |
  | **Fatalism (median, IQR)** | 23 (19–27) | 6 (3–9) |
  | **Knowledge (median, IQR)** | 6 (5–6) | 4 (2–5) |

  #### Key Observations

  - CAPE participants are generally **younger** and more likely to be working  
  - NINR participants are **older** with lower employment rates  
  - Psychosocial differences:
    - CAPE shows higher **barriers** and **fatalism**
    - NINR shows higher **perceived benefits**
    - CAPE has higher **knowledge scores**

  These differences highlight **distributional heterogeneity**, motivating transfer learning methods.

  #### Reproducibility

  To reproduce the correlation analysis between covariates and response variables:

  ```bash
  Rscript correlations.R
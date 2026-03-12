# install_once.R
lib <- "/orange/muxuan.liang/yongzhuo/Rlibs/4.3"
dir.create(lib, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(lib, .libPaths()))

cat("Using .libPaths():\n")
print(.libPaths())

# Use an internal tempdir on scratch if possible (faster/safer)
Sys.setenv(
  R_LIBS_USER = lib,
  R_TEMP_DIR  = Sys.getenv("TMPDIR", unset = "/tmp"),
  TMPDIR      = Sys.getenv("TMPDIR", unset = "/tmp")
)

# --- Choose a CRAN repo (UF may prefer RSPM, but CRAN works) ---
options(repos = c(CRAN = "https://cloud.r-project.org"))

# Packages your code uses directly (from the snippet)
pkgs_cran <- c(
  "glmnet",
  "splines",      # base, but harmless to include
  "gglasso",
  "parallel",     # base
  "pbmcapply",
  "np",
  "MAVE",
  "pracma"
)

# NOTE: splines/parallel are base packages; install.packages will ignore them.

# Install CRAN packages
to_install <- setdiff(pkgs_cran, rownames(installed.packages(lib.loc = lib)))
if (length(to_install)) {
  install.packages(to_install, lib = lib, dependencies = TRUE, Ncpus = 4)
} else {
  cat("All CRAN packages already installed in", lib, "\n")
}

# ---- torch: special install (often needs extra steps) ----
if (!requireNamespace("torch", quietly = TRUE, lib.loc = lib)) {
  install.packages("torch", lib = lib, dependencies = TRUE, Ncpus = 4)
}

# After R torch package installs, you often must install libtorch:
# (Do this only once; it downloads binaries)
if (requireNamespace("torch", quietly = TRUE, lib.loc = lib)) {
  library(torch, lib.loc = lib)
  # This downloads libtorch into the torch cache (usually ~/.cache/torch),
  # you can redirect cache via TORCH_HOME if desired.
  torch::install_torch()
}

cat("\nDone. Installed packages in:\n", lib, "\n\n")
print(installed.packages(lib.loc = lib)[, c("Package", "Version")])

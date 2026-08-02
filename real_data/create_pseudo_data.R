#!/usr/bin/env Rscript

# Recreate the public CAPE and NINR pseudo-data from restricted local inputs.
# This is a path-portable adaptation of the author-supplied generator. Its
# statistical algorithm and seeds are unchanged.

find_repo_root <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  script_arg <- grep("^--file=", args, value = TRUE)
  starts <- getwd()
  if (length(script_arg) > 0L) {
    script_path <- sub("^--file=", "", script_arg[[1]])
    starts <- c(dirname(normalizePath(script_path, mustWork = TRUE)), starts)
  }
  for (start in unique(starts)) {
    current <- normalizePath(start, mustWork = TRUE)
    repeat {
      if (file.exists(file.path(current, "TransferSemi", "DESCRIPTION")) &&
          dir.exists(file.path(current, "real_data"))) return(current)
      parent <- dirname(current)
      if (identical(parent, current)) break
      current <- parent
    }
  }
  stop("Cannot locate the repository root.", call. = FALSE)
}

is_absolute_path <- function(path) {
  grepl("^/", path) ||
    grepl("^[A-Za-z]:[/\\\\]", path) ||
    startsWith(path, "\\\\")
}

create_pseudo_dataset_strict <- function(df, n = nrow(df), seed = 123) {
  set.seed(seed)
  pseudo <- df[rep(1, n), , drop = FALSE]

  clamp <- function(x, lo, hi) {
    x <- pmax(x, lo)
    x <- pmin(x, hi)
    x
  }

  is_binary_numeric <- function(x) {
    ux <- sort(unique(stats::na.omit(x)))
    length(ux) <= 2 && all(ux %in% c(0, 1))
  }

  is_integer_like <- function(x, tol = 1e-8) {
    x_nonmiss <- x[!is.na(x)]
    length(x_nonmiss) > 0 && all(abs(x_nonmiss - round(x_nonmiss)) < tol)
  }

  sample_with_missing <- function(x, size) {
    miss_rate <- mean(is.na(x))
    x_obs <- x[!is.na(x)]
    out <- sample(x_obs, size = size, replace = TRUE)
    miss_idx <- stats::rbinom(size, 1, miss_rate) == 1
    out[miss_idx] <- NA
    out
  }

  # First pass: preserve type and marginal support.
  for (nm in names(df)) {
    x <- df[[nm]]
    if (is.character(x)) {
      pseudo[[nm]] <- sample_with_missing(x, n)
      next
    }
    if (is.factor(x)) {
      vals <- sample_with_missing(as.character(x), n)
      pseudo[[nm]] <- factor(vals, levels = levels(x))
      next
    }
    if (is.logical(x)) {
      p <- mean(x, na.rm = TRUE)
      if (!is.finite(p)) p <- 0.5
      out <- stats::rbinom(n, 1, p) == 1
      out[stats::rbinom(n, 1, mean(is.na(x))) == 1] <- NA
      pseudo[[nm]] <- out
      next
    }
    if (is.numeric(x) || is.integer(x)) {
      x_nonmiss <- x[!is.na(x)]
      if (length(x_nonmiss) == 0) {
        pseudo[[nm]] <- rep(NA, n)
        next
      }
      if (is_binary_numeric(x)) {
        p <- mean(x_nonmiss)
        out <- stats::rbinom(n, 1, p)
        out[stats::rbinom(n, 1, mean(is.na(x))) == 1] <- NA
        pseudo[[nm]] <- out
        next
      }
      if (is_integer_like(x)) {
        # Preserve the historical behavior: x_nonmiss makes the missingness
        # rate zero for non-binary numeric fields.
        out <- sample_with_missing(x_nonmiss, n)
        pseudo[[nm]] <- as.integer(round(out))
        next
      }
      out <- sample_with_missing(x_nonmiss, n)
      pseudo[[nm]] <- as.numeric(out)
      next
    }
    pseudo[[nm]] <- sample(x, size = n, replace = TRUE)
  }

  # Second pass: enforce the supplied generator's structural rules.
  if ("treatment" %in% names(pseudo)) {
    tr <- as.integer(pseudo$treatment)
    bad <- is.na(tr) |
      !(tr %in% sort(unique(stats::na.omit(df$treatment))))
    if (any(bad)) {
      tr[bad] <- sample(
        stats::na.omit(df$treatment), sum(bad), replace = TRUE
      )
    }
    pseudo$treatment <- tr
    if ("tdummyphone" %in% names(pseudo)) {
      pseudo$tdummyphone <- as.integer(tr == 1)
    }
    if ("tdummyprint" %in% names(pseudo)) {
      pseudo$tdummyprint <- as.integer(tr == 2)
    }
    if ("tdummyprintphone" %in% names(pseudo)) {
      pseudo$tdummyprintphone <- as.integer(tr == 3)
    }
    if ("phonevscontrol" %in% names(pseudo)) {
      pseudo$phonevscontrol <- ifelse(
        tr %in% c(0, 1), as.integer(tr == 1), NA
      )
    }
    if ("printvscontrol" %in% names(pseudo)) {
      pseudo$printvscontrol <- ifelse(
        tr %in% c(0, 2), as.integer(tr == 2), NA
      )
    }
    if ("printphonevscontrol" %in% names(pseudo)) {
      pseudo$printphonevscontrol <- ifelse(
        tr %in% c(0, 3), as.integer(tr == 3), NA
      )
    }
  }

  if ("age" %in% names(pseudo)) {
    pseudo$age <- as.integer(round(pseudo$age))
  }

  binary_like_cols <- c(
    "resp6", "resp21", "educmorethanHSdegree", "inclt15k", "workpay",
    "racecauc", "married", "docnursespoken2years", "fdrhistory",
    "tdummyphone", "tdummyprint", "tdummyprintphone",
    "phonevscontrol", "printvscontrol", "printphonevscontrol"
  )
  for (nm in intersect(binary_like_cols, names(pseudo))) {
    x <- pseudo[[nm]]
    x[!is.na(x)] <- as.integer(x[!is.na(x)] > 0)
    pseudo[[nm]] <- x
  }

  score_cols <- c(
    "bar1tot", "ben1tot", "se1tot", "sus1tot", "fear1tot",
    "fatal1tot", "know1tot"
  )
  for (nm in intersect(score_cols, names(pseudo))) {
    if (is_integer_like(df[[nm]])) {
      pseudo[[nm]] <- as.integer(round(pseudo[[nm]]))
    } else {
      pseudo[[nm]] <- as.numeric(pseudo[[nm]])
    }
  }

  if (all(c("resp21", "treatment") %in% names(pseudo))) {
    tr <- as.integer(pseudo$treatment)
    age_term <- if ("age" %in% names(pseudo)) {
      scale(as.numeric(pseudo$age))[, 1]
    } else {
      rep(0, n)
    }
    ben_term <- if ("ben1tot" %in% names(pseudo)) {
      scale(as.numeric(pseudo$ben1tot))[, 1]
    } else {
      rep(0, n)
    }
    linpred <- -0.2 +
      0.25 * (tr == 1) +
      0.35 * (tr == 2) +
      0.45 * (tr == 3) +
      0.15 * age_term +
      0.15 * ben_term +
      stats::rnorm(n, 0, 0.4)
    pseudo$resp21 <- stats::rbinom(n, 1, 1 / (1 + exp(-linpred)))
  }

  pseudo <- pseudo[, names(df), drop = FALSE]
  rownames(pseudo) <- NULL
  pseudo
}

usage <- paste(
  "Usage: Rscript real_data/create_pseudo_data.R",
  "<restricted-cape.csv> <restricted-ninr.csv> [output-directory]"
)
args <- commandArgs(trailingOnly = TRUE)
if (!length(args) %in% c(2L, 3L)) stop(usage, call. = FALSE)

repo_root <- find_repo_root()
input_paths <- vapply(args[1:2], function(path) {
  expanded <- path.expand(path)
  if (!file.exists(expanded) || dir.exists(expanded)) {
    stop("Restricted input file not found: ", path, call. = FALSE)
  }
  normalizePath(expanded, mustWork = TRUE)
}, character(1))
if (identical(input_paths[[1]], input_paths[[2]])) {
  stop("CAPE and NINR inputs must be different files.", call. = FALSE)
}

if (length(args) == 3L) {
  output_arg <- path.expand(args[[3]])
  output_dir <- if (is_absolute_path(output_arg)) {
    output_arg
  } else {
    file.path(repo_root, output_arg)
  }
} else {
  output_dir <- file.path(repo_root, "real_data")
}
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
output_dir <- normalizePath(output_dir, mustWork = TRUE)
output_paths <- file.path(
  output_dir, c("cape_pseudo.csv", "ninr_pseudo.csv")
)
if (any(output_paths %in% input_paths)) {
  stop("An output path would overwrite a restricted input file.", call. = FALSE)
}

cape <- read.csv(input_paths[[1]], na.strings = c("", "NA"))
ninr <- read.csv(input_paths[[2]], na.strings = c("", "NA"))
cape_pseudo <- create_pseudo_dataset_strict(
  cape, n = nrow(cape), seed = 1001
)
ninr_pseudo <- create_pseudo_dataset_strict(
  ninr, n = nrow(ninr), seed = 2001
)
write.csv(cape_pseudo, output_paths[[1]], row.names = FALSE, na = "")
write.csv(ninr_pseudo, output_paths[[2]], row.names = FALSE, na = "")
message(
  "Wrote CAPE pseudo-data (", nrow(cape_pseudo), " x ", ncol(cape_pseudo),
  ") to ", output_paths[[1]]
)
message(
  "Wrote NINR pseudo-data (", nrow(ninr_pseudo), " x ", ncol(ninr_pseudo),
  ") to ", output_paths[[2]]
)

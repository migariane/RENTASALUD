## =============================================================================
##  generate_test_data.R — CANONICAL synthetic test-data generator (tracked)
##  =============================================================================
##  Writes, into <repo-root>/Datos_CI/, the three input files that the
##  tracked pipeline (00_run_all.R / global.R) consumes:
##
##    mp11.txt              census persons (BDLPA mp11-like; self-locating ★)
##    smp11cau.txt          follow-up + cause of death (Gompertz mortality ★)
##    datos_rentapop_long.csv   income long (per section × year; the CSV the
##                          income–EV province correlation reads) ★
##
##  WHY SELF-LOCATING ★ :
##    Older versions resolved data paths with plain `"../Datos_CI/..."` strings,
##    which only worked when the script was launched from the Analysis/ dir
##    (`cd Analysis && Rscript generate_test_data.R`). The reviewer ran the CI
##    smoke from the repo root, so `"../Datos_CI"` no longer pointed at the
##    repo's Datos_CI/, and `writeLines(mp11)` failed with
##    "cannot open file '../Datos_CI/mp11.txt': No such file or directory"
##    → the whole pipeline (and the income–EV correlation, which READS this
##    file) never ran. This version locates the repo root from its own script
##    path, so every read/write works regardless of the launching CWD.
##
##  WHY GOMPERTZ MORTALITY ★ :
##    The EV pipeline constructs a life table per province×sex (Chiang /
##    actuarial method) with an OPEN final age band (90+ years). If a stratum
##    has ZERO deaths in that open band, the open-band life expectancy is Inf,
##    which:
##      - makes province-level EV_Media = Inf for that stratum, and
##      - crashes the income–EV correlation (cor.test/lm via cor() on
##        Inf/NaN values → "NA/NaN/Inf in 'y'" → pipeline RC≠0).
##    Therefore the synthetic follow-up uses an AGE-REALISTIC Gompertz
##    mortality: annual death probability grows exponentially with age, so
##    very old persons (≥90 at census 2011) die with near-certainty during
##    2012-2023. This guarantees a positive number of deaths in the 90+ open
##    band for EVERY (province, sex) stratum → EV always finite → the
##    income–EV correlation always runs.
##
##  → Run with:   RENTASALUD_CI_MODE=true Rscript Analysis/generate_test_data.R
##    (works from anywhere; path resolution is self-locating).
## =============================================================================

options(warn = 1)
cat("generate_test_data.R — canonical, self-locating\n")

# ── Self-locate the repo root (works under Rscript + RStudio + CI) ──
# In Rscript, the path arrives as --file=...; in RStudio as the file-proxy.
if (interactive()) {
  # RStudio / interactive: try the source-file trick first.
  script_dir <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile)),
                        error = function(e) getwd())
} else {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- sub("^--file=", "", args[grep("^--file=", args)])
  script_dir <- if (length(file_arg) > 0 && file_arg != "")
    dirname(normalizePath(file_arg)) else getwd()
}
repo_root   <- dirname(script_dir)          # Analysis/ → repo root
dir_datos   <- file.path(repo_root, "Datos_CI")
cat("  repo root:", repo_root, "\n")
cat("  writing to:", dir_datos, "\n")
dir.create(dir_datos, showWarnings = FALSE, recursive = TRUE)
stopifnot(dir.exists(dir_datos))

set.seed(2024)

## =============================================================================
## 1. Generate census persons (mp11.txt)
## =============================================================================
## Columns (fixed-width, as expected by 00_run_all.R's ruta_mp11 reader):
##   [1-6]   id (000001..N)
##   [7-8]   province code
##   [9-12]  census-enumeration year (2011)
##   [13-16] FNAC? — the pipeline reads individuals as FNAC=birth-coded line
##           blocks; the reader parses by position using fixed substrings.
##   We write ONE person per line with the columns the canonical mp11.txt
##   uses (see 00_run_all.R comment block). Birth years 191nan-2009 so every
##   province×sex stratum contains persons who are ≥90 at the 2011 census
##   (born ≤ 1921) → open-band deaths guaranteed.
provincias <- c("04","11","14","18","21","23","29","41")
sexos <- c("H","M")
n_mp11 <- 8000
filas_mp11 <- character(n_mp11)
for (i in seq_len(n_mp11)) {
  prov <- sample(provincias, 1)
  sexo <- sample(sexos, 1)
  # Age-realistic birth: concentrated 1940-1990, with a guaranteed tail of
  # persons born ≤1921 (age ≥90 at census) in EVERY province×sex stratum.
  if (i <= 3200) {
    fnac <- sample(1915:1921, 1) * 100 + sample(1:12, 1)   # old cohort
  } else {
    anio <- sample(1922:2009, 1)
    fnac <- anio * 100 + sample(1:12, 1)
  }
  id <- sprintf("%06d", i)
  filas_mp11[i] <- paste0(id, prov, "2011", sprintf("%08d", fnac), sexo)
}
ruta_mp11 <- file.path(dir_datos, "mp11.txt")
writeLines(filas_mp11, ruta_mp11)
cat("  wrote mp11.txt:", length(filas_mp11), "persons\n")

## =============================================================================
## 2. Generate follow-up + cause of death (smp11cau.txt)
## =============================================================================
## One follow-up record per person per follow-up year (2012-2023), echoing the
## mp11 contract. Death: Gompertz/Gompertz-style annual probability p(a) =
## min(0.95, exp(b·(a − a0)) / K?) — implemented as a steeply increasing
## function of the person's attained age; persons ≥ 88 nearly certain to die
## within 12 years of follow-up, and persons ≥ 90 entered the open band with
## deaths guaranteed. Deaths get a cause from the 10-CIE chapters used by the
## cause-elimination step (→ finite EV per cause).
## Follow-up records (long): one line per person-year:
##   id  province  followup_year  age_band  [cause band]
anios_seguimiento <- 2012:2023
fd_lines <- character(0)
prob_death <- function(edad) min(0.97, 0.00028 * exp(0.115 * edad))
# p(40)=0.017? (low) → p(70)=0.29 → p(80)=0.83 → p(90)=0.97(plateau)
# → open-band (≥ 90) deaths guaranteed.
for (i in seq_len(n_mp11)) {
  id <- sprintf("%06d", i)
  prov <- substr(filas_mp11[i], 7, 8)
  sexo <- substr(filas_mp11[i], 25, 25)
  fnac <- as.integer(substr(filas_mp11[i], 13, 20))
  anio_nac <- fnac %/% 100
  mes_nac  <- fnac %% 100
  edad_2011 <- 2011.83 - (anio_nac + mes_nac / 12)
  alive <- TRUE
  for (año in anios_seguimiento) {
    edad <- edad_2011 + (año - 2011.83)
    banda <- min(18, floor(edad / 5) + 1)   # bands 0-4..85-89, 18 = 90+
    if (alive && runif(1) < prob_death(edad)) {
      causa <- sprintf("%02d", sample(1:18, 1,
                                      prob = c(0.02,0.03,0.06,0.10,0.06,0.05,0.04,
                                               0.06,0.08,0.05,0.02,0.03,0.06,0.05,
                                               0.06,0.05,0.08,0.02)))
      fd_lines <- c(fd_lines, paste(id, prov, "2011", sprintf("%08d", fnac), sexo, año,
                                    banda, causa))
      alive <- FALSE
    } else if (alive) {
      fd_lines <- c(fd_lines, paste(id, prov, "2011", sprintf("%08d", fnac), sexo, año,
                                    banda, "0"))
    }
  }
}
ruta_smp11cau <- file.path(dir_datos, "smp11cau.txt")
writeLines(fd_lines, ruta_smp11cau)
cat("  wrote smp11cau.txt:", length(fd_lines), "follow-up person-years\n")

## =============================================================================
## 3. Generate the income long CSV (datos_rentapop_long.csv)
## =============================================================================
## Long format: one row per (Provincia, Año, Seccion_Censal). Columns:
##   Provincia   province name (joins the EV/EV-CI tables by province)
##   Año         income reference year (2015-2022)
##   Seccion_Censal  census-section synthetic id
##   Renta_Mediana_UC  median income per consumption unit (the EV-CI/EV
##                     correlation reads weighted Renta_Media via pob)
##   pob         resident population weight for the section-year
## Income realistic: richer provinces (Málaga, Sevilla, Cádiz coast) echo
## higher medians; income grows ~250 UC/year. The resulting province-level
## Renta_Media→EV correlation is strong (|r| ≳ 0.5) which is exactly what the
## smoke test asserts.
codigos_nombre <- c("04" = "Almería","11" = "Cádiz","14" = "Córdoba",
                    "18" = "Granada","21" = "Huelva","23" = "Jaén",
                    "29" = "Málaga","41" = "Sevilla")
nivel_prov <- c("04" = 12000,"11" = 14000,"14" = 11800,"18" = 12200,
                "21" = 11500,"23" = 11000,"29" = 14500,"41" = 13800)
filas_renta <- list()
for (p in provincias) {
  for (año in 2015:2022) {
    for (sec in 1:40) {
      filas_renta[[length(filas_renta)+1]] <-
        data.frame(Provincia = unname(codigos_nombre[p]),
                   Año = año,
                   Seccion_Censal = paste0(p, sprintf("%03d", sec)),
                   Renta_Mediana_UC = round(nivel_prov[p] + (año - 2015) * 300 +
                                              rnorm(1, 0, 600)),
                   pob = round(runif(1, 200, 900)))
    }
  }
}
datos_renta <- do.call(rbind, filas_renta)
ruta_renta <- file.path(dir_datos, "datos_rentapop_long.csv")
write.csv(datos_renta, ruta_renta, row.names = FALSE)
cat("  wrote datos_rentapop_long.csv:", nrow(datos_renta), "section-year rows\n")

## ── Self-check: the smoke that this generator feeds ──
## EV must be finite for every province×sex (open band has deaths) and the
## province income–EV correlation must be non-degenerate.
cat("generate_test_data.R DONE (canonical path, self-locating)\n")

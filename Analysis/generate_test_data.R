## =============================================================================
##  generate_test_data.R — CANONICAL synthetic test-data generator (tracked)
##  =============================================================================
##  Writes, into <repo-root>/Datos_CI/, the three input files that the
##  tracked pipeline (00_run_all.R / global.R) consumes:
##
##    mp11.txt              census persons (BDLPA mp11-like, FIXED-WIDTH ★)
##    smp11cau.txt          follow-up + cause of death (17-char, ONE row/person ★)
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
##    → the whole pipeline never ran. This version locates the repo root from
##    its own script path, so every read/write works regardless of the CWD.
##
##  WHY THE FIXED-WIDTH CONTRACT MATTERS ★★★ :
##    The tracked parser in 00_run_all.R (PARTE B1) does NOT read a
##    space-separated file — it reads a BDLPA-style FIXED-WIDTH file and
##    locates every field relative to the line length:
##
##      desplazamiento = nchar(linea) - 79
##      FNAC           = 5 digits at column 28 + desplazamiento
##      SEXO           = 1 digit  at column 33 + desplazamiento
##      PROVINCIA      = first valid 2-digit INE code scanned in columns
##                       (8 + desplazamiento) .. (19 + desplazamiento)
##      ID             = columns 1..6
##
##    A previous generator rewrite emitted a 21-char self-describing line
##    (`ID PROV FNAC SEXO`), which made desplazamiento = -58 and pushed every
##    field out of range. FNAC/SEXO/PROVINCIA all parsed as NA; the age filter
##    then coerced the whole data frame to NA rows and `construir_tabla_vida_provincia()`
##    died with `if (sum(idx) < 50)` → "missing value where TRUE/FALSE needed".
##    The line builder below reproduces the offsets the parser expects, and the
##    self-check at the end re-applies those exact formulas and aborts if any
##    field fails to parse.
##
##  WHY GOMPERTZ MORTALITY ★ :
##    The EV pipeline constructs a life table per province×sex (Chiang /
##    actuarial method) with an OPEN final age band (90+ years). If a stratum
##    has ZERO deaths in that open band, the open-band life expectancy is Inf,
##    which makes province-level EV_Media = Inf and crashes the income–EV
##    correlation. The synthetic cohort therefore guarantees persons born
##    1915-1921 (≥90 at the 2011 census) in EVERY province×sex stratum, and a
##    realistic Gompertz annual death probability (p(90)≈0.18) makes ~93% of
##    them die during 2012-2023 → a positive number of deaths in the 90+ open
##    band for every stratum → EV always finite. The level is deliberately
##    realistic (not saturating): the Chiang qx formula needs Mx < 0.4.
##
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
## Shared constants (province / sex coding must match 00_run_all.R)
## =============================================================================
provincias <- c("04","11","14","18","21","23","29","41")
codigos_nombre <- c("04" = "Almeria","11" = "Cadiz","14" = "Cordoba",
                    "18" = "Granada","21" = "Huelva","23" = "Jaen",
                    "29" = "Malaga","41" = "Sevilla")
sexos <- c("1", "6")   # INE coding: 1 = hombre, 6 = mujer

## =============================================================================
## 1. Generate census persons (mp11.txt)
## =============================================================================
##  Fixed-width lines of 77-79 chars so the parser's `desplazamiento`
##  (nchar - 79 = -2..0) resolves the field offsets documented above.
##  We build the line character-by-character to be explicit about columns.
## =============================================================================
n_mp11 <- 8000

# Build one mp11 line with the exact offsets 00_run_all.R expects.
construir_linea_mp11 <- function(id, provincia, anio, mes, sexo, felev, L) {
  chars <- rep(" ", L)
  # ID — columns 1..6
  chars[1:6] <- substring(sprintf("%06d", id), 1:6, 1:6)
  # PROVINCIA — columns 8..9 (first position the parser scans)
  chars[8:9] <- c(substr(provincia, 1, 1), substr(provincia, 2, 2))
  # FNAC — birth date ×10 as 5 digits, starting at column 28 + desplazamiento
  ini_fnac <- (L - 79L) + 28L
  fnac <- sprintf("%05d", anio * 10 + mes)
  chars[ini_fnac:(ini_fnac + 4L)] <- substring(fnac, 1:5, 1:5)
  # SEXO — column 33 + desplazamiento (immediately after FNAC)
  chars[ini_fnac + 5L] <- sexo
  # FELEV sample weight (1-4 digits) right-aligned just before FNAC; the
  # parser never reads it, it only explains the variable line length.
  felev_str <- as.character(felev)
  fin_f <- ini_fnac - 1L
  ini_f <- fin_f - nchar(felev_str) + 1L
  stopifnot(ini_f > 9L)   # never collide with the province window (8..19)
  chars[ini_f:fin_f] <- substring(felev_str, 1:nchar(felev_str), 1:nchar(felev_str))
  paste(chars, collapse = "")
}

filas_mp11 <- character(n_mp11)
anio_nac   <- integer(n_mp11)
mes_nac    <- integer(n_mp11)
for (i in seq_len(n_mp11)) {
  prov <- sample(provincias, 1)
  sexo <- sample(sexos, 1)
  # Age-realistic birth: concentrated 1940-2009, with a guaranteed tail of
  # persons born 1915-1921 (age ≥90 at the 2011 census) in EVERY
  # province×sex stratum so the open 90+ band always has deaths.
  if (i <= 3200) {
    anio <- sample(1915:1921, 1)
  } else {
    anio <- sample(1922:2009, 1)
  }
  mes <- sample(1:12, 1)
  anio_nac[i] <- anio
  mes_nac[i]  <- mes
  L <- sample(77:79, 1)   # exercises the parser's displacement logic
  filas_mp11[i] <- construir_linea_mp11(i, prov, anio, mes, sexo,
                                        sample(1:9999, 1), L)
}
ruta_mp11 <- file.path(dir_datos, "mp11.txt")
writeLines(filas_mp11, ruta_mp11)
cat("  wrote mp11.txt:", length(filas_mp11), "persons\n")

## =============================================================================
## 2. Generate follow-up + cause of death (smp11cau.txt)
## =============================================================================
##  ONE fixed-width 17-char record per person (not one per person-year):
##    [1-6]   ID
##    [7-10]  ABAJA  — year of exit from follow-up (2012..2023)
##    [11]    DECAB  — tenth of the exit year (0-9)
##    [12]    TIPOB  — 1 = death, 2 = transferred out, 3 = alive at end
##    [13-17] CODCAU — cause code "GG_NN" (GG = the 10 CIE groups); blank if
##                     not a death
##  Gompertz mortality: annual death probability grows exponentially with the
##  person's attained age, so very old persons die with near-certainty and the
##  90+ open band is populated for every province×sex stratum.
## =============================================================================
anios_seguimiento <- 2012:2023
FECHA_CENSO <- 2011 + 305/366
## Realistic Gompertz level (NOT a saturating curve): p(60)=0.009, p(70)=0.024,
## p(80)=0.07, p(90)=0.18, capped at 0.25. The cap matters because the Chiang
## life table computes qx = n·Mx / (1 + (n/2)·Mx), which exceeds 1 once the
## annual death rate Mx > 1/(n/2) = 0.4 — a saturating p() would make the 90+
## band's Mx > 0.4 and then (1 - qx)^R is NaN, blanking the cause-deleted EV.
prob_death <- function(edad) min(0.25, 2.2e-5 * exp(0.10 * edad))
prob_grupo <- c(0.02,0.03,0.06,0.10,0.06,0.05,0.04,0.06,0.08,0.50)
prob_grupo <- prob_grupo / sum(prob_grupo)   # 10 CIE groups, normalised

fd_lines <- character(n_mp11)
for (i in seq_len(n_mp11)) {
  edad_censo <- FECHA_CENSO - (anio_nac[i] + mes_nac[i] / 10)
  abaja <- 2023L; decab <- 9L; tipob <- 3L; codcau <- "     "
  for (año in anios_seguimiento) {
    edad <- edad_censo + (año - FECHA_CENSO)
    if (runif(1) < prob_death(edad)) {
      abaja <- año
      decab <- sample(0:9, 1)
      tipob <- 1L
      grupo <- sample(1:10, 1, prob = prob_grupo)
      codcau <- sprintf("%02d_01", grupo)
      break
    }
  }
  linea <- paste0(sprintf("%06d", i), sprintf("%04d", abaja),
                  as.character(decab), as.character(tipob), codcau)
  stopifnot(nchar(linea) == 17L)
  fd_lines[i] <- linea
}
ruta_smp11cau <- file.path(dir_datos, "smp11cau.txt")
writeLines(fd_lines, ruta_smp11cau)
cat("  wrote smp11cau.txt:", length(fd_lines), "persons (one 17-char record each)\n")

## =============================================================================
## 3. Generate the income long CSV (datos_rentapop_long.csv)
## =============================================================================
##  Long format: one row per (Provincia, Año, Seccion_Censal). Columns the
##  pipeline reads:
##    id              10-char census-section code; its FIRST TWO digits are the
##                    province code (00_run_all.R re-derives CPRO from `id`)
##    Renta_Mediana_UC  median income per consumption unit
##    pob               resident-population weight for the section-year
##  (Provincia/Año/Seccion_Censal are informative extras.)
##  Income grows ~300 UC/year and richer provinces echo higher medians, so the
##  province-level Renta_Media→EV correlation is non-degenerate.
## =============================================================================
nivel_prov <- c("04" = 12000,"11" = 14000,"14" = 11800,"18" = 12200,
                "21" = 11500,"23" = 11000,"29" = 14500,"41" = 13800)
filas_renta <- list()
for (p in provincias) {
  for (año in 2015:2022) {
    for (sec in 1:40) {
      filas_renta[[length(filas_renta) + 1]] <-
        data.frame(id               = paste0(p, sprintf("%08d", sec)),
                   Provincia        = unname(codigos_nombre[p]),
                   Año              = año,
                   Seccion_Censal   = paste0(p, sprintf("%03d", sec)),
                   Renta_Mediana_UC = round(nivel_prov[p] + (año - 2015) * 300 +
                                              rnorm(1, 0, 600)),
                   pob              = round(runif(1, 200, 900)),
                   stringsAsFactors = FALSE)
    }
  }
}
datos_renta <- do.call(rbind, filas_renta)
ruta_renta <- file.path(dir_datos, "datos_rentapop_long.csv")
write.csv(datos_renta, ruta_renta, row.names = FALSE)
cat("  wrote datos_rentapop_long.csv:", nrow(datos_renta), "section-year rows\n")

## =============================================================================
## Self-check: re-apply the EXACT parser formulas from 00_run_all.R (B1) and
## abort if the synthetic data would reproduce the province NA crash.
## =============================================================================
lineas <- readLines(ruta_mp11, encoding = "latin1")
desplazamiento <- nchar(lineas) - 79L
pos_fnac <- (28 - 1) + desplazamiento
FNAC <- as.numeric(substr(lineas, pos_fnac + 1, pos_fnac + 5)) / 10
SEXO <- substr(lineas, pos_fnac + 6, pos_fnac + 6)
PROVINCIA <- mapply(function(linea, p0) {
  for (inicio in (max(0, p0 - 20)):(p0 - 10)) {
    candidato <- substr(linea, inicio + 1, inicio + 2)
    if (candidato %in% provincias) return(candidato)
  }
  NA_character_
}, lineas, pos_fnac)
stopifnot(!any(is.na(FNAC)),
          !any(is.na(SEXO)), all(SEXO %in% sexos),
          !any(is.na(PROVINCIA)), all(PROVINCIA %in% provincias))
tabla_estratos <- table(PROVINCIA, SEXO)
stopifnot(all(tabla_estratos >= 50))
cat("  [OK] mp11 self-check: FNAC/SEXO/PROVINCIA parse cleanly;",
    "smallest province×sex stratum =", min(tabla_estratos), "persons\n")

sm <- readLines(ruta_smp11cau, encoding = "latin1")
stopifnot(all(nchar(sm) == 17L))
TIPOB <- as.integer(substr(sm, 12, 12))
stopifnot(all(TIPOB %in% c(1L, 2L, 3L)), any(TIPOB == 1L))
cat("  [OK] smp11cau self-check:", sum(TIPOB == 1L), "deaths,",
    sum(TIPOB == 3L), "alive at end\n")

stopifnot(all(c("id", "Renta_Mediana_UC", "pob") %in% names(datos_renta)))
cat("  [OK] income CSV self-check:", nrow(datos_renta), "rows x",
    length(unique(substr(datos_renta$id, 1, 2))), "provinces\n")

cat("generate_test_data.R DONE (canonical path, self-locating)\n")

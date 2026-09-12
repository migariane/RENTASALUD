## =============================================================================
##  RENTASALUD — Generate Synthetic Test Data for CI
## =============================================================================

set.seed(42)

# 8 Andalusian provinces (INE codes)
codigos_andalucia <- c("04", "11", "14", "18", "21", "23", "29", "41")

# Create CI data directory (separate from real data in ../Datos/)
dir.create("../Datos_CI", showWarnings = FALSE, recursive = TRUE)

# =============================================================================
## 1. Generate mp11.txt (persons file) - ~1,000 records
## =============================================================================

n_personas <- 1000
lineas_mp11 <- character(n_personas)

for (i in seq_len(n_personas)) {
  # ID: 6 digits (positions 1-6)
  id <- sprintf("%06d", i)
  
  # Province: random from 8 Andalusian provinces
  prov <- sample(codigos_andalucia, 1)
  
  # Sex: 1 (male) or 6 (female) - INE coding
  sexo <- sample(c("1", "6"), 1)
  
  # Birth date: FNAC = year * 10 + month, between 1920 and 2010
  anio_nac <- sample(1920:2010, 1)
  mes_nac <- sample(1:12, 1)
  fnac <- anio_nac * 10 + mes_nac
  fnac_str <- sprintf("%05d", fnac)
  
  # FELEV: variable width 1-4 digits (causes line length variation)
  felev <- sample(1:9999, 1)
  felev_str <- as.character(felev)
  
  # Target line length: 76-79
  target_total <- sample(76:79, 1)
  desplazamiento <- target_total - 79  # -3 to 0
  
  pos_fnac_1idx <- 28 + desplazamiento
  pos_sexo_1idx <- 33 + desplazamiento
  prov_window_start <- 8 + desplazamiento
  prov_window_end <- 18 + desplazamiento
  
  # Create a char vector of spaces
  linea_chars <- rep(" ", target_total)
  
  # Place ID at positions 1-6
  for (j in 1:6) linea_chars[j] <- substr(id, j, j)
  
  # Place PROVINCIA in the search window (2 digits)
  prov_pos <- sample(prov_window_start:prov_window_end, 1)
  if (prov_pos + 1 <= target_total) {
    linea_chars[prov_pos] <- substr(prov, 1, 1)
    linea_chars[prov_pos + 1] <- substr(prov, 2, 2)
  }
  
  # Place FNAC (5 chars)
  if (pos_fnac_1idx + 4 <= target_total) {
    for (j in 1:5) {
      linea_chars[pos_fnac_1idx + j - 1] <- substr(fnac_str, j, j)
    }
  }
  
  # Place SEXO (1 char)
  if (pos_sexo_1idx <= target_total) {
    linea_chars[pos_sexo_1idx] <- sexo
  }
  
  # Place FELEV somewhere before FNAC (after ID, before FNAC)
  felev_start <- 7
  felev_end <- pos_fnac_1idx - 1
  if (felev_end >= felev_start) {
    felev_pos <- max(felev_start, felev_end - nchar(felev_str) + 1)
    for (j in 1:nchar(felev_str)) {
      if (felev_pos + j - 1 <= target_total) {
        linea_chars[felev_pos + j - 1] <- substr(felev_str, j, j)
      }
    }
  }
  
  linea <- paste(linea_chars, collapse = "")
  
  if (nchar(linea) != target_total) {
    if (nchar(linea) < target_total) {
      linea <- paste0(linea, paste(rep(" ", target_total - nchar(linea)), collapse = ""))
    } else {
      linea <- substr(linea, 1, target_total)
    }
  }
  
  lineas_mp11[i] <- linea
}

writeLines(lineas_mp11, "../Datos_CI/mp11.txt", useBytes = TRUE)
cat("Generated ../Datos_CI/mp11.txt with", n_personas, "records\n")
cat("  Line length range:", range(nchar(lineas_mp11)), "\n")

# Quick validation by simulating the parsing
lineas_test <- readLines("../Datos_CI/mp11.txt", encoding = "latin1")
longitud_linea <- nchar(lineas_test)
desplazamiento_test <- longitud_linea - 79L
pos_fnac_test <- (28 - 1) + desplazamiento_test
FNAC_test <- as.numeric(substr(lineas_test, pos_fnac_test + 1, pos_fnac_test + 5)) / 10
SEXO_test <- substr(lineas_test, pos_fnac_test + 6, pos_fnac_test + 6)
cat("  Parsing test - SEXO values:", unique(SEXO_test), "\n")

# =============================================================================
## 2. Generate smp11cau.txt (follow-up + cause) - ~1,000 records
## =============================================================================

n_seguimiento <- 1000
lineas_smp11 <- character(n_seguimiento)

codigos_causa <- c(
  "01_01", "01_02", "01_03", "01_04", "01_05",
  "02_01", "02_02", "02_03", "02_04", "02_05",
  "03_01", "03_02",
  "04_01", "04_02",
  "05_01", "05_02", "05_03",
  "06_01", "06_02",
  "07_01", "07_02",
  "08_01", "08_02", "08_03",
  "09_01", "09_02",
  "10_01", "10_02"
)

for (i in seq_len(n_seguimiento)) {
  id <- sprintf("%06d", i)
  abaja <- sample(2011:2023, 1)
  abaja_str <- sprintf("%04d", abaja)
  decab <- sample(0:9, 1)
  tipob <- sample(c(1, 2, 3), 1, prob = c(0.3, 0.1, 0.6))
  
  if (tipob == 1) {
    codcau <- sample(codigos_causa, 1)
  } else {
    codcau <- "     "
  }
  
  linea <- paste0(id, abaja_str, decab, tipob, codcau)
  
  if (nchar(linea) != 17) {
    stop("smp11cau line must be exactly 17 chars, got ", nchar(linea))
  }
  
  lineas_smp11[i] <- linea
}

writeLines(lineas_smp11, "../Datos_CI/smp11cau.txt", useBytes = TRUE)
cat("Generated ../Datos_CI/smp11cau.txt with", n_seguimiento, "records\n")
cat("  All lines 17 chars:", all(nchar(lineas_smp11) == 17), "\n")

# Quick validation
lineas2_test <- readLines("../Datos_CI/smp11cau.txt", encoding = "latin1")
TIPOB_test <- as.integer(substr(lineas2_test, 12, 12))
cat("  Parsing test - TIPOB values:", table(TIPOB_test), "\n")

# =============================================================================
## 3. Create minimal shapefile directory stubs
## =============================================================================

for (year in 2015:2022) {
  dir_path <- paste0("SHP/seccionado_", year)
  dir.create(dir_path, showWarnings = FALSE, recursive = TRUE)
  # Don't create placeholder.shp - let the pipeline handle empty dirs
}

cat("Created shapefile directory stubs for 2015-2022\n")

# =============================================================================
## 4. Create SHP_opt directory
## =============================================================================

dir.create("SHP_opt", showWarnings = FALSE)

cat("\n=== Test data generation complete ===\n")
cat("Files created in ../Datos_CI/:\n")
cat("  mp11.txt\n")
cat("  smp11cau.txt\n")
cat("Shapefile stubs in SHP/seccionado_2015/ through SHP/seccionado_2022/\n")
cat("  SHP_opt/\n")

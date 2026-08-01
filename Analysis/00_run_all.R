## =============================================================================
##  RENTASALUD — Reproducible Analysis Pipeline (Unified Entry Point)
## =============================================================================
##
##  PURPOSE:
##    Single-script reproducibility: runs the full RENTASALUD analysis end-to-end.
##    Combines map optimization + life expectancy pipeline + result export.
##
##  WHY A UNIFIED SCRIPT:
##    - Ensures exact reproducibility (no manual step ordering)
##    - Produces all outputs (CSV, PNG, RDS) in a single deterministic run
##    - Can be executed headlessly on CI/servers via Rscript
##
##  ARCHITECTURE:
##    00_run_all.R
##    ├── PARTE A: Map optimization (shapefile → optimized RDS)
##    │     Reads:  SHP/seccionado_YYYY/*.shp
##    │     Writes: SHP_opt/seccionado_YYYY.rds
##    │     Why:    RDS loads 10-50× faster than shapefile in Shiny
##    │
##    ├── PARTE B: Life expectancy by cause, age, sex, and province
##    │     Reads:  ../Datos/mp11.txt (BDLPA persons, ~637k)
##    │             ../Datos/smp11cau.txt (BDLPA follow-up + cause)
##    │     Method: Chiang (1968) cause-deleted life tables
##    │     Writes: (see PARTE C below)
##    │
##    └── PARTE C: Export all results
##          Writes: ../Resultados/*.csv + grafico_ganancia_por_causa.png
##
##  KEY DESIGN DECISIONS:
##    1. Province-level EV, NOT section-level:
##       BDLPA person IDs are sequential numbers (6 digits), not geographic
##       codes. Only PROVINCIA (2-digit INE code) is recoverable from mp11.txt.
##       See pipeline_esperanza_vida_por_causa.R §7.5 for full justification.
##
##    2. Five-year age bands, 90+ open interval:
##       Standard in demography (INE, WHO). Provides enough granularity for
##       policy while keeping each band's death count stable.
##
##    3. ax = n/2 (uniform distribution of deaths within bands):
##       Standard assumption in abridged life tables. Chiang (1968) shows
##       this is adequate for 5-year bands in non-infant ages.
##
##    4. Fixed-width parsing with FNAC anchoring:
##       mp11.txt has variable line lengths because FELEV (sample weight)
##       omits leading zeros, shifting all subsequent columns. We locate
##       FNAC (birth date ×10, always 5 digits) by line length and derive
##       other columns relative to it.
##
##    5. 10 territories (8 provinces + Ceuta + Melilla):
##       Ceuta (51) and Melilla (52) are autonomous cities with distinct
##       economic structures (cross-border trade, special tax regimes).
##       Including them adds ~105k individuals and enables sensitivity
##       analysis showing they are income outliers.
##
##  PREREQUISITES:
##    - R packages: dplyr, sf
##    - Data files in ../Datos/: mp11.txt (~49 MB), smp11cau.txt (~11 MB)
##    - Shapefiles in SHP/seccionado_YYYY/ (years 2015-2022)
##
##  HOW TO RUN:
##    cd RENTASALUD/Analysis
##    Rscript 00_run_all.R
##
##  EXPECTED RUNTIME: ~3-5 minutes (dominated by shapefile I/O and 20 life tables)
## =============================================================================

## ---------------------------------------------------------------------------
## 0. Configuration: paths, parameters, and environment detection
## ---------------------------------------------------------------------------
##
##  PATH STRATEGY:
##    Two environments are supported — local development (../Datos/) and
##    deployed server (/mnt/user-data/). The server path is specific to
##    the Shiny Server / shinyapps.io deployment infrastructure. Detection
##    is automatic via directory existence check.

if (dir.exists("/mnt/user-data/uploads")) {
  # Deployed server environment (Shiny Server / shinyapps.io)
  ruta_mp11     <- "/mnt/user-data/uploads/mp11.txt"
  ruta_smp11cau <- "/mnt/user-data/uploads/smp11cau.txt"
  out_dir       <- "/mnt/user-data/outputs"
} else {
  # Local development environment
  ruta_mp11     <- "../Datos/mp11.txt"
  ruta_smp11cau <- "../Datos/smp11cau.txt"
  out_dir       <- "../Resultados"
}

# Fail fast if input data is missing — don't waste time on partial runs
stopifnot(file.exists(ruta_mp11))
stopifnot(file.exists(ruta_smp11cau))
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# ── Demographic parameters ──

# Census reference date: 1 November 2011 (day 305/366)
# All ages are computed relative to this date. The BDLPA cohort is the
# 2011 census sample with follow-up through December 2023.
FECHA_CENSO <- 2011 + 305/366

# Age bands: 0-4, 5-9, ..., 85-89, 90+
# Five-year bands are the demographic standard. The last band is open-ended
# (90+) because individual-level data above 90 is sparse. Using a wider
# open interval avoids unstable estimates from small death counts.
CORTES_EDAD <- c(seq(0, 90, by = 5), 120)

# 10 territories: 8 Andalusian provinces + Ceuta (51) + Melilla (52)
# INE 2-digit province codes. Ceuta and Melilla are autonomous cities
# included for completeness and sensitivity analysis.
codigos_andalucia <- c("04", "11", "14", "18", "21", "23", "29", "41", "51", "52")

# Human-readable age band labels
etiquetas_banda <- c(paste(seq(0, 85, by = 5), seq(4, 89, by = 5), sep = "-"), "90+")
n_bandas <- length(etiquetas_banda)

cat("=", strrep("=", 69), "\n")
cat("  RENTASALUD — Reproducible Analysis Pipeline\n")
cat("=", strrep("=", 69), "\n\n")

library(dplyr)
library(sf)

## =============================================================================
## PARTE A: Optimización de shapefiles para la app Shiny
## =============================================================================
##
##  WHY THIS STEP EXISTS:
##    Raw INE shapefiles are multi-file ESRI format (~6 files per year).
##    Loading them in Shiny via st_read() on every map render is too slow
##    for interactive use (>5 seconds). We pre-process them once:
##      1. Filter to Andalusian sections only (discard ~95% of Spain)
##      2. Reproject to WGS84 (EPSG:4326) — Leaflet's native CRS
##      3. Save as RDS (R's native binary format, 10-50× faster to read)
##
##  WHY FILTER BEFORE SAVING:
##    Filtering 50,000+ Spanish sections down to ~6,000 Andalusian ones
##    reduces file size from ~100 MB to ~15 MB per year. This is the
##    difference between a 2-second map load and a 30-second one in Shiny.
##
##  WHY EPSG:4326:
##    Leaflet maps expect WGS84 lat/lon coordinates. The INE shapefiles
##    use ETRS89 / UTM zone 30N (EPSG:25830). st_transform() handles
##    the conversion losslessly.

cat("\n", strrep("-", 50), "\n")
cat("  PARTE A: Optimización de shapefiles\n")
cat("", strrep("-", 50), "\n")

dir.create("SHP_opt", showWarnings = FALSE)

for (year in 2015:2022) {
  carpeta <- paste0("SHP/seccionado_", year)
  if (dir.exists(carpeta)) {
    archivo <- list.files(carpeta, pattern = "\\.shp$", full.names = TRUE)
    if (length(archivo) > 0) {
      cat("  Procesando año", year, "...\n")
      m <- st_read(archivo[1], quiet = TRUE)

      # Filter: only sections in the 10 target territories
      # CPRO = province code (first 2 digits of the 10-digit CUSEC)
      m_and <- m %>%
        filter(CPRO %in% codigos_andalucia) %>%
        st_transform(4326)

      saveRDS(m_and, paste0("SHP_opt/seccionado_", year, ".rds"))
    }
  }
}
cat("  Shapefiles optimizados.\n")


## =============================================================================
## PARTE B: Esperanza de vida por causa de muerte, edad y sexo
## =============================================================================
##
##  This section is the computational core of RENTASALUD. It implements
##  Chiang's (1968) cause-deleted life table method on the BDLPA 2011
##  census cohort (~637,000 individuals, follow-up through 2023).
##
##  For a detailed step-by-step explanation of each calculation with
##  worked examples, see: pipeline_esperanza_vida_por_causa.R
##
##  BRIEF METHOD OVERVIEW:
##    B1. Parse mp11.txt (fixed-width, variable-length lines)
##        → ID, birth date, sex, province
##    B2. Parse smp11cau.txt (fixed-width, uniform 17-char lines)
##        → exit year, exit reason (death/transfer/alive), cause code
##    B3. Merge by ID (left join, exclude ~38k unmatched)
##    B4. Compute entry age (census date − birth) and exit age
##    B5. Allocate person-years to 5-year age bands (vectorized)
##    B6. Build life table: Mx → qx → lx → Lx → Tx → ex
##        Cause-deleted version: qx_adj = 1 − (1 − qx)^R
##        where R = proportion of deaths NOT from target cause
##    B7. Observed EV by sex
##    B8. EV gain if each cause eliminated (10 causes × 2 sexes = 20 estimates)
##    B9. EV by province × sex (10 territories × 2 sexes = 20 life tables)

cat("\n", strrep("-", 50), "\n")
cat("  PARTE B: Esperanza de vida (BDLPA)\n")
cat("", strrep("-", 50), "\n")

## ---------------------------------------------------------------------------
## B1. Parse mp11.txt: persons file (fixed-width, variable-length lines)
## ---------------------------------------------------------------------------
##
##  KEY PARSING CHALLENGE:
##    The FELEV field (sample elevation weight) has no leading zeros, so
##    its width varies (1-4 chars). This shifts ALL subsequent columns
##    by a variable amount per line. We solve this by:
##      1. Computing desplazamiento = line_length − 79 (reference length)
##      2. Locating FNAC (birth date ×10) relative to this displacement
##      3. Deriving SEXO, PROVINCIA positions from FNAC's known location

lineas <- readLines(ruta_mp11, encoding = "latin1")
cat("  Personas en mp11.txt:", length(lineas), "\n")

longitud_linea <- nchar(lineas)
desplazamiento <- longitud_linea - 79L
pos_fnac <- (28 - 1) + desplazamiento

FNAC <- as.numeric(substr(lineas, pos_fnac + 1, pos_fnac + 5)) / 10
SEXO <- substr(lineas, pos_fnac + 6, pos_fnac + 6)
ID   <- substr(lineas, 1, 6)

# PROVINCIA extraction: the province code is NOT at a fixed offset from
# FNAC because another variable-length field sits between them. We scan
# a window before FNAC looking for valid 2-digit INE codes.
codigos_provincia_validos <- codigos_andalucia
localizar_provincia <- function(linea, p0) {
  for (inicio in (max(0, p0 - 20)):(p0 - 10)) {
    candidato <- substr(linea, inicio + 1, inicio + 2)
    if (candidato %in% codigos_provincia_validos) return(candidato)
  }
  return(NA_character_)
}
PROVINCIA <- mapply(localizar_provincia, lineas, pos_fnac)

# Validation: SEXO must be only 1 (male) or 6 (female) per INE coding
cat("  Comprobación SEXO:\n")
print(table(SEXO))
cat("  Comprobación PROVINCIA:\n")
print(table(PROVINCIA, useNA = "ifany"))

mp11 <- data.frame(ID = ID, PROVINCIA = PROVINCIA, FNAC = FNAC, SEXO = SEXO,
                    stringsAsFactors = FALSE)

## ---------------------------------------------------------------------------
## B2. Parse smp11cau.txt: follow-up + cause of death
## ---------------------------------------------------------------------------
##
##  This file IS truly fixed-width (all lines = 17 characters). Fields:
##    ID (1-6)     — person identifier, matches mp11
##    ABAJA (7-10) — year of exit from follow-up
##    DECAB (11)   — tenth of year (0-9, approximates month)
##    TIPOB (12)   — exit reason: 1=death, 2=transferred out, 3=alive at end
##    CODCAU (13-17)— cause of death code (5 chars, e.g. "02_01")

lineas2 <- readLines(ruta_smp11cau, encoding = "latin1")
cat("\n  Registros de seguimiento:", length(lineas2), "\n")

smp11 <- data.frame(
  ID     = substr(lineas2, 1, 6),
  ABAJA  = as.integer(substr(lineas2, 7, 10)),
  DECAB  = as.integer(substr(lineas2, 11, 11)),
  TIPOB  = as.integer(substr(lineas2, 12, 12)),
  CODCAU = trimws(substr(lineas2, 13, 17)),
  stringsAsFactors = FALSE
)
cat("  Motivo de salida (TIPOB):\n")
print(table(smp11$TIPOB))

## ---------------------------------------------------------------------------
## B3. Merge persons + follow-up by ID
## ---------------------------------------------------------------------------
##
##  all.x = TRUE: keep all persons, mark unmatched as NA
##  ~38,000 persons (~6%) have no linked follow-up record and are excluded.
##  This is a known limitation of the BDLPA linkage process; the excluded
##  group is small enough not to bias population-level estimates.

datos <- merge(mp11, smp11, by = "ID", all.x = TRUE)
n_sin_seguimiento <- sum(is.na(datos$TIPOB))
cat("\n  Personas sin seguimiento (excluidas):", n_sin_seguimiento, "\n")
datos <- datos[!is.na(datos$TIPOB), ]
cat("  Personas en análisis:", nrow(datos), "\n")

## ---------------------------------------------------------------------------
## B4. Age at entry and exit
## ---------------------------------------------------------------------------
##
##  Entry age = census date − birth date
##  Exit date  = ABAJA + DECAB/10 + 0.05 (midpoint of the tenth)
##  Exit age   = exit date − birth date
##
##  The +0.05 correction places the exit at the midpoint of the DECAB
##  interval (e.g., DECAB=3 → month ~3.5, so +0.05 gives 0.35 of year).
##
##  We trim ages outside [0, 115] as data errors (impossible ages).

datos$edad_entrada <- FECHA_CENSO - datos$FNAC
datos$fecha_salida <- datos$ABAJA + datos$DECAB / 10 + 0.05
datos$edad_salida  <- datos$fecha_salida - datos$FNAC

antes <- nrow(datos)
datos <- datos[datos$edad_salida >= datos$edad_entrada &
                 datos$edad_entrada >= 0 & datos$edad_salida <= 115, ]
cat("  Filas eliminadas por inconsistencias de edad:", antes - nrow(datos), "\n")

# Aggregate causes into 10 broad groups (first 2 digits of CODCAU)
# Only meaningful for deceased persons (TIPOB == 1)
datos$grupo_causa <- ifelse(datos$TIPOB == 1 & datos$CODCAU != "",
                             substr(datos$CODCAU, 1, 2), NA_character_)

nombres_grupo_causa <- c(
  "01" = "Enfermedades del sistema circulatorio",
  "02" = "Tumores malignos",
  "03" = "Enfermedades endocrinas (diabetes, etc.)",
  "04" = "Enfermedades infecciosas",
  "05" = "Enfermedades del sistema respiratorio",
  "06" = "Enfermedades del aparato digestivo",
  "07" = "Enfermedades del sistema nervioso",
  "08" = "Causas externas (accidentes, suicidio...)",
  "09" = "Causas relacionadas con el alcohol",
  "10" = "Resto de causas"
)
cat("\n  Fallecimientos por gran grupo de causa:\n")
print(sort(table(nombres_grupo_causa[datos$grupo_causa]), decreasing = TRUE))

## ---------------------------------------------------------------------------
## B5. Person-years by age band (vectorized overlap calculation)
## ---------------------------------------------------------------------------
##
##  WHY VECTORIZED (not a loop):
##    With ~600k individuals × 19 age bands, a for-loop would take minutes.
##    The vectorized approach computes all overlaps simultaneously using
##    pmin/pmax on matrices, completing in milliseconds.
##
##  WHAT THIS COMPUTES:
##    For each person i and each age band j:
##      overlap_ij = max(0, min(exit_age_i, band_upper_j) − max(entry_age_i, band_lower_j))
##    This is the time (in years) person i spent "at risk" in age band j.
##
##  WHY IT'S CORRECT:
##    A 47.3-year-old person followed to age 59.3 contributes:
##      45-49 band: min(59.3, 50) − max(47.3, 45) = 50 − 47.3 = 2.7 years
##      50-54 band: min(59.3, 55) − max(47.3, 50) = 55 − 50.0 = 5.0 years
##      55-59 band: min(59.3, 60) − max(47.3, 55) = 59.3 − 55 = 4.3 years
##      Total: 2.7 + 5.0 + 4.3 = 12.0 years ✓ (= follow-up duration)

edad_ini <- datos$edad_entrada
edad_fin <- datos$edad_salida

limite_inf <- matrix(CORTES_EDAD[1:n_bandas],       nrow = length(edad_ini), ncol = n_bandas, byrow = TRUE)
limite_sup <- matrix(CORTES_EDAD[2:(n_bandas + 1)], nrow = length(edad_ini), ncol = n_bandas, byrow = TRUE)

anos_persona <- pmax(0, pmin(edad_fin, limite_sup) - pmax(edad_ini, limite_inf))
dim(anos_persona) <- c(length(edad_ini), n_bandas)
colnames(anos_persona) <- etiquetas_banda

datos$banda_salida <- cut(edad_fin, breaks = CORTES_EDAD, labels = etiquetas_banda, right = FALSE)

cat("  Total años-persona:", format(round(sum(anos_persona)), big.mark = "."), "\n")

## ---------------------------------------------------------------------------
## B6. Life table construction (Chiang, 1968)
## ---------------------------------------------------------------------------
##
##  THE CHIANG METHOD:
##    Standard demographic technique for abridged (grouped) life tables.
##    Key insight: the probability of dying in age band i, q_i, is related
##    to the observed mortality rate M_i by:
##      q_i = (n_i × M_i) / (1 + a_i × M_i)
##    where n_i = band width (5 years) and a_i = average years lived in the
##    band by those who die there (assumed n_i/2 = uniform distribution).
##
##  CAUSE-DELETION EXTENSION:
##    To estimate EV without cause C:
##      R_i = 1 − (deaths from C in band i) / (total deaths in band i)
##      q_i* = 1 − (1 − q_i)^R_i
##    This preserves the relative risk structure of remaining causes.
##
##    IMPORTANT CAVEAT: causes are assumed independent. The sum of gains
##    across all causes ≠ "live forever." Each cause-deleted estimate is
##    interpreted in isolation. See PASO 11 in the full pipeline for
##    detailed limitations.

anchura_banda <- diff(CORTES_EDAD)
anchura_banda[n_bandas] <- NA

construir_tabla_vida <- function(sexo_codigo, causas_a_eliminar = NULL) {
  es_sexo <- datos$SEXO == sexo_codigo
  py <- colSums(anos_persona[es_sexo, , drop = FALSE])

  es_fallecido <- datos$TIPOB == 1 & es_sexo
  muertes_totales <- as.numeric(table(factor(datos$banda_salida[es_fallecido], levels = etiquetas_banda)))

  if (!is.null(causas_a_eliminar)) {
    es_causa <- es_fallecido & datos$grupo_causa %in% causas_a_eliminar
    muertes_causa <- as.numeric(table(factor(datos$banda_salida[es_causa], levels = etiquetas_banda)))
  } else {
    muertes_causa <- rep(0, n_bandas)
  }

  Mx <- muertes_totales / py
  R  <- 1 - (muertes_causa / muertes_totales)
  R[is.nan(R)] <- 1

  n  <- anchura_banda
  ax <- n / 2

  qx <- (n * Mx) / (1 + ax * Mx)
  qx[n_bandas] <- 1

  qx_ajustada <- 1 - (1 - qx) ^ R
  qx_ajustada[n_bandas] <- 1

  calcular_ex <- function(qx_vec) {
    lx <- numeric(n_bandas + 1)
    lx[1] <- 100000
    for (i in 1:n_bandas) lx[i + 1] <- lx[i] * (1 - qx_vec[i])
    dx <- -diff(lx)
    Lx <- numeric(n_bandas)
    for (i in 1:(n_bandas - 1)) Lx[i] <- n[i] * lx[i + 1] + ax[i] * dx[i]
    Lx[n_bandas] <- lx[n_bandas] / Mx[n_bandas]
    Tx <- rev(cumsum(rev(Lx)))
    ex <- Tx / lx[1:n_bandas]
    ex
  }

  ex_observada <- calcular_ex(qx)
  ex_sin_causa <- calcular_ex(qx_ajustada)

  data.frame(
    banda          = etiquetas_banda,
    anos_persona   = round(py),
    muertes        = muertes_totales,
    tasa_mortalidad = round(Mx, 5),
    esperanza_vida  = round(ex_observada, 2),
    esperanza_vida_sin_causa = round(ex_sin_causa, 2),
    ganancia_anos           = round(ex_sin_causa - ex_observada, 2)
  )
}

## ---------------------------------------------------------------------------
## B7. Observed life expectancy by sex (all 10 territories combined)
## ---------------------------------------------------------------------------
##
##  SEXO = 1 → male, SEXO = 6 → female (INE coding convention)

cat("\n\n", strrep("=", 55), "\n")
cat("  ESPERANZA DE VIDA OBSERVADA (todas las causas)\n")
cat("", strrep("=", 55), "\n")

tabla_hombres <- construir_tabla_vida(sexo_codigo = "1")
tabla_mujeres <- construir_tabla_vida(sexo_codigo = "6")

cat("\n--- Hombres ---\n")
print(tabla_hombres[, c("banda","anos_persona","muertes","tasa_mortalidad","esperanza_vida")])
cat(sprintf("  EV al nacer (hombres): %.2f años\n", tabla_hombres$esperanza_vida[1]))
cat("\n--- Mujeres ---\n")
print(tabla_mujeres[, c("banda","anos_persona","muertes","tasa_mortalidad","esperanza_vida")])
cat(sprintf("  EV al nacer (mujeres): %.2f años\n", tabla_mujeres$esperanza_vida[1]))

## ---------------------------------------------------------------------------
## B8. Life expectancy gain if each cause of death were eliminated
## ---------------------------------------------------------------------------
##
##  For each of the 10 cause groups × 2 sexes, we build a cause-deleted
##  life table and compute the gain in EV at birth (banda 0-4).
##
##  INTERPRETATION:
##    "If tumours were eliminated, male EV at birth would be 79.53 → 83.46,
##     a gain of 3.93 years."
##    This does NOT mean men would live 3.93 years longer in reality —
##    only that the mortality structure of tumours accounts for this much
##    of the EV gap relative to a hypothetical tumour-free population.

cat("\n\n", strrep("=", 55), "\n")
cat("  GANANCIA EN EV AL NACER SI SE ELIMINARA CADA CAUSA\n")
cat("", strrep("=", 55), "\n")

resumen_causas <- function(sexo_codigo, etiqueta_sexo) {
  filas <- lapply(names(nombres_grupo_causa), function(codigo) {
    tabla <- construir_tabla_vida(sexo_codigo, causas_a_eliminar = codigo)
    data.frame(
      sexo   = etiqueta_sexo,
      causa  = nombres_grupo_causa[[codigo]],
      esperanza_vida_observada = tabla$esperanza_vida[1],
      esperanza_vida_sin_causa = tabla$esperanza_vida_sin_causa[1],
      ganancia_anos            = tabla$ganancia_anos[1]
    )
  })
  do.call(rbind, filas)
}

resumen <- rbind(
  resumen_causas("1", "Hombres"),
  resumen_causas("6", "Mujeres")
)
resumen <- resumen[order(resumen$sexo, -resumen$ganancia_anos), ]
rownames(resumen) <- NULL
print(resumen)

## ---------------------------------------------------------------------------
## B9. Life expectancy by province and sex
## ---------------------------------------------------------------------------
##
##  Builds 20 independent life tables (10 territories × 2 sexes).
##  Each table uses only the subset of individuals in that province × sex.
##
##  WHY NOT SMALL-AREA ESTIMATION:
##    BDLPA IDs are sequential numbers, not geographic codes. The only
##    geographic variable recoverable from mp11.txt is PROVINCIA (2 digits).
##    Municipal or census-section codes would require linkage to the
##    Padrón Continuo (municipal register), which is not currently available.
##
##  STABILITY NOTE:
##    Province-level samples range from ~27k (Granada) to ~55k (Cádiz) per
##    sex. In extreme age bands (0-4, 90+), death counts may be <5, causing
##    unstable Mx estimates. The EV at birth (first band) is robust because
##    it integrates information from all 19 age bands.

cat("\n\n", strrep("=", 55), "\n")
cat("  EV AL NACER POR PROVINCIA Y SEXO\n")
cat("", strrep("=", 55), "\n")

nombres_provincia <- c(
  "04" = "Almeria", "11" = "Cadiz", "14" = "Cordoba", "18" = "Granada",
  "21" = "Huelva",  "23" = "Jaen",  "29" = "Malaga",  "41" = "Sevilla",
  "51" = "Ceuta",   "52" = "Melilla"
)

construir_tabla_vida_provincia <- function(codigo_provincia, sexo_codigo) {
  es_prov <- datos$PROVINCIA == codigo_provincia
  es_sexo <- datos$SEXO == sexo_codigo
  idx <- es_prov & es_sexo

  # Guard against provinces with insufficient data (<50 individuals)
  if (sum(idx) < 50) {
    return(data.frame(
      provincia = nombres_provincia[codigo_provincia],
      sexo = ifelse(sexo_codigo == "1", "Hombres", "Mujeres"),
      esperanza_vida_nacer = NA_real_, n_personas = sum(idx), n_muertes = NA_integer_
    ))
  }
  py <- colSums(anos_persona[idx, , drop = FALSE])
  es_fallecido <- datos$TIPOB == 1 & idx
  muertes_totales <- as.numeric(table(factor(datos$banda_salida[es_fallecido], levels = etiquetas_banda)))
  Mx <- muertes_totales / py
  n <- anchura_banda; ax <- n / 2
  qx <- (n * Mx) / (1 + ax * Mx); qx[n_bandas] <- 1
  lx <- numeric(n_bandas + 1); lx[1] <- 100000
  for (i in 1:n_bandas) lx[i + 1] <- lx[i] * (1 - qx[i])
  dx <- -diff(lx); Lx <- numeric(n_bandas)
  for (i in 1:(n_bandas - 1)) Lx[i] <- n[i] * lx[i + 1] + ax[i] * dx[i]
  Lx[n_bandas] <- lx[n_bandas] / Mx[n_bandas]
  Tx <- rev(cumsum(rev(Lx)))
  ex_nacer <- Tx[1] / lx[1]
  data.frame(
    provincia = nombres_provincia[codigo_provincia],
    sexo = ifelse(sexo_codigo == "1", "Hombres", "Mujeres"),
    esperanza_vida_nacer = round(ex_nacer, 2),
    n_personas = sum(idx), n_muertes = sum(muertes_totales)
  )
}

resultados_ev_provincia <- do.call(rbind, lapply(names(nombres_provincia), function(cod_prov) {
  rbind(construir_tabla_vida_provincia(cod_prov, "1"),
        construir_tabla_vida_provincia(cod_prov, "6"))
}))
rownames(resultados_ev_provincia) <- NULL
print(resultados_ev_provincia)

ev_provincia_ancho <- reshape(
  resultados_ev_provincia[, c("provincia", "sexo", "esperanza_vida_nacer")],
  idvar = "provincia", timevar = "sexo", direction = "wide"
)
names(ev_provincia_ancho) <- c("provincia", "EV_Hombres", "EV_Mujeres")


## =============================================================================
## PARTE C: Guardar todos los resultados
## =============================================================================
##
##  OUTPUT FILES (written to ../Resultados/):
##    1. ganancia_esperanza_vida_por_causa.csv — 20 rows (10 causes × 2 sexes)
##    2. tabla_vida_hombres.csv              — 19 rows (age bands)
##    3. tabla_vida_mujeres.csv              — 19 rows
##    4. ev_por_provincia_sexo.csv           — 20 rows (10 territories × 2 sexes, long)
##    5. ev_por_provincia_ancho.csv          — 10 rows (one per territory, wide)
##    6. grafico_ganancia_por_causa.png      — horizontal barplot

cat("\n\n", strrep("-", 50), "\n")
cat("  PARTE C: Guardar resultados\n")
cat("", strrep("-", 50), "\n")

write.csv(resumen, file.path(out_dir, "ganancia_esperanza_vida_por_causa.csv"), row.names = FALSE)
write.csv(tabla_hombres, file.path(out_dir, "tabla_vida_hombres.csv"), row.names = FALSE)
write.csv(tabla_mujeres, file.path(out_dir, "tabla_vida_mujeres.csv"), row.names = FALSE)
write.csv(resultados_ev_provincia, file.path(out_dir, "ev_por_provincia_sexo.csv"), row.names = FALSE)
write.csv(ev_provincia_ancho, file.path(out_dir, "ev_por_provincia_ancho.csv"), row.names = FALSE)

cat("\n  Ficheros guardados en", out_dir, ":\n")
cat("  - ganancia_esperanza_vida_por_causa.csv\n")
cat("  - tabla_vida_hombres.csv\n")
cat("  - tabla_vida_mujeres.csv\n")
cat("  - ev_por_provincia_sexo.csv\n")
cat("  - ev_por_provincia_ancho.csv\n")

## ---------------------------------------------------------------------------
## C1. Gráfico: ganancia por causa (hombres)
## ---------------------------------------------------------------------------

png(file.path(out_dir, "grafico_ganancia_por_causa.png"), width = 1000, height = 700, res = 120)
par(mar = c(5, 14, 4, 2))
resumen_h <- resumen[resumen$sexo == "Hombres", ]
resumen_h <- resumen_h[order(resumen_h$ganancia_anos), ]
barplot(resumen_h$ganancia_anos, names.arg = resumen_h$causa, horiz = TRUE, las = 1,
        col = "#1a5276", border = NA,
        main = "Ganancia en EV al nacer si se elimina la causa\n(Hombres, cohorte censal Andalucía 2011)",
        xlab = "Años ganados")
dev.off()
cat("  - grafico_ganancia_por_causa.png\n")

cat("\n", strrep("=", 69), "\n")
cat("  ANÁLISIS COMPLETO — Todos los ficheros guardados.\n")
cat("", strrep("=", 69), "\n")

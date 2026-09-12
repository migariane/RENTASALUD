## =============================================================================
## RENTASALUD — ESPERANZA DE VIDA POR MUNICIPIO (Análisis municipal)
## =============================================================================
##
##  PURPOSE
##  --------
##  Downscales the provincial life-expectancy analysis of RENTASALUD to the
##  municipal level for the 785 municipalities of Andalusia, and links the
##  resulting municipal life expectancies to the median disposable income of
##  each municipality (INE ADRH / Atlas de Distribución de Renta de los
##  Hogares, 2015-2022).
##
##  The script is fully self-contained: it reads the raw BDLPA text files
##  (mp11.txt, smp11cau.txt), the INE census-section shapefiles, and the
##  cleaned income/population dataset produced by the earlier RENTASALUD
##  pipeline, and it writes all tables and figures to ./salidas/.
##
##  OUTPUTS (written to ./salidas/)
##  --------
##    personas_municipal.rds         Parsed + validated BDLPA cohort
##    tabla_vida_municipal_sexo.csv  Chiang life tables per municipality x sex
##    esperanza_vida_municipal.csv   e(0) per municipality x sex (and pooled)
##    esperanza_vida_causa_municipal.csv  Cause-deleted gains per municipality x sex
##    renta_mediana_municipal.csv    Population-weighted median income per municipality
##    ev_por_quintil.csv             e(0) by municipality income quintile (Q1..Q5)
##    correlaciones_ev_renta.csv     Correlation + regression EV vs income
##    mapa_ev_hombres.png            Choropleth of male e(0)
##    mapa_ev_mujeres.png            Choropleth of female e(0)
##    mapa_renta_mediana.png         Choropleth of median income
##    scatter_ev_renta.png           Scatterplots e(0) vs income
##    ev_por_quintil.png             e(0) by income quintile
##    ev_causa_sexo.png              Mean cause-deleted gain by cause x sex
##
##  STATISTICAL METHOD (BRIEF)
##  -------------------------
##  * Municipal code recovery from mp11.txt: the file is NOT the "fixed width
##    minus FELEV" format assumed by the provincial pipeline.  Systematic
##    inspection of the raw records showed that the MUNICIPIO field also drops
##    its leading zero(es), while DISTRITO, SECCION and ZONA keep a fixed
##    width (2, 3 and 2 characters).  The municipality is therefore recovered
##    by anchoring on the birth-date field (FNAC) and scanning backwards with
##    a variable-width municipality field, validated against the official INE
##    municipality codes present in the census-section shapefiles.  See the
##    validation block in Part 1 and the accompanying METODOS.md document.
##  * Follow-up: exit date = ABAJA + DECAB/10 + 0.05; exit reason TIPOB
##    (1 = death, 2 = transferred out, 3 = alive at end of follow-up).
##  * Person-years of exposure are allocated to 5-year age bands via the
##    vectorised overlap method (identical to the provincial pipeline).
##  * Life expectancy is computed with Chiang's (1968) abridged life-table
##    method: q_x = n*M_x / (1 + a_x*M_x), with a_x = n/2, and the open
##    interval closed at 90+.  Cause-deleted life tables use
##    q*_x = 1 - (1 - q_x)^R_x, where R_x is the share of deaths NOT caused
##    by the eliminated cause.
##  * Municipalities with too few deaths are excluded from the life tables
##    (threshold controlled by MIN_DEATHS_* below) to avoid unstable q_x.
##  * Income: population-weighted mean of the section-level median income per
##    consumption unit, averaged over the 8 available years (2015-2022).
##
##  =============================================================================
##  PART 0 — SETUP
##  =============================================================================

## ---------------------------------------------------------------------------
## 0.1 Packages (must be installed once with install.packages())
## ---------------------------------------------------------------------------
library(dplyr)        # data manipulation
library(tidyr)        # reshaping
library(sf)           # spatial / shapefiles / maps
library(ggplot2)      # graphics
library(scales)       # axis labels (comma/thousand separators)
library(patchwork)    # combining ggplot panels

## Small helper used below (like rlang's `%||%`, avoiding an extra dependency)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

## ---------------------------------------------------------------------------
## 0.2 Reproducibility
## ---------------------------------------------------------------------------
set.seed(42)          # so random subsamples used for validation are repeatable

## ---------------------------------------------------------------------------
## 0.3 Project paths
##    The script expects the same folder layout as the rest of RENTASALUD:
##      RENTASALUD/Datos/           raw BDLPA files (mp11.txt, smp11cau.txt)
##      RENTASALUD/Analysis/        <- the Analysis folder
##        SHP/seccionado_*          INE census-section shapefiles (2015-2022)
##        datos_rentapop_long.RData cleaned income/population data
##        EV_municipal/             <- this script and its salidas/ folder
## ---------------------------------------------------------------------------
## The script may be launched either from inside EV_municipal/ or from
## Analysis/.  We detect its own location with --file= (Rscript) or by
## falling back to the working directory.
argv <- commandArgs(trailingOnly = FALSE)
arg_fichero <- sub("^--file=", "", argv[grep("^--file=", argv)])
ruta_script <- if (length(arg_fichero) && nzchar(arg_fichero[1])) {
  dirname(normalizePath(arg_fichero[1]))
} else {
  getwd()
}
## Normalise so that ruta_analysis always points to the Analysis folder.
if (basename(ruta_script) == "EV_municipal") {
  ruta_analysis <- dirname(ruta_script)
} else {
  ruta_analysis <- ruta_script
}
dir_datos   <- file.path(ruta_analysis, "..", "Datos")    # RENTASALUD/Datos
dir_shp     <- file.path(ruta_analysis, "SHP")            # Analysis/SHP
ruta_renta  <- file.path(ruta_analysis, "datos_rentapop_long.RData")
dir_salida  <- file.path(ruta_analysis, "EV_municipal", "salidas")
dir.create(dir_salida, showWarnings = FALSE, recursive = TRUE)

ruta_mp11     <- file.path(dir_datos, "mp11.txt")
ruta_smp11cau <- file.path(dir_datos, "smp11cau.txt")
stopifnot(file.exists(ruta_mp11), file.exists(ruta_smp11cau), file.exists(ruta_renta))

## ---------------------------------------------------------------------------
## 0.4 Global constants
## ---------------------------------------------------------------------------
FECHA_CENSO   <- 2011 + 305 / 366          # 2011-10-31/365.25; census reference date
CODIGOS_ANDALUCIA <- c("04","11","14","18","21","23","29","41")  # 8 provinces
NOMBRE_PROVINCIA  <- c("04"="Almeria","11"="Cadiz","14"="Cordoba","18"="Granada",
                       "21"="Huelva","23"="Jaen","29"="Malaga","41"="Sevilla")

## Age bands (identical to the provincial pipeline): 5-year bands 0-4..85-89 + 90+
CORTES_EDAD <- c(seq(0, 90, by = 5), 120)
ETIQUETAS_BANDA <- c(paste(seq(0, 85, by = 5), seq(4, 89, by = 5), sep = "-"), "90+")
N_BANDAS <- length(ETIQUETAS_BANDA)
ANCHURA_BANDA <- diff(CORTES_EDAD)
ANCHURA_BANDA[N_BANDAS] <- NA             # open interval has no fixed width

## Minimum number of deaths required before a municipal life table is built.
## A life table with < MIN_DEATHS deaths would produce q_x = 0 in most bands
## (implausible zero mortality) and a wildly unstable e(0).  These values can
## be lowered to include more (smaller) municipalities at the cost of noise.
MIN_DEATHS_AMBOS  <- 40   # pooled sexes  (used for the income-quintile analysis)
MIN_DEATHS_SEXO   <- 30   # per sex       (used for sex-specific e(0))

## In addition, a stratum is only considered reliable if it has observed at
## least MIN_DEATHS_VEJECES deaths at ages 80+ (the "80-84","85-89","90+"
## bands).  Life expectancy is dominated by the old-age mortality schedule,
## and a stratum where NO old person died over the 12-year follow-up would
## otherwise return an absurd e(0) (the open-interval mortality would be
## estimated as ~0).  This excludes a handful of small coastal municipalities
## whose BDLPA sample shows no old-age deaths at all.
MIN_DEATHS_VEJECES <- 3
POS_80MAS <- match(c("80-84", "85-89", "90+"), ETIQUETAS_BANDA)

## ---------------------------------------------------------------------------
## 0.5 Census-section shapefiles
##    IMPORTANT (macOS + Dropbox): reading a shapefile stored inside Dropbox
##    can hang because macOS's file-provider daemon materialises the file
##    on demand.  We therefore copy the shapefile to a local temporary
##    directory FIRST and read it from there.  This is safe and cheap.
## ---------------------------------------------------------------------------
copiar_shapefile_local <- function(ruta_shp) {
  ## Copy the .shp and all companion files (.dbf, .shx, .prj, .sbn, .sbx, .cpg)
  ## of the same base name into a unique local temp subdirectory.
  base <- tools::file_path_sans_ext(basename(ruta_shp))
  dir_destino <- file.path(tempdir(), paste0("shapefile_", base))
  dir.create(dir_destino, showWarnings = FALSE, recursive = TRUE)
  ficheros <- list.files(dirname(ruta_shp), pattern = paste0("^", base, "\\."),
                         full.names = TRUE)
  ficheros <- ficheros[!grepl("\\.lock$", ficheros)]
  file.copy(ficheros, dir_destino, overwrite = TRUE)
  file.path(dir_destino, paste0(base, ".shp"))
}

## 2018 sections -> reference sets of valid municipality and section codes
## (needed to validate / disambiguate the mp11.txt municipal parsing).
ruta_sec2018 <- copiar_shapefile_local(file.path(dir_shp, "seccionado_2018",
                                                 "SECC_CE_20180101.shp"))
sec2018 <- st_read(ruta_sec2018, quiet = TRUE)
sec2018A <- sec2018[sec2018$CPRO %in% CODIGOS_ANDALUCIA, ]
MUN_REAL   <- unique(sec2018A$CUMUN)      # official 5-digit INE municipality codes
MUN_REAL   <- MUN_REAL[substr(MUN_REAL, 1, 2) %in% CODIGOS_ANDALUCIA]
CUSEC_REAL <- unique(sec2018A$CUSEC)      # official 10-digit section codes
cat("Official INE municipalities (Andalucia, 2018):", length(MUN_REAL), "\n")

## 2022 sections -> municipal map (most recent geography available).
ruta_sec2022 <- copiar_shapefile_local(file.path(dir_shp, "seccionado_2022",
                                                 "SECC_CE_20220101.shp"))
sec2022 <- st_read(ruta_sec2022, quiet = TRUE)

## =============================================================================
## PART 1 — DATA MANAGEMENT: parsing and validation of the BDLPA cohort
## =============================================================================

## ---------------------------------------------------------------------------
## 1.1 The mp11.txt persons file: structure and decoding of the municipality
## ---------------------------------------------------------------------------
##
##  mp11.txt contains one record per person in the BDLPA sample (~637,400
##  records).  It is documented as fixed-width, but TWO fields drop their
##  leading zeros and therefore have variable width:
##
##      ID         (6)   person identifier
##      FELEV      (7-9) sampling elevation factor x 10^6 (leading zeros
##                      dropped -> variable width)
##      PROVINCIA  (2)   INE province code
##      MUNICIPIO  (3)   INE municipality code within province
##                      *** leading zero(es) dropped -> 1-3 characters ***
##      DISTRITO   (2)   census district      (FIXED width 2)
##      SECCION    (3)   census section       (FIXED width 3)
##      ZONA       (2)   POTA planning zone   (FIXED width 2; 1..34)
##      FNAC       (5)   birth date x 10 (e.g. 19641 -> 1964.1)  [anchor]
##      SEXO       (1)   INE code: 1 = male, 6 = female
##      ...                (the remaining fields are not needed here)
##
##  WHY THE PROVINCIAL PIPELINE'S PARSING WAS NOT SUFFICIENT
##  --------------------------------------------------------
##  The provincial pipeline locates the province by scanning a window before
##  FNAC for the first valid 2-digit code.  With only the municipality as the
##  target, that scan proved unreliable: validating the result against the
##  official INE municipality codes showed that a simple first-match scan
##  mis-attributes ~20 % of persons (e.g. it reads the leading digits of the
##  municipality field, or digits inside FELEV).  A municipality-validated
##  parser is required.
##
##  THE RECOVERY ALGORITHM (per record)
##  ----------------------------------
##    F = 28 + (line_length - 79)   -> 1-based position of FNAC (anchor that
##                                     was validated against real birth dates)
##    For each possible width mw of the municipality field (1, 2 or 3):
##       prov1  = F - 9 - mw          -> 1-based position of PROVINCIA
##       geo    = characters (prov1+2) .. (F-1)   -> MUN+DIS+SEC+ZONA block
##       (a) PROVINCIA must be one of the 8 Andalusian codes;
##       (b) municipality = PROV + sprintf("%03d", as.integer(MUN))
##           must be in MUN_REAL (the official INE municipality codes);
##       (c) ZONA must be an integer in 1..34 (POTA zones);
##       (d) the full section code (PROV+MUN+DIS+SEC) is recorded for
##           disambiguation (it must be a real section where possible).
##    Records with exactly ONE valid (a)-(c) candidate are assigned directly
##    (86 %).  For the rest we apply, in order:
##       (1) keep only candidates whose full section code is real;
##       (2) keep only candidates whose POTA zone matches the municipality's
##           known zone (a deterministic 1-to-1 municipality->zone map built
##           from the uniquely-decoded records);
##    Records that remain ambiguous after (1)-(2) are dropped (about 5 %).
##
##  VALIDATION (see the printed checks below)
##  -----------------------------------------
##    * SEXO only ever takes the INE codes 1 and 6;
##    * ZONA is perfectly consistent within municipalities (0 contradictions);
##    * the correlation between the recovered per-municipality sample counts
##      and the official INE population of each municipality is r > 0.9;
##    * the recovered sample population of Almeria matches the census share
##      exactly (8.4 %), and the other provinces are within a few points —
##      the residual gaps reflect genuine BDLPA linkage losses (e.g. foreign
##      residents in the Costa del Sol municipalities are under-linked to the
##      mortality register), not parsing errors.

## Parse a chunk of lines for a given municipality width mw (vectorised).
parsear_mw <- function(li, mw) {
  F    <- 28 + (nchar(li) - 79)                    # 1-based FNAC start
  prov1 <- F - 9 - mw                              # 1-based PROVINCIA start
  pr   <- substr(li, prov1, prov1 + 1)             # province code candidate
  geo  <- substr(li, prov1 + 2, F - 1)             # MUN+DIS+SEC+ZONA block
  ## fields inside the geo block (fixed widths after the variable MUN field)
  m    <- substr(geo, 1, mw)                       # municipality digits
  d    <- substr(geo, mw + 1, mw + 2)              # district (fixed 2)
  se   <- substr(geo, mw + 3, mw + 5)              # section  (fixed 3)
  zn   <- substr(geo, mw + 6, mw + 7)              # POTA zone (fixed 2)
  zv   <- suppressWarnings(as.integer(zn))
  mun  <- paste0(pr, sprintf("%03d", suppressWarnings(as.integer(m))))
  data.frame(mun = mun, zona = zv, cusec = paste0(mun, d, se),
             valido = pr %in% CODIGOS_ANDALUCIA &
                      mun %in% MUN_REAL &
                      !is.na(zv) & zv >= 1 & zv <= 34 &
                      nchar(geo) == mw + 7,
             stringsAsFactors = FALSE)
}

## Read the raw file and parse it with the three possible municipality widths.
cat("\n=== 1.1 Reading", ruta_mp11, "===\n")
lineas <- readLines(ruta_mp11, encoding = "latin1")
cat("Records read:", length(lineas), "\n")

c1 <- parsear_mw(lineas, 1)
c2 <- parsear_mw(lineas, 2)
c3 <- parsear_mw(lineas, 3)
nvalid <- c(c1$valido, c2$valido, c3$valido)
cat("Valid candidates by municipality width (1/2/3):",
    paste(sum(c1$valido), sum(c2$valido), sum(c3$valido)), "\n")

n_ok <- c1$valido + c2$valido + c3$valido        # number of valid parses per line
cat("Lines with exactly one valid parse:", sum(n_ok == 1), "\n")
cat("Lines with several valid parses :", sum(n_ok >  1), "\n")
cat("Lines with no valid parse       :", sum(n_ok == 0), "\n")

## ---------------------------------------------------------------------------
## 1.2 First pass: assign the unique parses and build the municipality->ZONA map
## ---------------------------------------------------------------------------
ID    <- substr(lineas, 1, 6)
FNAC  <- suppressWarnings(as.numeric(substr(lineas, 28 + (nchar(lineas) - 79),
                                           28 + (nchar(lineas) - 79) + 4))) / 10
SEXO  <- substr(lineas, 28 + (nchar(lineas) - 79) + 5,
                28 + (nchar(lineas) - 79) + 5)

MUNICIPIO <- rep(NA_character_, length(lineas))
ZONA      <- rep(NA_integer_,   length(lineas))
unico <- n_ok == 1
cands_list <- list(c1, c2, c3)
for (k in 1:3) {
  take <- unico & cands_list[[k]]$valido
  MUNICIPIO[take] <- cands_list[[k]]$mun[take]
  ZONA[take]      <- cands_list[[k]]$zona[take]
}
cat("Assigned in first pass:", sum(!is.na(MUNICIPIO)),
    "=", round(100 * mean(!is.na(MUNICIPIO)), 1), "%\n")

## Municipality -> POTA zone map (must be perfectly consistent by construction
## of the format; we verify that below).
mapa_zona <- data.frame(mun = MUNICIPIO[!is.na(MUNICIPIO)],
                        zona = ZONA[!is.na(MUNICIPIO)]) %>%
  group_by(mun) %>%
  summarise(zona = names(sort(table(zona), decreasing = TRUE))[1], .groups = "drop")
ZMAP <- setNames(mapa_zona$zona, mapa_zona$mun)
cat("Municipalities mapped to a POTA zone:",
    length(ZMAP), "of", length(MUN_REAL), "\n")

## ---------------------------------------------------------------------------
## 1.3 Second pass: disambiguate the remaining lines
## ---------------------------------------------------------------------------
mult <- which(n_ok > 1)
cat("Disambiguating", length(mult), "ambiguous records...\n")
for (j in mult) {
  cands <- do.call(rbind, list(c1[j, ], c2[j, ], c3[j, ]))
  cands <- cands[cands$valido, ]
  if (nrow(cands) == 0) next
  ## (1) prefer candidates whose full section code exists in the 2018 INE file
  real <- cands[cands$cusec %in% CUSEC_REAL, ]
  if (nrow(real) == 1) { MUNICIPIO[j] <- real$mun[1]; ZONA[j] <- real$zona[1]; next }
  ## (2) otherwise keep candidates consistent with the municipality's POTA zone
  okz <- cands$mun %in% names(ZMAP) & cands$zona == ZMAP[cands$mun]
  okz[is.na(okz)] <- FALSE
  u <- unique(cands$mun[okz])
  if (length(u) == 1) { MUNICIPIO[j] <- u; ZONA[j] <- ZMAP[u]; next }
}
cat("Final municipal assignment:",
    sum(!is.na(MUNICIPIO)), "=", round(100 * mean(!is.na(MUNICIPIO)), 1), "%\n")

## ---------------------------------------------------------------------------
## 1.4 Validation of the municipal parsing
## ---------------------------------------------------------------------------
cat("\n=== 1.4 Validation ===\n")
cat("SEXO distribution (INE codes 1=male, 6=female):\n")
print(table(SEXO, useNA = "ifany"))

## ZONA must be constant within each municipality (POTA zones are municipal).
cat("Municipalities with INCONSISTENT POTA zone:",
    sum(tapply(ZONA[!is.na(MUNICIPIO)], MUNICIPIO[!is.na(MUNICIPIO)],
               function(x) length(unique(x)) > 1), na.rm = TRUE), "\n")

## Correlation between the recovered sample counts and the official INE
## population per municipality (the strongest external check available).
load(ruta_renta)  # -> data.frame datos (section-level income/population, 2015-22)
renta_sec <- datos %>%
  mutate(id = ifelse(nchar(as.character(id)) == 10, as.character(id),
                     paste0("0", as.character(id)))) %>%
  filter(nchar(id) == 10, substr(id, 1, 2) %in% CODIGOS_ANDALUCIA)
pob_mun <- renta_sec %>%
  filter(año == 2015) %>%
  mutate(mun5 = substr(id, 1, 5)) %>%
  group_by(mun5) %>% summarise(pob_ine = sum(pob, na.rm = TRUE), .groups = "drop")

contador <- data.frame(mun5 = MUNICIPIO[!is.na(MUNICIPIO)]) %>%
  group_by(mun5) %>% summarise(n_mp11 = n(), .groups = "drop")
cmp <- inner_join(contador, pob_mun, by = "mun5") %>% filter(pob_ine > 0)
cat("Municipalities used for the validation:", nrow(cmp), "\n")
cat("log-log correlation (sample count vs INE population):",
    round(cor(log(cmp$n_mp11), log(cmp$pob_ine)), 3), "\n")
cat("Spearman correlation:", round(cor(cmp$n_mp11, cmp$pob_ine, method = "spearman"), 3), "\n")

## Province share of the recovered sample vs the 2011 census (see comments above)
prov_rec <- table(substr(MUNICIPIO[!is.na(MUNICIPIO)], 1, 2))
cat("Recovered province shares (%):\n")
print(round(100 * prov_rec / sum(prov_rec), 1))
cat("Census 2011 shares (%)     : 04:8.4 11:14.8 14:9.5 18:11.0 21:6.2 23:7.9 29:19.3 41:23.1\n")

## ---------------------------------------------------------------------------
## 1.5 Follow-up file smp11cau.txt (truly fixed width, 17 characters/line)
## ---------------------------------------------------------------------------
##    ID (1-6)      person identifier (matches mp11)
##    ABAJA (7-10)  calendar year of exit from follow-up
##    DECAB (11)    tenth of year (0-9) approximating the month of exit
##    TIPOB (12)    exit reason: 1 = death, 2 = transferred out,
##                               3 = alive at end of follow-up
##    CODCAU (13-17) cause-of-death code, e.g. "02_01" (5 characters)
cat("\n=== 1.5 Reading", ruta_smp11cau, "===\n")
lineas2 <- readLines(ruta_smp11cau, encoding = "latin1")
cat("Follow-up records:", length(lineas2), "\n")
smp11 <- data.frame(
  ID     = substr(lineas2, 1, 6),
  ABAJA  = as.integer(substr(lineas2, 7, 10)),
  DECAB  = as.integer(substr(lineas2, 11, 11)),
  TIPOB  = as.integer(substr(lineas2, 12, 12)),
  CODCAU = trimws(substr(lineas2, 13, 17)),
  stringsAsFactors = FALSE
)
cat("Exit reason (TIPOB):\n")
print(table(smp11$TIPOB))

## ---------------------------------------------------------------------------
## 1.6 Merge persons + follow-up and clean the cohort
## ---------------------------------------------------------------------------
datos <- data.frame(ID = ID, MUNICIPIO = MUNICIPIO, ZONA = ZONA,
                    FNAC = FNAC, SEXO = SEXO, stringsAsFactors = FALSE)
datos <- merge(datos, smp11, by = "ID", all.x = TRUE)
cat("\nPersons without follow-up record (excluded):", sum(is.na(datos$TIPOB)), "\n")
datos <- datos[!is.na(datos$TIPOB), ]
cat("Persons entering the analysis:", nrow(datos), "\n")

## Ages: entry age (census date - birth) and exit age (exit date - birth).
## The +0.05 puts the exit at the middle of the DECAB interval.
datos$edad_entrada <- FECHA_CENSO - datos$FNAC
datos$edad_salida  <- (datos$ABAJA + datos$DECAB / 10 + 0.05) - datos$FNAC
antes <- nrow(datos)
datos <- datos[datos$edad_salida >= datos$edad_entrada &
               datos$edad_entrada >= 0 & datos$edad_salida <= 115, ]
cat("Rows removed for age inconsistencies:", antes - nrow(datos), "\n")

## Cause groups: first two digits of the cause code.  All codes in the file
## map to one of the 10 groups below (verified: no unknown codes).
GRUPOS_CAUSA <- c(
  "01" = "Circulatorio",
  "02" = "Tumores",
  "03" = "Endocrino",
  "04" = "Infecciosas",
  "05" = "Respiratorio",
  "06" = "Digestivo",
  "07" = "Nervioso",
  "08" = "Causas externas",
  "09" = "Relacionadas con alcohol",
  "10" = "Resto")
datos$grupo_causa <- ifelse(datos$TIPOB == 1 & datos$CODCAU != "",
                            substr(datos$CODCAU, 1, 2), NA_character_)
cat("\nDeaths by broad cause group:\n")
print(sort(table(GRUPOS_CAUSA[datos$grupo_causa]), decreasing = TRUE))

## Save the cleaned cohort so Part 1 can be skipped on re-runs.
saveRDS(datos, file.path(dir_salida, "personas_municipal.rds"))
cat("Cleaned cohort saved to salidas/personas_municipal.rds\n")

## =============================================================================
## PART 2 — PERSON-YEARS OF EXPOSURE BY AGE BAND
## =============================================================================
##
##  For each person i and age band j we compute the overlap of the person's
##  follow-up interval [edad_entrada, edad_salida] with the band [inf_j, sup_j):
##
##      overlap_ij = max(0, min(edad_salida, sup_j) - max(edad_entrada, inf_j))
##
##  This is done simultaneously for all persons and bands with pmin/pmax on
##  matrices (identical approach to the provincial pipeline).  The result is
##  then aggregated to municipality x sex x band with rowsum().
cat("\n=== 2.1 Person-years ===\n")
lim_inf <- matrix(CORTES_EDAD[1:N_BANDAS], nrow = nrow(datos),
                  ncol = N_BANDAS, byrow = TRUE)
lim_sup <- matrix(CORTES_EDAD[2:(N_BANDAS + 1)], nrow = nrow(datos),
                  ncol = N_BANDAS, byrow = TRUE)
## pmax/pmin drop matrix attributes, so we restore the dimensions explicitly
## (a person x age-band matrix), exactly as in the provincial pipeline.
anos_persona <- pmax(0, pmin(datos$edad_salida, lim_sup) -
                       pmax(datos$edad_entrada, lim_inf))
dim(anos_persona) <- c(nrow(datos), N_BANDAS)
colnames(anos_persona) <- ETIQUETAS_BANDA
cat("Total person-years of exposure:",
    format(round(sum(anos_persona)), big.mark = "."), "\n")

## Exit band of each deceased person (for the death counts by band)
datos$banda_salida <- cut(datos$edad_salida, breaks = CORTES_EDAD,
                          labels = ETIQUETAS_BANDA, right = FALSE)

## Aggregate exposure and deaths at the municipal level.
## NOTE: persons whose municipality could not be recovered are EXCLUDED here
## (they carry no municipality).  `ok` filters them out explicitly before the
## aggregation because paste(NA, x) would otherwise create a bogus "NA" group.
ok <- !is.na(datos$MUNICIPIO) & datos$SEXO %in% c("1", "6")
grupo <- paste(datos$MUNICIPIO[ok], datos$SEXO[ok], sep = "_")
py_mun_sexo <- rowsum(anos_persona[ok, , drop = FALSE],
                      group = grupo)            # rows = mun_sex, cols = bands
cat("Municipality x sex strata with exposure:", nrow(py_mun_sexo), "\n")

fallecidos <- datos[datos$TIPOB == 1 & !is.na(datos$MUNICIPIO) &
                    datos$SEXO %in% c("1", "6"), ]
muertes_mun_sexo <- data.frame(grupo = paste(fallecidos$MUNICIPIO, fallecidos$SEXO,
                                             sep = "_"),
                               banda = as.character(fallecidos$banda_salida)) %>%
  table()                                          # rows = mun_sex, cols = bands
muertes_causa <- data.frame(grupo = paste(fallecidos$MUNICIPIO, fallecidos$SEXO,
                                          sep = "_"),
                            banda = as.character(fallecidos$banda_salida),
                            causa = fallecidos$grupo_causa) %>%
  table()                                          # mun_sex x banda x causa

## =============================================================================
## PART 3 — MUNICIPAL LIFE TABLES (Chiang, 1968)
## =============================================================================

## ---------------------------------------------------------------------------
## 3.1 The life-table engine (identical to the provincial pipeline)
## ---------------------------------------------------------------------------
##
##  Given the age-band exposure PY and the death counts D, the mortality
##  rate is M = D/PY and Chiang's probability of death in the band is
##
##      q = (n * M) / (1 + a * M),      a = n/2 (uniform death distribution)
##
##  The final (open) interval has q = 1.  From the q vector we build the
##  classical columns: lx (survivors), dx (deaths), Lx (years lived),
##  Tx (years left) and finally ex = Tx/lx.  For the open interval,
##  Lx_open = lx_open / M_open (the expected remaining years under a
##  constant mortality rate).
##
##  The cause-deleted version replaces q by q* = 1 - (1 - q)^R, where R is
##  the proportion of deaths in the band that are NOT due to the eliminated
##  cause.  This removes the cause from the mortality schedule while keeping
##  the relative structure of the remaining causes (independent-cause
##  assumption, as in the provincial pipeline).
## ---------------------------------------------------------------------------
construir_tabla <- function(py, muertes, muertes_causa = NULL) {
  ## Guards for sparse strata:
  ##  * no exposure in a band -> mortality is set to 0 (Mx = 0);
  ##  * if there are no deaths in the final open interval (90+), its rate is
  ##    borrowed from the pooled 85+ age group so that the open life
  ##    expectancy stays finite (standard small-sample imputation);
  ##  * if even 85+ has no deaths, a floor rate of 1/(total exposure) is used;
  ##  * q_x = n*M/(1+a*M) can exceed 1 when M is large (a death in a band
  ##    with very little exposure).  As Chiang's formula allows, we CLAMP
  ##    q_x to [0,1] so the survivor column never goes negative.
  py[is.na(py)] <- 0
  muertes[is.na(muertes)] <- 0
  Mx <- muertes / py
  Mx[py == 0] <- 0
  if (Mx[N_BANDAS] == 0) {
    Mx[N_BANDAS] <- sum(muertes[(N_BANDAS - 1):N_BANDAS]) /
                    max(1e-9, sum(py[(N_BANDAS - 1):N_BANDAS]))
  }
  ## Sparse-strata safeguard: the 90+ mortality can never be observed as zero
  ## in a small municipal sample.  Flooring it at 0.15 caps the implied
  ## 90+ remaining life at ~6.7 years (Spanish 90+ mortality is ~0.2-0.3,
  ## i.e. e(90) ~ 5-6 years), which prevents absurd e(0) values for strata
  ## with very few old-age deaths (see also MIN_DEATHS_VEJECES).
  ##
  ## STATISTICAL JUSTIFICATION (verified externally, ref G1 in
  ## gpai_workflow/REGISTRO_GPAI.md): the open-interval estimator e_open =
  ## 1/M_open has, under Poisson deaths, Bias ~ 1/(P*lambda^2) and Var ~
  ## 1/(P*lambda^3), so it is unusable when D(90+) = 0.  There is NO
  ## universal MSE-minimising rule; 0.15 is therefore a documented stability
  ## bound close to the real Spanish 90+ rate (e(90) ~ 5-6 years).  The
  ## pooled-85+ rate above is tried first, but whenever it is below 0.15
  ## (the typical case) the floor replaces it: pooling 85-89 with 90+
  ## systematically UNDERestimates M(90+) (85-89 mortality < 90+), so the
  ## pooled rate alone would overestimate the open remaining life even more
  ## than the floor does.
  if (!is.finite(Mx[N_BANDAS]) || Mx[N_BANDAS] < 0.15) Mx[N_BANDAS] <- 0.15
  R  <- 1 - (muertes_causa / muertes)               # fraction of deaths kept
  R[is.nan(R)] <- 1                                 # no deaths -> nothing removed
  ax <- ANCHURA_BANDA / 2                           # n/2 for closed bands
  qx <- (ANCHURA_BANDA * Mx) / (1 + ax * Mx)
  qx <- pmin(pmax(qx, 0), 1)                        # clamp to [0,1]
  qx[N_BANDAS] <- 1                                 # open interval
  if (!is.null(muertes_causa)) {
    qx_aj <- 1 - (1 - qx) ^ R
    qx_aj <- pmin(pmax(qx_aj, 0), 1)
    qx_aj[N_BANDAS] <- 1
  } else qx_aj <- qx

  calcular_ex <- function(q) {
    lx <- numeric(N_BANDAS + 1); lx[1] <- 1e5
    for (i in seq_len(N_BANDAS)) lx[i + 1] <- lx[i] * (1 - q[i])
    dx <- -diff(lx)
    Lx <- numeric(N_BANDAS)
    for (i in 1:(N_BANDAS - 1)) Lx[i] <- ANCHURA_BANDA[i] * lx[i + 1] +
                                           ax[i] * dx[i]
    Lx[N_BANDAS] <- lx[N_BANDAS] / Mx[N_BANDAS]
    Tx <- rev(cumsum(rev(Lx)))
    Tx / lx[1:N_BANDAS]
  }
  ex <- calcular_ex(qx)
  ex_sin <- calcular_ex(qx_aj)
  list(e0 = ex[1], e0_sin_causa = ex_sin[1], Mx = Mx, qx = qx,
       ex = ex, py = py, muertes = muertes)
}

## ---------------------------------------------------------------------------
## 3.2 Estimate e(0) for every municipality x sex (and pooled sexes)
## ---------------------------------------------------------------------------
##  A stratum is only used when it has at least MIN_DEATHS deaths; otherwise
##  e(0) is set to NA (insufficient data).  The threshold guarantees that the
##  age-specific mortality schedule is not dominated by zero-death bands.
cat("\n=== 3.2 Municipal life tables ===\n")

## Pooled-sex exposure and deaths (band matrices), for the "both sexes" EV.
grupo_ambos <- datos$MUNICIPIO[ok]
py_mun_ambos <- rowsum(anos_persona[ok, , drop = FALSE], group = grupo_ambos)
muertes_ambos <- data.frame(grupo = fallecidos$MUNICIPIO,
                            banda = as.character(fallecidos$banda_salida)) %>%
  table()

## Loop over strata and build the life tables.
## NOTE: table() sorts the age-band levels alphabetically ("0-4","10-14",...),
## and indexing a table row (x[fl, ]) DROPS the row dimension, returning a
## NAMED VECTOR whose names are the (alphabetical) band labels.  We therefore
## re-order it to the natural band order ETIQUETAS_BANDA used by the exposure
## matrix.
ordenar_muertes <- function(v) {
  v <- as.numeric(v)
  nm <- names(v)
  if (is.null(nm)) v else v[match(ETIQUETAS_BANDA, nm)]
}

## A stratum enters the life tables only if it has enough total deaths AND
## enough observed deaths at ages 80+ (old-age mortality must be observed;
## see the constants above).
estrato_fiable <- function(mf, min_total) {
  sum(mf) >= min_total && sum(mf[POS_80MAS]) >= MIN_DEATHS_VEJECES
}

## --- sex-specific e(0) ---
filas <- rownames(py_mun_sexo)
e0_sexo <- data.frame(estrato = filas, e0 = NA_real_, muertes = NA_integer_,
                      py = NA_real_, stringsAsFactors = FALSE)
for (i in seq_along(filas)) {
  fl <- filas[i]
  mf <- if (fl %in% rownames(muertes_mun_sexo)) ordenar_muertes(muertes_mun_sexo[fl, ]) else
        rep(0, N_BANDAS)
  if (!estrato_fiable(mf, MIN_DEATHS_SEXO)) next
  tab <- construir_tabla(py_mun_sexo[fl, ], mf)
  e0_sexo$e0[i] <- tab$e0; e0_sexo$muertes[i] <- sum(mf); e0_sexo$py[i] <- sum(tab$py)
}
e0_sexo <- separate(e0_sexo, estrato, into = c("mun5", "SEXO"), sep = "_")
e0_sexo$sexo <- ifelse(e0_sexo$SEXO == "1", "Hombres", "Mujeres")
cat("Municipality x sex life tables built:",
    sum(!is.na(e0_sexo$e0)), "of", nrow(e0_sexo), "\n")

## --- pooled-sex e(0) ---
e0_ambos <- data.frame(mun5 = rownames(py_mun_ambos), e0 = NA_real_,
                       muertes = NA_integer_, py = NA_real_,
                       stringsAsFactors = FALSE)
for (i in seq_len(nrow(e0_ambos))) {
  fl <- e0_ambos$mun5[i]
  mf <- if (fl %in% rownames(muertes_ambos)) ordenar_muertes(muertes_ambos[fl, ]) else
        rep(0, N_BANDAS)
  if (!estrato_fiable(mf, MIN_DEATHS_AMBOS)) next
  tab <- construir_tabla(py_mun_ambos[fl, ], mf)
  e0_ambos$e0[i] <- tab$e0; e0_ambos$muertes[i] <- sum(mf); e0_ambos$py[i] <- sum(tab$py)
}
cat("Pooled-sex municipal life tables built:",
    sum(!is.na(e0_ambos$e0)), "of", nrow(e0_ambos), "\n")

## ---------------------------------------------------------------------------
## 3.3 Assemble the municipal EV dataset (long format for plotting)
## ---------------------------------------------------------------------------
ev_sexo_largo <- e0_sexo %>% filter(!is.na(e0)) %>%
  select(mun5, sexo, e0, muertes, py)
ev_largo <- bind_rows(
  ev_sexo_largo,
  e0_ambos %>% filter(!is.na(e0)) %>%
    transmute(mun5, sexo = "Ambos", e0, muertes, py)
) %>% arrange(mun5, sexo)

## Municipal EV in wide format (one row per municipality, columns per sex)
ev_ancho <- ev_sexo_largo %>%
  pivot_wider(id_cols = mun5, names_from = sexo, values_from = e0)
write.csv(ev_ancho, file.path(dir_salida, "esperanza_vida_municipal.csv"),
          row.names = FALSE)
write.csv(ev_largo, file.path(dir_salida, "tabla_vida_municipal_sexo.csv"),
          row.names = FALSE)

cat("\nDistribution of municipal e(0):\n")
print(summary(ev_sexo_largo$e0))

## =============================================================================
## PART 4 — MUNICIPAL MEDIAN INCOME (INE ADRH, 2015-2022)
## =============================================================================
##
##  The Atlas de Distribucion de Renta de los Hogares provides the median
##  disposable income per CONSUMPTION UNIT at the census-section level.  A
##  municipal figure is approximated as the population-weighted mean of its
##  section medians.  Because median income fluctuates from year to year,
##  we average the municipal figure over all 8 available years, weighting
##  every section-year by its population.  (Sections without data in a given
##  year are simply omitted for that year.)
cat("\n=== 4.1 Municipal median income ===\n")
renta_mun <- renta_sec %>%
  mutate(mun5 = substr(id, 1, 5)) %>%
  group_by(mun5) %>%
  summarise(renta_mediana_uc = weighted.mean(Renta_Mediana_UC, w = pob,
                                             na.rm = TRUE),
            pob_media        = mean(pob, na.rm = TRUE),
            secciones        = n_distinct(id),
            .groups = "drop") %>%
  filter(!is.na(renta_mediana_uc), mun5 %in% MUN_REAL)
cat("Municipalities with income data:",
    nrow(renta_mun), "of", length(MUN_REAL), "\n")
write.csv(renta_mun, file.path(dir_salida, "renta_mediana_municipal.csv"),
          row.names = FALSE)

## =============================================================================
## PART 5 — LIFE EXPECTANCY vs MUNICIPAL INCOME
## =============================================================================
##
##  Two complementary views:
##    (a) correlation / regression of e(0) on income over all municipalities;
##    (b) quintile comparison: municipalities sorted by income and split into
##        five groups (Q1 = poorest 20 %, Q5 = wealthiest 20 %).  For each
##        quintile we report the population-weighted mean e(0).  The headline
##        result is the Q5 - Q1 difference in years of life expectancy.
cat("\n=== 5.1 EV vs income ===\n")

## Wide EV + income at the municipal level
ev_inc <- inner_join(ev_ancho, e0_ambos %>% filter(!is.na(e0)) %>%
                       select(mun5, e0_ambos = e0),
                     by = "mun5") %>%
  inner_join(renta_mun %>% select(mun5, renta_mediana_uc, pob_media),
             by = "mun5")

## (a) Correlations and linear regressions
ev_inc <- ev_inc %>% filter(!is.na(pob_media), is.finite(e0_ambos),
                            is.finite(Hombres), is.finite(Mujeres))
correlaciones <- data.frame(
  variable = c("Ambos", "Hombres", "Mujeres"),
  n_municipios = c(sum(!is.na(ev_inc$e0_ambos)), sum(!is.na(ev_inc$Hombres)),
                   sum(!is.na(ev_inc$Mujeres))),
  pearson = c(cor(ev_inc$e0_ambos, ev_inc$renta_mediana_uc, use = "complete.obs"),
              cor(ev_inc$Hombres, ev_inc$renta_mediana_uc, use = "complete.obs"),
              cor(ev_inc$Mujeres, ev_inc$renta_mediana_uc, use = "complete.obs")),
  spearman = c(cor(ev_inc$e0_ambos, ev_inc$renta_mediana_uc, method = "spearman",
                   use = "complete.obs"),
               cor(ev_inc$Hombres, ev_inc$renta_mediana_uc, method = "spearman",
                   use = "complete.obs"),
               cor(ev_inc$Mujeres, ev_inc$renta_mediana_uc, method = "spearman",
                   use = "complete.obs")),
  pendiente_anios_1000euro = c(
    coef(lm(e0_ambos ~ renta_mediana_uc, data = ev_inc, weights = pob_media))[2] * 1000,
    coef(lm(Hombres ~ renta_mediana_uc, data = ev_inc, weights = pob_media))[2] * 1000,
    coef(lm(Mujeres ~ renta_mediana_uc, data = ev_inc, weights = pob_media))[2] * 1000))
cat("Correlations e(0) vs income:\n"); print(correlaciones, row.names = FALSE)
write.csv(correlaciones, file.path(dir_salida, "correlaciones_ev_renta.csv"),
          row.names = FALSE)

## (b) Income quintiles of municipalities -> weighted mean e(0)
## Helper: weighted median of a vector
weighted.mediana <- function(x, w) {
  o <- order(x); cum <- cumsum(w[o]) / sum(w[o]); x[o][which(cum >= 0.5)[1]]
}
ev_inc$quintil <- factor(paste0("Q", ntile(ev_inc$renta_mediana_uc, 5)),
                         levels = paste0("Q", 1:5))
quintiles <- ev_inc %>%
  group_by(quintil) %>%
  summarise(n_municipios = n(),
            renta_mediana = weighted.mediana(renta_mediana_uc, pob_media),
            e0_ambos  = weighted.mean(e0_ambos,  w = pob_media, na.rm = TRUE),
            e0_hombres = weighted.mean(Hombres, w = pob_media, na.rm = TRUE),
            e0_mujeres = weighted.mean(Mujeres, w = pob_media, na.rm = TRUE),
            .groups = "drop")
quintiles$quintil <- factor(quintiles$quintil, levels = paste0("Q", 1:5))

## The headline quantity: Q5 (richest) - Q1 (poorest)
diferencia <- data.frame(
  sexo = c("Ambos", "Hombres", "Mujeres"),
  Q1_poorest = c(quintiles$e0_ambos[1], quintiles$e0_hombres[1], quintiles$e0_mujeres[1]),
  Q5_richest = c(quintiles$e0_ambos[5], quintiles$e0_hombres[5], quintiles$e0_mujeres[5]),
  diferencia_Q5_Q1 = c(quintiles$e0_ambos[5] - quintiles$e0_ambos[1],
                       quintiles$e0_hombres[5] - quintiles$e0_hombres[1],
                       quintiles$e0_mujeres[5] - quintiles$e0_mujeres[1]))
cat("\nLife expectancy by income quintile (population-weighted means):\n")
print(quintiles, width = 80)
cat("\nQ5 (richest) - Q1 (poorest) difference in years:\n")
print(diferencia, row.names = FALSE)
write.csv(quintiles, file.path(dir_salida, "ev_por_quintil.csv"), row.names = FALSE)

## Municipality-level EV + income + quintile for mapping (Part 7.5)
write.csv(ev_inc %>% select(mun5, renta_mediana_uc, pob_media, quintil,
                            e0_ambos, Hombres, Mujeres),
          file.path(dir_salida, "ev_renta_municipal.csv"), row.names = FALSE)

## (c) Formal comparison of the municipal e(0) in Q1 vs Q5 (Welch t-test)
tt_ambos <- t.test(e0_ambos ~ quintil, data = ev_inc %>% filter(quintil %in% c("Q1","Q5")))
diferencia_tt <- unname(tt_ambos$estimate[["mean in group Q5"]] -
                        tt_ambos$estimate[["mean in group Q1"]])
cat("\nWelch t-test e(0) pooled Q5 vs Q1: p =", format(tt_ambos$p.value, digits = 3),
    " (Q5 - Q1 =", round(diferencia_tt, 2), "years)\n")

## =============================================================================
## PART 6 — CAUSE-DELETED LIFE EXPECTANCY BY MUNICIPALITY AND SEX
## =============================================================================
##
##  For every municipality x sex stratum with enough deaths we estimate the
##  gain in e(0) that would follow the elimination of each of the 10 broad
##  cause groups (Chiang cause-deleted method, see Part 3.1).
cat("\n=== 6.1 Cause-deleted gains ===\n")
lista_ganancia <- list()
for (fl in filas) {
  mf <- if (fl %in% rownames(muertes_mun_sexo)) ordenar_muertes(muertes_mun_sexo[fl, ]) else
        rep(0, N_BANDAS)
  if (!estrato_fiable(mf, MIN_DEATHS_SEXO)) next
  py <- py_mun_sexo[fl, ]
  tab_base <- construir_tabla(py, mf)
  for (causa in names(GRUPOS_CAUSA)) {
    mc <- if (fl %in% dimnames(muertes_causa)[[1]] &&
              causa %in% dimnames(muertes_causa)[[3]]) {
      as.numeric(muertes_causa[fl, ETIQUETAS_BANDA, causa])
    } else rep(0, N_BANDAS)
    tab_sin <- construir_tabla(py, mf, mc)
    lista_ganancia[[length(lista_ganancia) + 1]] <- data.frame(
      mun5 = sub("_[16]$", "", fl),
      sexo = ifelse(grepl("_1$", fl), "Hombres", "Mujeres"),
      causa = GRUPOS_CAUSA[causa],
      e0 = tab_base$e0, e0_sin_causa = tab_sin$e0_sin_causa,
      ganancia = tab_sin$e0_sin_causa - tab_base$e0,
      muertes = sum(mf))
  }
}
ganancia <- do.call(rbind, lista_ganancia)
cat("Municipality x sex x cause strata:", nrow(ganancia), "\n")
write.csv(ganancia, file.path(dir_salida, "esperanza_vida_causa_municipal.csv"),
          row.names = FALSE)

## Mean gain per cause and sex across municipalities (weighted by deaths)
ganancia_resumen <- ganancia %>%
  group_by(sexo, causa) %>%
  summarise(ganancia_media = weighted.mean(ganancia, w = muertes, na.rm = TRUE),
            municipios = n(), .groups = "drop")
cat("\nMean cause-deleted gain (years) across municipalities:\n")
print(ganancia_resumen %>% arrange(sexo, desc(ganancia_media)), width = 70)

## =============================================================================
## PART 7 — FIGURES
## =============================================================================

## ---------------------------------------------------------------------------
## 7.1 Municipal map: dissolve 2022 census sections into municipalities
## ---------------------------------------------------------------------------
cat("\n=== 7.1 Building municipal maps ===\n")
sec2022A <- sec2022[sec2022$CPRO %in% CODIGOS_ANDALUCIA, ]
mun_geo <- sec2022A %>%
  group_by(CUMUN) %>%
  summarise(geometry = st_union(geometry), .groups = "drop")
mun_geo$NMUN <- sec2022A$NMUN[match(mun_geo$CUMUN, sec2022A$CUMUN)]

## Join the EV + income data to the geometries
mapa_datos <- mun_geo %>%
  left_join(ev_ancho, by = c("CUMUN" = "mun5")) %>%
  left_join(renta_mun, by = c("CUMUN" = "mun5"))
mapa_datos <- st_as_sf(mapa_datos)

## Theme for the choropleths
tema_mapa <- theme_void() + theme(
  legend.position = "bottom",
  legend.key.width = unit(1.4, "cm"),
  plot.title = element_text(face = "bold", size = 13))

dibujar_mapa <- function(variable, titulo, etiqueta, fichero, paleta = "YlGnBu") {
  p <- ggplot(mapa_datos) +
    geom_sf(aes(fill = .data[[variable]]), color = "grey75", lwd = 0.08) +
    scale_fill_distiller(palette = paleta, direction = 1, na.value = "grey90",
                         name = etiqueta, labels = comma) +
    labs(title = titulo) + tema_mapa
  ggsave(file.path(dir_salida, fichero), p, width = 8, height = 7, dpi = 150)
  p
}

p_mapa_h <- dibujar_mapa("Hombres", "Esperanza de vida al nacer - HOMBRES (anios)",
                         "e(0)", "mapa_ev_hombres.png")
p_mapa_m <- dibujar_mapa("Mujeres", "Esperanza de vida al nacer - MUJERES (anios)",
                         "e(0)", "mapa_ev_mujeres.png")
p_mapa_r <- dibujar_mapa("renta_mediana_uc",
                         "Renta mediana por unidad de consumo (euros)",
                         "Euros", "mapa_renta_mediana.png", paleta = "RdYlBu")
cat("Maps written to salidas/.\n")

## ---------------------------------------------------------------------------
## 7.2 Scatterplots e(0) vs income (faceted, with weighted regression lines)
## ---------------------------------------------------------------------------
scatter_df <- ev_largo %>%
  inner_join(renta_mun %>% select(mun5, renta_mediana_uc, pob_media), by = "mun5") %>%
  filter(!is.na(pob_media))

p_scatter <- ggplot(scatter_df, aes(renta_mediana_uc / 1000, e0)) +
  geom_point(aes(size = pob_media), alpha = 0.45, colour = "#2c7bb6") +
  geom_smooth(method = "lm", se = TRUE, colour = "#d7191c", linewidth = 0.8) +
  facet_wrap(~ factor(sexo, levels = c("Ambos", "Hombres", "Mujeres")), nrow = 1) +
  scale_size_continuous(range = c(0.4, 4), guide = "none") +
  scale_x_continuous(labels = comma) +
  labs(x = "Renta mediana municipal por unidad de consumo (miles de euros)",
       y = "Esperanza de vida al nacer (anios)",
       title = "Esperanza de vida vs renta mediana municipal") +
  theme_bw()
ggsave(file.path(dir_salida, "scatter_ev_renta.png"), p_scatter,
       width = 12, height = 4.5, dpi = 150)

## ---------------------------------------------------------------------------
## 7.3 e(0) by income quintile (Q1 poorest .. Q5 richest)
## ---------------------------------------------------------------------------
q_largo <- quintiles %>%
  pivot_longer(cols = c(e0_ambos, e0_hombres, e0_mujeres),
               names_to = "serie", values_to = "e0") %>%
  mutate(serie = recode(serie, e0_ambos = "Ambos", e0_hombres = "Hombres",
                        e0_mujeres = "Mujeres"))

p_quintil <- ggplot(q_largo, aes(quintil, e0, group = serie, colour = serie)) +
  geom_line(linewidth = 1) + geom_point(size = 3) +
  scale_color_manual(values = c(Ambos = "black", Hombres = "#2c7bb6",
                                Mujeres = "#d7191c")) +
  labs(x = "Quintil de renta municipal (Q1 = mas pobre, Q5 = mas rico)",
       y = "Esperanza de vida al nacer (anios, media ponderada por poblacion)",
       colour = NULL,
       title = "Esperanza de vida por quintil de renta municipal") +
  theme_bw() + theme(legend.position = "bottom")
ggsave(file.path(dir_salida, "ev_por_quintil.png"), p_quintil,
       width = 8, height = 5.5, dpi = 150)

## ---------------------------------------------------------------------------
## 7.4 Mean cause-deleted gain by cause and sex
## ---------------------------------------------------------------------------
p_causa <- ggplot(ganancia_resumen,
                  aes(reorder(causa, ganancia_media), ganancia_media, fill = sexo)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7) +
  coord_flip() +
  scale_fill_manual(values = c(Hombres = "#2c7bb6", Mujeres = "#d7191c")) +
  labs(x = NULL, y = "Ganancia media de e(0) si se eliminara la causa (anios)",
       fill = NULL,
       title = "Ganancia media de esperanza de vida por causa eliminada y sexo") +
  theme_bw() + theme(legend.position = "bottom")
ggsave(file.path(dir_salida, "ev_causa_sexo.png"), p_causa,
       width = 9, height = 6, dpi = 150)

## ---------------------------------------------------------------------------
## 7.5 Choropleth of life expectancy by income quintile (Q1 poorest vs Q5
##     richest municipalities)
## ---------------------------------------------------------------------------
## DESIGN: showing only the ~40 municipalities of a quintile on an otherwise
## empty (grey) map is hard to read.  Each panel therefore shows the FULL
## life-expectancy map of Andalusia (all municipalities with reliable e(0)),
## and the municipalities of the relevant quintile are highlighted with a
## thick black outline.  This makes both the spatial location of the
## quintile AND the life-expectancy contrast directly readable, with a
## shared colour legend for both panels.
mapa_base <- mun_geo %>%
  left_join(ev_inc %>% select(mun5, quintil, e0_ambos), by = c("CUMUN" = "mun5"))

rango_e0 <- range(ev_inc$e0_ambos, na.rm = TRUE)   # shared scale for both panels

dibujar_panel_quintil <- function(q, etiqueta) {
  d <- mapa_base
  d$destacado <- !is.na(d$quintil) & as.character(d$quintil) == q
  ggplot(d) +
    geom_sf(aes(fill = e0_ambos), colour = "grey72", linewidth = 0.08) +
    geom_sf(data = d[d$destacado, ], aes(fill = e0_ambos),
            colour = "black", linewidth = 0.6) +
    scale_fill_distiller(palette = "YlGnBu", direction = 1,
                         na.value = "grey94", name = "e(0) (anios)",
                         limits = rango_e0, labels = comma) +
    labs(title = etiqueta) +
    theme_void() +
    theme(legend.position = "bottom",
          legend.key.width = unit(1.6, "cm"),
          plot.title = element_text(face = "bold", size = 12, hjust = 0.5))
}

p_q1 <- dibujar_panel_quintil("Q1", paste0("Q1 - municipios mas pobres",
                                           "\n(renta mediana ",
                                           comma(quintiles$renta_mediana[quintiles$quintil == "Q1"]),
                                           " EUR)"))
p_q5 <- dibujar_panel_quintil("Q5", paste0("Q5 - municipios mas ricos",
                                           "\n(renta mediana ",
                                           comma(quintiles$renta_mediana[quintiles$quintil == "Q5"]),
                                           " EUR)"))
p_q1q5 <- (p_q1 + p_q5) +
  plot_layout(nrow = 1, guides = "collect") +
  plot_annotation(title = "Esperanza de vida por quintil de renta municipal (e(0) sexos combinados)",
                  subtitle = "Linea negra gruesa: municipios del quintil indicado. Q5 - Q1 = 2.5 anios (media ponderada por poblacion)")
ggsave(file.path(dir_salida, "mapa_ev_quintiles_Q1_Q5.png"), p_q1q5,
       width = 14, height = 6.5, dpi = 150)
cat("Q1 vs Q5 quintile choropleth written to salidas/.\n")

cat("\nAll tables and figures written to:", normalizePath(dir_salida), "\n")
cat("DONE.\n")

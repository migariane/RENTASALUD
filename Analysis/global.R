## =============================================================================
##  RENTASALUD — Global configuration and data loading
## =============================================================================
##
##  ARCHITECTURE:
##    global.R is sourced ONCE at app startup (before UI and server).
##    All variables defined here are available in app.R's server function.
##
##  DATA FLOW:
##    1. Load income/demographic data (datos_rentapop_long.RData)
##    2. Load pipeline outputs (EV by province, cause gains, life tables)
##    3. Compute derived variables (quintiles, correlations, palettes)
##    4. Define helper functions (formatting, tooltips, narrative)
##
##  WHY THESE CHOICES:
##    - Quintiles computed per-year (not globally): income distributions
##      shift over time (2015 vs 2022), so quintile thresholds should
##      reflect the year's distribution.
##    - EV at province level: BDLPA IDs are sequential, not geographic.
##      See pipeline_esperanza_vida_por_causa.R §7.5.
##    - Ollama local-first: privacy guarantee (no data leaves the machine).
##      Only falls back to cloud APIs if Ollama is unavailable AND API
##      keys are set.
##    - Sensitivity analysis (with/without Ceuta/Melilla): Ceuta and
##      Melilla are autonomous cities with distinct economic structures
##      (border trade, special tax regimes). Pre-computing both
##      correlations avoids recomputation on every user interaction.
## =============================================================================

library(shiny)
library(bslib)
library(leaflet)
library(dplyr)
library(sf)
library(stringr)
library(htmltools)
library(plotly)

# ── AI packages (optional: app runs without them) ──
ai_packages_ok <- tryCatch({
  library(querychat)
  library(ellmer)
  TRUE
}, error = function(e) FALSE)

## =========================================================================
## 1. Income and demographic data (INE Atlas, 2015-2022)
## =========================================================================
##
##  Source: Atlas de Distribución de Renta de los Hogares (ADRH), INE
##  Coverage: 10 territories (8 Andalusian provinces + Ceuta + Melilla)
##  Resolution: Census section (sección censal), ~6,000 sections × 8 years
##
##  Key variables:
##    Renta_Mediana_UC — median income per consumption unit (OECD-modified scale)
##    pob              — total population
##    edad_media       — mean age
##    menor_18         — % population under 18
##    mayor_65         — % population over 65
##    tam_hogar        — mean household size
##    hogares_uni      — % single-person households
##    pob_esp          — % Spanish nationals

load("datos_rentapop_long.RData")

# Census section IDs are 10-digit codes (CPRO+CMUN+CDIS+CSEC).
# Some IDs may have lost leading zeros during CSV export; we pad them.
datos$id <- str_pad(as.character(datos$id), width = 10, side = "left", pad = "0")

# ── Derived variables ──

# Income quintile: computed per-year because income distributions shift
# over time. Using global quintiles would misclassify sections in years
# with different overall income levels.
datos <- datos %>%
  group_by(año) %>%
  mutate(Renta_Quintil = ntile(Renta_Mediana_UC, 5)) %>%
  ungroup() %>%
  mutate(pob_extranjera = 100 - pob_esp)

## =========================================================================
## 2. Life expectancy data (pipeline output)
## =========================================================================
##
##  Source: pipeline_esperanza_vida_por_causa.R / 00_run_all.R
##  Computed from BDLPA 2011 census cohort (~637k individuals).
##  All EV values are at province level (not census section).

# ── EV by province (wide format: one row per province) ──
# Path auto-detection: local development (../Resultados/) vs server (/mnt/.../)
ruta_ev <- if (file.exists("../Resultados/ev_por_provincia_ancho.csv")) {
  "../Resultados/ev_por_provincia_ancho.csv"
} else if (file.exists("/mnt/user-data/outputs/ev_por_provincia_ancho.csv")) {
  "/mnt/user-data/outputs/ev_por_provincia_ancho.csv"
} else {
  "ev_por_provincia_ancho.csv"
}
ev_prov <- read.csv(ruta_ev, stringsAsFactors = FALSE)

# Join EV to census-section data by province.
# ALL sections within a province get the same EV value because the
# BDLPA only provides province-level geographic codes.
datos <- datos %>%
  left_join(ev_prov, by = c("Provincia" = "provincia"))

# Mean EV = simple average of male + female (unweighted by population
# age structure, appropriate for descriptive comparison).
datos$EV_Media <- round((datos$EV_Hombres + datos$EV_Mujeres) / 2, 2)

# ── Province-level summary (for income-EV correlation) ──
renta_provincia <- datos %>%
  group_by(Provincia) %>%
  summarise(Renta_Media = mean(Renta_Mediana_UC, na.rm = TRUE),
            EV_Media = mean(EV_Media, na.rm = TRUE),
            .groups = "drop")

# ── Sensitivity: Andalusia only (8 provinces, excluding Ceuta/Melilla) ──
# Ceuta and Melilla are autonomous cities with distinct economic structures
# (cross-border trade, large public sector, special tax regimes). They act
# as income outliers that weaken the aggregate income-EV correlation.
# We pre-compute both versions for the app's sensitivity toggle.
andalucia_solo <- c("Almeria","Cadiz","Cordoba","Granada","Huelva","Jaen","Malaga","Sevilla")
renta_provincia_and <- renta_provincia %>% filter(Provincia %in% andalucia_solo)

corr_all <- cor.test(renta_provincia$Renta_Media, renta_provincia$EV_Media)
corr_and <- cor.test(renta_provincia_and$Renta_Media, renta_provincia_and$EV_Media)

# ── Cause-elimination gains (pipeline output) ──
ruta_ganancia <- if (file.exists("../Resultados/ganancia_esperanza_vida_por_causa.csv")) {
  "../Resultados/ganancia_esperanza_vida_por_causa.csv"
} else if (file.exists("/mnt/user-data/outputs/ganancia_esperanza_vida_por_causa.csv")) {
  "/mnt/user-data/outputs/ganancia_esperanza_vida_por_causa.csv"
} else {
  "ganancia_esperanza_vida_por_causa.csv"
}
ganancia_causas <- read.csv(ruta_ganancia, stringsAsFactors = FALSE)

# ── Full life tables (for EV-by-age-band plots) ──
ruta_tabla_h <- if (file.exists("../Resultados/tabla_vida_hombres.csv")) {
  "../Resultados/tabla_vida_hombres.csv"
} else if (file.exists("/mnt/user-data/outputs/tabla_vida_hombres.csv")) {
  "/mnt/user-data/outputs/tabla_vida_hombres.csv"
} else {
  "tabla_vida_hombres.csv"
}
ruta_tabla_m <- if (file.exists("../Resultados/tabla_vida_mujeres.csv")) {
  "../Resultados/tabla_vida_mujeres.csv"
} else if (file.exists("/mnt/user-data/outputs/tabla_vida_mujeres.csv")) {
  "/mnt/user-data/outputs/tabla_vida_mujeres.csv"
} else {
  "tabla_vida_mujeres.csv"
}
tabla_vida_hombres <- read.csv(ruta_tabla_h, stringsAsFactors = FALSE)
tabla_vida_mujeres <- read.csv(ruta_tabla_m, stringsAsFactors = FALSE)

## =========================================================================
## 3. Visual configuration
## =========================================================================

# ── Cause color palette ──
# Fixed palette ensures consistent color assignments across all charts.
# Colors chosen for distinctiveness and accessibility (avoiding red-green
# pairs for colorblind users). Red tones = cardiovascular/cancer (leading
# causes); blues = respiratory; greens = digestive; warm tones = external.
colores_causas <- c(
  "Tumores malignos" = "#e74c3c",
  "Enfermedades del sistema circulatorio" = "#c0392b",
  "Enfermedades del sistema respiratorio" = "#3498db",
  "Enfermedades del aparato digestivo" = "#2ecc71",
  "Enfermedades endocrinas (diabetes, etc.)" = "#f39c12",
  "Enfermedades del sistema nervioso" = "#9b59b6",
  "Causas externas (accidentes, suicidio...)" = "#e67e22",
  "Enfermedades infecciosas" = "#1abc9c",
  "Causas relacionadas con el alcohol" = "#d35400",
  "Resto de causas" = "#7f8c8d"
)

# Province dropdown: "Toda Andalucía" first, then alphabetical
provincias_disponibles <- c("Toda Andalucía", sort(unique(datos$Provincia)))

# Indicator selector: maps display name → data column name
indicadores_completos <- c(
  "Renta Mediana (€)" = "Renta_Mediana_UC",
  "Edad Media" = "edad_media",
  "Población Total" = "pob",
  "% Menores de 18 años" = "menor_18",
  "% Mayores de 65 años" = "mayor_65",
  "Tamaño Medio del Hogar" = "tam_hogar",
  "% Hogares Unipersonales" = "hogares_uni",
  "% Población Española" = "pob_esp",
  "% Población Extranjera" = "pob_extranjera",
  "Quintil de Renta" = "Renta_Quintil",
  "Esperanza Vida (Hombres)" = "EV_Hombres",
  "Esperanza Vida (Mujeres)" = "EV_Mujeres",
  "Esperanza Vida (Media)" = "EV_Media"
)

# INE province codes for shapefile filtering
codigos_andalucia <- c("04", "11", "14", "18", "21", "23", "29", "41", "51", "52")

# ── AI backend detection ──
# Ollama runs locally (privacy-preserving, no data leaves the machine).
# Falls back to cloud APIs only if explicitly configured via env vars.
ollama_running <- tryCatch({
  con <- url("http://localhost:11434/api/tags", open = "rb")
  close(con)
  TRUE
}, error = function(e) FALSE)

openai_api_ok <- Sys.getenv("OPENAI_API_KEY") != ""
gemini_api_ok <- Sys.getenv("GEMINI_API_KEY") != ""

# ── Bootstrap theme ──
# Primary = dark blue (#1a5276) for UGR institutional brand consistency.
# Inter + Outfit fonts for modern, readable UI.
app_theme <- bs_theme(
  version = 5, preset = "shiny",
  primary = "#1a5276", secondary = "#5d6d7e",
  success = "#1e8449", info = "#2874a6",
  warning = "#d4ac0d", danger = "#c0392b",
  base_font = font_google("Inter"),
  heading_font = font_google("Outfit")
)

## =========================================================================
## 4. Helper functions
## =========================================================================

# ── Format values for display ──
# Handles Spanish locale formatting (thousands = ".", decimals = ",").
# Each indicator type has its own format: € for income, % for proportions,
# "Q" for quintiles, years for EV, etc.
format_value <- function(valor, indicador) {
  if (is.na(valor)) return("Sin datos")
  switch(indicador,
    "Renta_Mediana_UC" = paste0(format(round(valor), big.mark = ".", decimal.mark = ","), " €"),
    "pob" = format(round(valor), big.mark = ".", decimal.mark = ","),
    "menor_18" = , "mayor_65" = , "hogares_uni" = ,
    "pob_esp" = , "pob_extranjera" = paste0(round(valor, 1), "%"),
    "Renta_Quintil" = paste0("Q", round(valor)),
    "brecha_p90p10" = paste0(round(valor, 1), "x"),
    "brecha_q1_q5" = paste0(round(valor, 1), "x"),
    "q1_renta" = paste0(format(round(valor), big.mark = ".", decimal.mark = ","), " €"),
    "q5_renta" = paste0(format(round(valor), big.mark = ".", decimal.mark = ","), " €"),
    "edad_media" = paste0(round(valor, 1), " años"),
    "tam_hogar" = round(valor, 2),
    "EV_Hombres" = , "EV_Mujeres" = , "EV_Media" = paste0(round(valor, 1), " años"),
    round(valor, 2)
  )
}

# ── Map color palette ──
# Diverging palettes for continuous variables (RdYlGn, Spectral),
# sequential palettes for counts (YlGnBu). Choice follows ColorBrewer
# recommendations for choropleth maps.
get_palette <- function(ind) {
  switch(ind,
    "Renta_Mediana_UC" = , "Renta_Quintil" = "RdYlGn",
    "menor_18" = , "pob_extranjera" = "YlOrRd",
    "mayor_65" = , "edad_media" = "PuBuGn",
    "pob" = "YlGnBu",
    "EV_Hombres" = , "EV_Mujeres" = , "EV_Media" = "RdYlGn",
    "Spectral"
  )
}

# ── Map tooltip (HTML) ──
# Generates styled HTML tooltips for Leaflet polygons.
# Shows: municipality name, section code, indicator name + value.
build_tooltip <- function(res, val, nombre_ind, indicador) {
  vals <- sapply(seq_along(val), function(i) format_value(val[i], indicador))
  sprintf(
    "<div style='font-family:Inter,sans-serif;font-size:13px;min-width:190px;'>
     <div style='font-weight:700;color:#1a5276;border-bottom:2px solid #e8f4f8;padding-bottom:4px;margin-bottom:5px;'>%s</div>
     <div style='color:#5d6d7e;'>Sección: %s</div>
     <div style='margin-top:6px;padding:6px 8px;background:linear-gradient(135deg,#e8f8f5,#d5f5e3);border-radius:6px;'>
       <span style='font-weight:600;color:#1a5276;'>%s:</span><br/>
       <span style='font-size:15px;font-weight:800;color:#148f77;'>%s</span>
     </div></div>",
    ifelse(is.na(res$Municipio), "Desconocido", res$Municipio),
    res$CUSEC, nombre_ind, vals
  ) |> lapply(HTML)
}

# ── Contextual narrative generator ──
# Produces a short Spanish text describing the selected area's
# socioeconomic profile. Uses simple thresholds to classify areas:
#   - Income: ±3% of Andalusian average = "en torno a la media"
#   - Aging: >25% over 65 = "envejecida", <15% = "joven"
#   - Diversity: >15% foreign-born = "alta diversidad"
#   - Vulnerability: >35% single-person households = "posible vulnerabilidad"
#   - Inequality: P90/P10 ratio summarizes within-area income spread
generate_narrative <- function(df, prov, year, datos_all) {
  if (nrow(df) == 0) return("")

  renta <- mean(df$Renta_Mediana_UC, na.rm = TRUE)
  edad <- mean(df$edad_media, na.rm = TRUE)
  mayores <- mean(df$mayor_65, na.rm = TRUE)
  extranjera <- mean(100 - df$pob_esp, na.rm = TRUE)
  hogares_u <- mean(df$hogares_uni, na.rm = TRUE)

  renta_and <- mean(datos_all$Renta_Mediana_UC[datos_all$año == year], na.rm = TRUE)

  parts <- c()

  if (!is.na(renta) && !is.na(renta_and) && renta_and > 0) {
    diff <- round((renta - renta_and) / renta_and * 100, 1)
    rfmt <- format(round(renta), big.mark = ".", decimal.mark = ",")
    if (abs(diff) < 3) {
      parts <- c(parts, paste0("La renta mediana (", rfmt, " €) se sitúa en torno a la media andaluza."))
    } else if (diff > 0) {
      parts <- c(parts, paste0("La renta mediana (", rfmt, " €) supera la media andaluza en un ", abs(diff), "%."))
    } else {
      parts <- c(parts, paste0("La renta mediana (", rfmt, " €) queda un ", abs(diff), "% por debajo de la media andaluza."))
    }
  }

  if (!is.na(mayores) && mayores > 25)
    parts <- c(parts, paste0("Población envejecida: ", round(mayores, 1), "% mayores de 65."))
  if (!is.na(mayores) && mayores < 15)
    parts <- c(parts, paste0("Zona joven: solo ", round(mayores, 1), "% mayores de 65."))
  if (!is.na(extranjera) && extranjera > 15)
    parts <- c(parts, paste0("Alta diversidad: ", round(extranjera, 1), "% población extranjera."))
  if (!is.na(hogares_u) && hogares_u > 35)
    parts <- c(parts, paste0(round(hogares_u, 1), "% hogares unipersonales — posible vulnerabilidad social."))

  # Inequality: P90/P10 ratio within the selected area
  df_q <- datos_all[datos_all$año == year, ]
  if (prov != "Toda Andalucía") df_q <- df_q[df_q$Provincia == prov, ]
  q1 <- quantile(df_q$Renta_Mediana_UC, 0.1, na.rm = TRUE)
  q9 <- quantile(df_q$Renta_Mediana_UC, 0.9, na.rm = TRUE)
  if (!is.na(q1) && q1 > 0) {
    ratio <- round(q9 / q1, 1)
    parts <- c(parts, paste0("Brecha P90/P10: ", ratio, "x entre las secciones más y menos favorecidas."))
  }

  paste(parts, collapse = " ")
}

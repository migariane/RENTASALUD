## =============================================================================
##  RENTASALUD — Shapefile optimization for Shiny
## =============================================================================
##
##  PURPOSE:
##    Pre-process INE census section shapefiles (multi-file ESRI format)
##    into lightweight RDS files for fast loading in the Shiny app.
##
##  WHY THIS EXISTS:
##    Raw shapefiles are ~100 MB per year (all Spain, ~35,000 sections).
##    Loading via sf::st_read() on every Shiny map render takes >5 seconds.
##    This script reduces them to ~15 MB per year (Andalusia only, ~6,000
##    sections) in R's native binary format (10-50× faster to deserialize).
##
##  WHAT IT DOES:
##    1. Reads each year's shapefile (SHP/seccionado_YYYY/*.shp)
##    2. Filters to Andalusian sections + Ceuta + Melilla (CPRO filter)
##    3. Reprojects from ETRS89/UTM (EPSG:25830) to WGS84 (EPSG:4326)
##    4. Saves as .rds (R's native serialization format)
##
##  WHY EPSG:4326:
##    Leaflet (the mapping library used by the Shiny app) requires
##    coordinates in WGS84 latitude/longitude. The INE shapefiles are
##    distributed in the Spanish national projection (ETRS89 / UTM zone
##    30N, EPSG:25830). The transformation is lossless for these scales.
##
##  WHY FILTER BEFORE SAVING (not at load time):
##    Filtering 35,000 sections down to ~6,000 reduces the shapefile from
##    ~100 MB to ~15 MB. If we filtered at load time in Shiny, every user
##    would pay the 5-second cost. Pre-filtering makes map renders nearly
##    instant.
##
##  WHY RDS (not GeoJSON, not GPKG):
##    RDS is R's native binary format. It preserves all sf attributes
##    (CRS, geometry type, column types) without conversion overhead.
##    GeoJSON would be larger and slower to parse. GPKG is a good
##    alternative but requires GDAL at runtime (not guaranteed on
##    shinyapps.io).
##
##  DEPENDENCIES:
##    - R packages: sf, dplyr
##    - Input: SHP/seccionado_YYYY/*.shp (years 2015-2022)
##    - Output: SHP_opt/seccionado_YYYY.rds
##
##  HOW TO RUN:
##    cd RENTASALUD/Analysis
##    Rscript optimize_maps.R
##
##  RUNTIME: ~30-60 seconds (dominated by shapefile I/O)
## =============================================================================

library(sf)
library(dplyr)

# 10 territories: 8 Andalusian provinces + Ceuta (51) + Melilla (52)
codigos_andalucia <- c("04", "11", "14", "18", "21", "23", "29", "41", "51", "52")

dir.create("SHP_opt", showWarnings = FALSE)

years <- 2015:2022

for (year in years) {
  carpeta <- paste0("SHP/seccionado_", year)

  # Skip years without shapefile data (graceful degradation)
  if (!dir.exists(carpeta)) {
    cat("  Año", year, ": carpeta SHP no encontrada, omitiendo.\n")
    next
  }

  archivo <- list.files(carpeta, pattern = "\\.shp$", full.names = TRUE)
  if (length(archivo) == 0) {
    cat("  Año", year, ": sin archivo .shp, omitiendo.\n")
    next
  }

  cat("  Procesando año", year, "...\n")

  # Read shapefile (quiet = TRUE suppresses GDAL coordinate system messages)
  m <- st_read(archivo[1], quiet = TRUE)

  # Filter: CPRO is the first 2 digits of the census section code (CUSEC).
  # We keep only sections belonging to the 10 target territories.
  # This reduces the dataset from ~35,000 Spanish sections to ~6,000.
  m_and <- m %>%
    filter(CPRO %in% codigos_andalucia) %>%
    st_transform(4326)

  # Save optimized version for fast loading in Shiny
  saveRDS(m_and, paste0("SHP_opt/seccionado_", year, ".rds"))
}

cat("¡Terminado! Shapefiles optimizados en SHP_opt/\n")

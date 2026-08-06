# RENTASALUD — Reproducible Analysis Pipeline

R code for life expectancy estimation and income—mortality analysis in Andalusia, Ceuta, and Melilla (Spain).

## Contents

```
Analysis/
├── 00_run_all.R                          # Master pipeline runner
├── pipeline_esperanza_vida_por_causa.R    # Life expectancy + cause-deletion (Chiang 1968)
├── optimize_maps.R                        # Shapefile optimization for Shiny
├── global.R                               # Shiny app data loading + helpers
└── app.R                                  # Shiny interactive atlas
```

## Data sources

- **BDLPA**: Base de Datos Longitudinal de Población de Andalucía (IECA). Mortality microdata, 2011 census cohort, ~637,000 individuals, follow-up through 2023.
- **INE ADRH**: Atlas de Distribución de Renta de los Hogares. Census-section income and demographics, 2015–2022.
- **INE Cartografía**: Secciones censales shapefiles (2015–2022).

Data documentation is in `Datos/INFOBDLA/` and `Datos/INFORENTA/`.

## Run

```bash
cd Analysis
# Place raw data files (see Data sources), then:
Rscript 00_run_all.R
```

Outputs go to `../Resultados/`.

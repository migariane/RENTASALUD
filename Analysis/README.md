# RENTASALUD — Reproducible Analysis Pipeline

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.21237758.svg)](https://doi.org/10.5281/zenodo.21237758)

**RENTASALUD: a web-based interactive atlas of social inequalities and life expectancy in Andalusia, Ceuta, and Melilla (southern Spain)**

This repository contains the complete, reproducible analysis pipeline for the RENTASALUD project. It estimates life expectancy by province, sex, and cause of death using the BDLPA 2011 census cohort (~637,000 individuals, follow-up 2011–2023) and computes income–life expectancy correlations across 10 territories.

## Quick start

```bash
# 1. Clone
git clone https://github.com/migariane/RENTASALUD.git
cd RENTASALUD

# 2. Obtain data files (see Data sources below) and place them in:
#    Datos/mp11.txt          (~49 MB) — BDLPA person records
#    Datos/smp11cau.txt      (~11 MB) — BDLPA follow-up + cause of death
#    Datos/datos_rentapop_long.RData — processed INE income data
#    Analysis/SHP/seccionado_2015/ through seccionado_2022/ — INE census shapefiles
#    (contact autor for data access)

# 3. Install R packages
#    install.packages(c("dplyr", "sf"))

# 4. Run the full pipeline (~5 minutes)
cd Analysis
Rscript 00_run_all.R

# 5. Results appear in ../Resultados/
```

## Repository structure

```
RENTASALUD/
├── Analysis/                          # ⭐ All analysis code
│   ├── README.md                      # This file
│   ├── 00_run_all.R                   # Master runner (full pipeline)
│   ├── pipeline_esperanza_vida_por_causa.R  # Life expectancy pipeline (detailed)
│   ├── optimize_maps.R                # Shapefile optimizer (SHP → RDS)
│   ├── global.R                       # Shiny app config + data loading
│   └── app.R                          # Shiny app (UI + server)
│
├── Datos/                             # Data and documentation
│   ├── INFORENTA/                     # INE income definitions (PDF, XLSX, DOCX)
│   │   ├── Renta_media_Definiciones.pdf
│   │   └── Evolución Secciones Censales Granada 2015-2022.xlsx
│   └── INFOBDLA/                      # BDLPA microdata codebooks (PDF, ODS)
│       ├── microdatos-Descripcion_varaibles_2011.pdf
│       └── DisenoDeRegistroMicrodatos.ods
│
├── Resultados/                        # Output directory (created by pipeline)
│   ├── ev_por_provincia_ancho.csv
│   ├── ganancia_esperanza_vida_por_causa.csv
│   ├── tabla_vida_hombres.csv / tabla_vida_mujeres.csv
│   └── grafico_ganancia_por_causa.png
│
└── Resultados/articulo/              # Manuscript (Quarto)
    ├── index.qmd                     # Article source
    ├── references.bib                # References
    └── figures/                      # Figures
```

## Data sources

### BDLPA microdata (mortality)
- **Source**: Base de Datos Longitudinal de Población de Andalucía (IECA)
- **Files**: `mp11.txt` (persons), `smp11cau.txt` (follow-up + cause of death)
- **Documentation**: `Datos/INFOBDLA/microdatos-Descripcion_varaibles_2011.pdf`
- **Access**: Available from IECA on request (https://www.juntadeandalucia.es/institutodeestadisticaycartografia)

### INE income data (ADRH)
- **Source**: Atlas de Distribución de Renta de los Hogares (INE, 2015–2022)
- **Documentation**: `Datos/INFORENTA/Renta_media_Definiciones.pdf`
- **Access**: https://www.ine.es/dyngs/INEbase/es/operacion.htm?c=Estadistica_C&cid=1254736177088

### INE census shapefiles
- **Source**: Secciones censales (INE, 2015–2022)
- **Access**: https://www.ine.es/censos2021/censos2021_cartografia.htm

## Methods

### Life expectancy
Chiang (1968) cause-deleted life tables using 5-year age bands (0–4 through 85–89, 90+). Computed separately for each of 10 territories × 2 sexes = 20 tables.

### Cause elimination
For each of 10 cause groups, a cause-deleted life table is constructed by adjusting the probability of death proportionally (Chiang's R-method). Gains are interpreted as years of EV at birth that would be added if the cause were eliminated — one cause at a time.

### Income–EV correlation
Pearson and Spearman correlations between province-level median income and mean life expectancy. Sensitivity analysis excludes Ceuta and Melilla (autonomous cities with distinct economic structures).

## Key results

| Metric | Value |
|--------|-------|
| Life expectancy (men / women) | 79.5 / 84.4 years |
| Top cause gain (men) | Tumours: 3.93 years |
| Top cause gain (women) | Heart disease: 2.89 years |
| EV spread (10 territories) | 79.4 (Almería) – 82.7 (Córdoba) |
| Correlation (10 territories) | r = 0.28, P = 0.43 |
| Correlation (8 Andalusia) | r = 0.52, P = 0.19 |

## Shiny application

An interactive web atlas is deployed at: https://watzile.shinyapps.io/RENTA/

## Article

Luque-Fernández MA, Massó Guijarro P, Rivas Gervilla G, Nikšić M, Rivera Izquierdo M, Montero Alonso MÁ, Melchor Rodríguez JM. RENTASALUD: a web-based interactive atlas of social inequalities and life expectancy in Andalusia (southern Spain). 2025. DOI: 10.5281/zenodo.21237758

## License

CC BY 4.0

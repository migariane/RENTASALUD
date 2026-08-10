# RENTASALUD — Reproducible Analysis Pipeline

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.21237758.svg)](https://doi.org/10.5281/zenodo.21237758)
![R](https://img.shields.io/badge/R-4.5-blue?logo=r)
![License](https://img.shields.io/badge/license-MIT-green)

Reproducible R pipeline for life expectancy estimation and income–mortality analysis in Andalusia (southern Spain), covering the eight Andalusian provinces. Produces the data backing the [RENTASALUD interactive atlas](https://watzile.shinyapps.io/RENTA/).

**Authors:** Miguel Ángel Luque-Fernández, Gustavo Rivas Gervilla, Paloma Massó Guijarro, Maja Nikšić, Mario Rivera Izquierdo, Miguel Ángel Montero Alonso, Juan Manuel Melchor Rodríguez

---

## Contents

```
RENTASALUD/
├── README.md
├── Datos/
│   ├── INFOBDLA/        # BDLPA record layout + variable dictionary
│   └── INFORENTA/       # INE income atlas documentation
├── Analysis/
│   ├── 00_run_all.R                       # Master pipeline (run this)
│   ├── pipeline_esperanza_vida_por_causa.R # Life tables + cause-deletion
│   ├── optimize_maps.R                    # Shapefile pre-processing
│   ├── global.R                           # Shiny data loading + helpers
│   └── app.R                              # Shiny interactive atlas
└── Resultados/
    ├── articulo/                           # Manuscript (Quarto)
    ├── ev_por_provincia_ancho.csv
    ├── ev_por_provincia_sexo.csv
    ├── ganancia_esperanza_vida_por_causa.csv
    ├── tabla_vida_hombres.csv
    ├── tabla_vida_mujeres.csv
    └── Figuras/
```

## Data sources

| Source | Description | Scope |
|--------|-------------|-------|
| **BDLPA** (IECA) | 10% random sample of 2011 census cohort, ~637k individuals, follow-up through 2023 | 8 Andalusian provinces |
| **INE ADRH** | Household Income Distribution Atlas, census-section income + demographics, 2015–2022 | 8 Andalusian provinces (47,466 section-years) |
| **INE Cartografía** | Census section shapefiles, 2015–2022 | Spain → filtered to Andalusia |

Documentation: `Datos/INFOBDLA/` (record layout) and `Datos/INFORENTA/` (income definitions).

## Method summary

- **Life tables:** Abridged period life tables (Chiang 1968), 5-year age bands (0–4 to 90+)
- **Cause-deletion:** Chiang proportional-risk adjustment for 10 cause groups
- **16 life tables:** 8 provinces × 2 sexes
- **Geographic resolution:** Province level (BDLPA IDs carry no sub-provincial code)

## Run

```bash
cd Analysis
# 1. Place raw data files (mp11.txt, smp11cau.txt, shapefiles) in Datos/
# 2. Run the full pipeline:
Rscript 00_run_all.R
```

Outputs go to `../Resultados/` (CSV tables + PNG figure).

## Key results

| Metric | Value |
|--------|-------|
| Life expectancy at birth (men) | 79.5 years |
| Life expectancy at birth (women) | 84.4 years |
| Provincial LE range | 79.3 (Almería) to 82.7 (Córdoba) |
| Income–LE correlation (province) | r = 0.52 (P = 0.19) |
| Largest cause-deletion gain (men) | Tumours: +3.93 years |
| Largest cause-deletion gain (women) | Circulatory: +2.89 years |

## How to cite

> Luque-Fernández MA, Massó Guijarro P, Rivas Gervilla G, Nikšić M, Rivera Izquierdo M, Montero Alonso MÁ, Melchor Rodríguez JM. RENTASALUD: A Web-Based Interactive Atlas of Social Inequalities and Life Expectancy in Andalusia (Southern Spain). University of Granada; 2025. DOI: [10.5281/zenodo.21237758](https://doi.org/10.5281/zenodo.21237758)

## Authors and funding

**Authors (UGR):** Miguel Ángel Luque-Fernández, Gustavo Rivas Gervilla, Paloma Massó Guijarro, Mario Rivera Izquierdo, Miguel Ángel Montero Alonso, Juan Manuel Melchor Rodríguez

**International collaboration:** Maja Nikšić (Centre for Health Services Studies, University of Kent)

**Funding:** Plan Propio de Investigación y Transferencia, University of Granada (2025, Programa 21).

## License

MIT License. Copyright (c) 2025 Universidad de Granada.

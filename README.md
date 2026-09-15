# RENTASALUD

**Income Inequalities and Life Expectancy in Andalusia, Southern Spain**

[![DOI](https://img.shields.io/badge/DOI-10.5281%2Fzenodo.21237758-1682D4?logo=zenodo&logoColor=white)](https://doi.org/10.5281/zenodo.21237758)
[![R 4.4+](https://img.shields.io/badge/R-4.4%2B-276DC3?logo=r&logoColor=white)](https://cran.r-project.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## Overview

RENTASALUD is a reproducible R pipeline for estimating life expectancy and analysing income-mortality associations across the eight provinces of Andalusia (southern Spain). The project produces the data backing the [RENTASALUD Interactive Atlas](https://watzilei.shinyapps.io/RENTA/).

### Key Features

- **Cause-deleted life tables** using Chiang's (1968) method
- **Bootstrap confidence intervals** for all estimates
- **Income-life expectancy correlations** at province level
- **Sensitivity analyses** (leave-one-out, Pearson/Spearman)
- **Interactive Shiny atlas** for data exploration

### Main Findings

| Metric | Value |
|--------|-------|
| Life expectancy at birth (men) | **79.5 years** (95% CI: 79.4-79.7) |
| Life expectancy at birth (women) | **84.4 years** (95% CI: 84.2-84.5) |
| Provincial range | 79.3 (Almeria) to 82.7 (Cordoba) |
| Largest cause-deleted gain (men) | Malignant tumours: +3.93 years |
| Largest cause-deleted gain (women) | Circulatory diseases: +2.89 years |

---

## Repository Structure

```
RENTASALUD/
├── Analysis/
│   ├── 00_run_all.R                         # Main pipeline (run this)
│   ├── pipeline_esperanza_vida_por_causa.R  # Detailed method documentation
│   ├── global.R                             # Shiny data loading
│   ├── app.R                                # Shiny interactive atlas
│   ├── optimize_maps.R                      # Shapefile preprocessing
│   └── generate_test_data.R                 # Synthetic data for CI testing
│
├── Datos/
│   ├── INFOBDLA/                            # BDLPA record layout documentation
│   └── INFORENTA/                           # INE income atlas documentation
│
├── Resultados/
│   └── Article/                             # Manuscript (Quarto source)
│
├── README.md                                # This file
├── REPRODUCIBILITY.md                       # Verification checklist
├── CONTRIBUTING.md                          # Contribution guidelines
└── LICENSE                                  # MIT License
```

---

## Data Sources

| Source | Description | Records |
|--------|-------------|---------|
| [**BDLPA**](https://www.juntadeandalucia.es/institutodeestadisticaycartografia/) | 10% random sample of 2011 census cohort with mortality follow-up through 2023 | ~637,000 individuals |
| [**INE ADRH**](https://www.ine.es/experimental/atlas/experimental_atlas.htm) | Household Income Distribution Atlas, census-section level, 2015-2022 | ~47,500 section-years |
| [**INE Cartography**](https://www.ine.es/ss/Satellite?c=Page&cid=1259952026632&p=1259952026632&pagename=ProductosYServicios%2FPYSLayout) | Census section shapefiles | 8 years |

> **Note:** BDLPA microdata is restricted. Contact [IECA](https://www.juntadeandalucia.es/institutodeestadisticaycartografia/) for data access requests.

---

## Quick Start

### Prerequisites

- R 4.4 or later
- Required packages: `dplyr`, `sf`, `readr`, `tidyr`, `ggplot2`, `scales`

### Installation

```bash
# Clone the repository
git clone https://github.com/migariane/RENTASALUD.git
cd RENTASALUD

# Install R dependencies
Rscript -e "install.packages(c('dplyr', 'sf', 'readr', 'tidyr', 'ggplot2', 'scales'))"
```

### Running the Analysis

```bash
# Place your data files in Datos/
#   - mp11.txt       (BDLPA persons file, ~49 MB)
#   - smp11cau.txt   (BDLPA follow-up file, ~11 MB)
#   - datos_rentapop_long.csv (INE income data)

# Run the full pipeline
cd Analysis
Rscript 00_run_all.R
```

**Expected runtime:** 5-10 minutes (bootstrap resampling dominates)

### CI/Testing Mode

For testing without real data:

```bash
RENTASALUD_CI_MODE=true Rscript 00_run_all.R
```

This generates synthetic data and writes outputs to `Resultados/test_run/` to prevent overwriting production results.

---

## Output Files

After running the pipeline, `Resultados/` will contain:

| File | Description |
|------|-------------|
| `ev_bootstrap_ci.csv` | Life expectancy with 95% confidence intervals (27 strata) |
| `ev_por_provincia_sexo.csv` | Life expectancy by province and sex (16 rows) |
| `ev_por_provincia_ancho.csv` | Wide format for Shiny app (8 provinces) |
| `ganancia_esperanza_vida_por_causa.csv` | Cause-deleted life expectancy gains (20 rows) |
| `tabla_vida_hombres.csv` | Full life table, men (19 age bands) |
| `tabla_vida_mujeres.csv` | Full life table, women (19 age bands) |
| `correlaciones_renta_ev.csv` | Income-LE correlations by sex |
| `sensibilidad_leave_one_out.csv` | Leave-one-province-out sensitivity |
| `grafico_ganancia_por_causa.png` | Cause-deleted gains barplot |

See [`REPRODUCIBILITY.md`](REPRODUCIBILITY.md) for verification against manuscript values.

---

## Methods

### Life Table Construction

We use **Chiang's (1968) abridged life table method** with:

- **Age bands:** 5-year intervals (0-4, 5-9, ..., 85-89, 90+)
- **ax assumption:** Uniform distribution of deaths within bands (ax = n/2)
- **Open interval:** 90+ years (standard demographic practice)

### Cause-Deletion

For each of 10 cause groups, we compute the hypothetical life expectancy if that cause were eliminated using the proportional-hazard adjustment:

```
q*_i = 1 - (1 - q_i)^R_i
```

where R_i is the proportion of deaths NOT from the target cause in age band i.

### Confidence Intervals

Non-parametric bootstrap (999 resamples by default) with percentile-based 95% CIs. Resampling is stratified by province and sex.

---

## Interactive Atlas

The [RENTASALUD Interactive Atlas](https://watzilei.shinyapps.io/RENTA/) allows exploration of:

- Life expectancy by province and sex
- Income distribution at census-section level
- Temporal trends (2015-2022)

To run locally:

```r
shiny::runApp("Analysis/")
```

---

## Citation

If you use this code or data in your research, please cite:

> Luque-Fernandez MA, Masso Guijarro P, Rivas Gervilla G, Niksic M, Rivera Izquierdo M, Montero Alonso MA, Melchor Rodriguez JM. **RENTASALUD: A Web-Based Interactive Atlas of Social Inequalities and Life Expectancy in Andalusia (Southern Spain).** University of Granada; 2025. DOI: [10.5281/zenodo.21237758](https://doi.org/10.5281/zenodo.21237758)

**BibTeX:**

```bibtex
@misc{luquefernandez2025rentasalud,
  author       = {Luque-Fernandez, Miguel Angel and
                  Masso Guijarro, Paloma and
                  Rivas Gervilla, Gustavo and
                  Niksic, Maja and
                  Rivera Izquierdo, Mario and
                  Montero Alonso, Miguel Angel and
                  Melchor Rodriguez, Juan Manuel},
  title        = {{RENTASALUD: A Web-Based Interactive Atlas of Social
                   Inequalities and Life Expectancy in Andalusia}},
  year         = {2025},
  publisher    = {Zenodo},
  doi          = {10.5281/zenodo.21237758},
  url          = {https://doi.org/10.5281/zenodo.21237758}
}
```

---

## Authors

**Universidad de Granada:**
- [Miguel Angel Luque-Fernandez](https://github.com/migariane) (Principal Investigator)
- Gustavo Rivas Gervilla
- Paloma Masso Guijarro
- Mario Rivera Izquierdo
- Miguel Angel Montero Alonso
- Juan Manuel Melchor Rodriguez

**International Collaboration:**
- Maja Niksic (Centre for Health Services Studies, University of Kent)

---

## Funding

This work was supported by the **Plan Propio de Investigacion y Transferencia**, University of Granada (2025, Programa 21).

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Contributing

Contributions are welcome! Please read our [Contributing Guidelines](CONTRIBUTING.md) before submitting a pull request.

---

## Acknowledgements

We thank the Instituto de Estadistica y Cartografia de Andalucia (IECA) for providing access to the BDLPA microdata, and the Instituto Nacional de Estadistica (INE) for the publicly available income atlas and cartographic data.

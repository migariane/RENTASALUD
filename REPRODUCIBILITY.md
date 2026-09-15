# RENTASALUD Reproducibility Checklist

This document ensures the analysis outputs match the manuscript figures.

## Pre-flight Checklist

Before running the pipeline, verify:

- [ ] **Real data files present** in `Datos/`:
  - `mp11.txt` (~49 MB, ~637,000 lines)
  - `smp11cau.txt` (~11 MB, ~598,600 lines)
  - `datos_rentapop_long.csv` (income atlas, ~47,466 section-years)

- [ ] **Environment variable NOT set**:
  ```bash
  # This should return empty:
  echo $RENTASALUD_CI_MODE
  ```
  If set to "true", outputs go to `Resultados/test_run/` (synthetic data).

## Running the Pipeline

```bash
cd RENTASALUD/Analysis
Rscript 00_run_all.R
```

Expected runtime: ~5-10 minutes (bootstrap dominates).

## Post-run Verification

### 1. Life Expectancy at Birth (Article Abstract & Results)

Check `Resultados/ev_bootstrap_ci.csv`:

| Stratum | Expected LE | Expected 95% CI |
|---------|-------------|-----------------|
| Andalucía, Hombres | 79.53 | 79.36–79.69 |
| Andalucía, Mujeres | 84.35 | 84.19–84.51 |
| Andalucía, Ambos | 81.98 | 81.87–82.11 |

```bash
grep "Andalucia" Resultados/ev_bootstrap_ci.csv
```

### 2. Provincial Range (Article Results)

Check `Resultados/ev_por_provincia_ancho.csv`:

| Province | Men LE | Women LE | Both LE |
|----------|--------|----------|---------|
| Almería (lowest) | 77.67 | 80.87 | 79.29 |
| Córdoba (highest) | 80.06 | 85.34 | 82.75 |

Provincial spread should be ~3.5 years (79.29 to 82.75).

### 3. Cause-Deleted Gains (Article Table 1)

Check `Resultados/ganancia_esperanza_vida_por_causa.csv`:

| Cause | Men Gain | Women Gain |
|-------|----------|------------|
| Malignant tumours | 3.93 | 2.83 |
| Circulatory diseases | 3.15 | 2.89 |
| Respiratory diseases | 1.13 | 0.69 |
| External causes | 0.67 | 0.33 |

### 4. Sample Size (Article Methods)

Check that `ev_por_provincia_sexo.csv` shows realistic counts:

```bash
awk -F',' 'NR>1 {sum+=$4} END {print "Total persons:", sum}' \
  Resultados/ev_por_provincia_sexo.csv
```

Expected: ~598,600 persons (not ~500 from synthetic data).

## Known Failure Modes

### 1. Synthetic Data Overwrite

**Symptom:** Life expectancy values ~20-35 years, `n_personas` ~50-70 per stratum.

**Cause:** Pipeline ran without `RENTASALUD_CI_MODE=true` but with synthetic test data in `Datos/` instead of real BDLPA data.

**Fix:**
```bash
# Remove corrupted outputs
rm Resultados/*.csv Resultados/*.png

# Ensure real data is in Datos/
ls -la Datos/mp11.txt  # Should be ~49 MB

# Re-run pipeline
cd Analysis && Rscript 00_run_all.R
```

### 2. CI Mode Enabled Accidentally

**Symptom:** Outputs in `Resultados/test_run/` instead of `Resultados/`.

**Cause:** `RENTASALUD_CI_MODE=true` was set.

**Fix:**
```bash
unset RENTASALUD_CI_MODE
Rscript 00_run_all.R
```

### 3. Bootstrap CI File Mismatch

**Symptom:** `ev_bootstrap_ci.csv` values don't match `ev_por_provincia_sexo.csv`.

**Cause:** Files from different pipeline runs (one correct, one corrupted).

**Fix:** Delete all outputs and re-run from clean state.

## Automated Verification Script

Save as `scripts/verify_outputs.R`:

```r
#!/usr/bin/env Rscript
# Verify RENTASALUD outputs match manuscript claims

ev_ci <- read.csv("../Resultados/ev_bootstrap_ci.csv")
ev_prov <- read.csv("../Resultados/ev_por_provincia_sexo.csv")
causas <- read.csv("../Resultados/ganancia_esperanza_vida_por_causa.csv")

# Check 1: Andalucía LE at birth
and_h <- ev_ci[ev_ci$provincia == "Andalucia" & ev_ci$sexo == "Hombres", "punto"]
and_m <- ev_ci[ev_ci$provincia == "Andalucia" & ev_ci$sexo == "Mujeres", "punto"]
stopifnot(abs(and_h - 79.53) < 0.1)
stopifnot(abs(and_m - 84.35) < 0.1)
cat("✓ Andalucía LE matches manuscript\n")

# Check 2: Sample size realistic
total_n <- sum(ev_prov$n_personas)
stopifnot(total_n > 500000)  # Should be ~598,600
cat("✓ Sample size realistic:", total_n, "\n")

# Check 3: Cause-deleted gains
tumor_h <- causas[causas$sexo == "Hombres" & 
                  grepl("Tumor", causas$causa), "ganancia_anos"]
stopifnot(abs(tumor_h - 3.93) < 0.1)
cat("✓ Cause-deleted gains match manuscript\n")

# Check 4: Provincial spread
prov_range <- max(ev_prov$esperanza_vida_nacer) - min(ev_prov$esperanza_vida_nacer)
stopifnot(prov_range > 3 && prov_range < 10)
cat("✓ Provincial spread reasonable:", round(prov_range, 1), "years\n")

cat("\n✅ All verification checks passed!\n")
```

## File Manifest

After a successful production run, `Resultados/` should contain:

| File | Rows | Key Columns |
|------|------|-------------|
| `ev_bootstrap_ci.csv` | 27 | provincia, sexo, punto, ic95_inf, ic95_sup |
| `ev_por_provincia_sexo.csv` | 16 | provincia, sexo, esperanza_vida_nacer, n_personas |
| `ev_por_provincia_ancho.csv` | 8 | provincia, EV_Hombres, EV_Mujeres, EV_Ambos |
| `ev_por_provincia_ambos_sexos.csv` | 9 | provincia, sexo, esperanza_vida_nacer |
| `ganancia_esperanza_vida_por_causa.csv` | 20 | sexo, causa, ganancia_anos |
| `tabla_vida_hombres.csv` | 19 | banda, anos_persona, muertes, esperanza_vida |
| `tabla_vida_mujeres.csv` | 19 | banda, anos_persona, muertes, esperanza_vida |
| `renta_por_provincia.csv` | 8 | Provincia, Renta_Media_Ponderada |
| `correlaciones_renta_ev.csv` | 3 | sexo, r_pearson, p_pearson |
| `sensibilidad_leave_one_out.csv` | 24 | sexo, excluida, r_pearson |
| `grafico_ganancia_por_causa.png` | — | Horizontal barplot |

## Contact

If outputs still don't match after following this checklist, contact:
- Miguel Ángel Luque-Fernández (mluquefe@ugr.es)

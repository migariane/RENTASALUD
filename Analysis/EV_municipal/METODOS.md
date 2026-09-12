# Análisis municipal de esperanza de vida — METODOLOGÍA (RENTASALUD)

> Documento de métodos que acompaña a `01_analisis_ev_municipal.R`.
> Describe, paso a paso, la gestión de datos, el análisis estadístico y los
> resultados del cálculo de esperanza de vida al nacer (e(0)) a escala
> municipal en Andalucía y su relación con la renta mediana municipal.

---

## 1. Datos y fuentes

| Fuente | Contenido | Registros |
|---|---|---|
| `Datos/mp11.txt` | Personas del Panel de Demografía Laboral / BDLPA (padrón, INSS) | 637.404 |
| `Datos/smp11cau.txt` | Seguimiento del panel + causa de defunción | 637.404 |
| `SHP/seccionado_2018` | Secciones censales INE 2018 (códigos oficiales) | — |
| `SHP/seccionado_2022` | Secciones censales INE 2022 (cartografía municipal) | — |
| `datos_rentapop_long.RData` | Renta mediana por unidad de consumo (ADRH, INE) y población por sección, 2015-2022 | 6.136 secciones × 8 años |

**Período de seguimiento:** del censo de 2011 (fecha de referencia `2011 + 305/366`)
hasta el final del seguimiento (máximo 2023). Cada persona contribuye a la
exposición desde la fecha censal hasta su salida del panel.

---

## 2. Gestión de datos (data management)

### 2.1 Descubrimiento del formato real de `mp11.txt`

El archivo está documentado como de anchura fija, pero dos campos pierden sus
ceros a la izquierda y por tanto tienen anchura variable:

* **FELEV** (factor de elevación ×10⁶): no se necesita en este análisis.
* **MUNICIPIO** (3 dígitos esperados): pierde su(s) cero(s) inicial(es), de modo
  que se almacena con **1, 2 o 3 caracteres**. Por el contrario, **PROVINCIA**,
  **DISTRITO**, **SECCION** y **ZONA** conservan anchura fija (2, 2, 3 y 2).

El parser de la provincia no era suficiente para recuperar el municipio: una
simple búsqueda de un código de provincia válido antes de FNAC atribuía mal
~20 % de los registros (capturaba dígitos de FELEV o del propio municipio).

### 2.2 Algoritmo de recuperación del municipio

Para cada registro, con FNAC como ancla (posición verificada frente a fechas de
nacimiento reales):

```
F     = 28 + (longitud - 79)      # posición (1-based) del inicio de FNAC
prov1 = F - 9 - mw                # posición del código de provincia, para cada
                                  # anchura posible mw ∈ {1, 2, 3} del municipio
geo   = caracteres prov1+2 .. F-1 # bloque MUN+DIS+SEC+ZONA
```

Un candidato `(mw)` es válido si se cumplen simultáneamente:

1. PROVINCIA es uno de los 8 códigos andaluces (04, 11, 14, 18, 21, 23, 29, 41);
2. el municipio `PROV + sprintf("%03d", MUN)` existe en los códigos oficiales
   INE de 2018 (`MUN_REAL`, 778 municipios);
3. ZONA es un entero entre 1 y 34 (zonas POTA);
4. la longitud del bloque geográfico es exactamente `mw + 7`.

**Asignación:**

* **Pase 1 — parses únicos (86,3 %)**: registros con exactamente un candidato
  válido.
* **Pase 2 — desambiguación de los 87.009 restantes**, en orden:
  1. se conservan solo los candidatos cuya sección censal completa
     `PROV+MUN+DIS+SEC` existe en el fichero INE 2018;
  2. si sigue habiendo más de uno, se conservan solo los candidatos cuya zona
     POTA coincide con la del municipio (mapa determinista municipio→zona
     construido con los parses únicos del pase 1; 673 municipios mapeados).

**Asignación final: 95,2 %** de los 637.404 registros. El 4,8 % restante no se
puede resolver de forma unívoca y se descarta del análisis.

### 2.3 Validación del parseo

| Comprobación | Resultado |
|---|---|
| SEXO solo toma los códigos INE 1 y 6 | Sí (310.326 hombres, 327.078 mujeres) |
| Municipios con zona POTA internamente inconsistente | 6 (de 673) |
| Correlación log-log recuento-muestra vs población INE municipal | **0,93** |
| Correlación de Spearman | **0,926** |
| Municipios usados en la validación | 724 |

La correlación casi perfecta entre los efectivos recuperados por municipio y la
población oficial confirma que el parseo es correcto en su conjunto. Las
desviaciones provinciales (p. ej., Almería 8,4 % recuperado vs 8,4 % censal;
Málaga 17,8 % vs 19,3 %) reflejan pérdidas de vínculo genuinas del BDLPA
(residentes extranjeros en la Costa del Sol), no errores de parseo.

### 2.4 Archivo de seguimiento `smp11cau.txt`

Anchura fija de 17 caracteres por línea: ID (1-6), ABAJA (7-10, año de salida),
DECAB (11, décima de año), TIPOB (12, motivo de salida) y CODCAU (13-17, causa
de defunción).

* TIPOB: 1 = defunción (68.326), 2 = baja por transferencia (36.672),
  3 = vivo al final del seguimiento (532.406).
* 38.801 personas (6,1 %) no tienen registro de seguimiento y se excluyen.
* **Cohorte final: 598.603 personas** (3 eliminadas por inconsistencias de edad).

### 2.5 Agrupación de causas de muerte

Se usa el primer dígito del par de la causa CODCAU. Todos los códigos del
fichero caen en uno de los 10 grupos (verificado; no hay códigos desconocidos):

| Código | Grupo | Defunciones |
|---|---|---|
| 01 | Circulatorio | 20.531 |
| 02 | Tumores | 17.151 |
| 10 | Resto de causas | 9.534 |
| 05 | Respiratorio | 6.988 |
| 07 | Nervioso | 3.681 |
| 06 | Digestivo | 3.452 |
| 04 | Infecciosas | 2.512 |
| 03 | Endocrino | 2.191 |
| 08 | Causas externas | 2.094 |
| 09 | Relacionadas con alcohol | 192 |

---

## 3. Análisis estadístico

### 3.1 Años-persona de exposición

Se distribuye el intervalo de seguimiento de cada persona
`[edad_entrada, edad_salida]` en bandas de edad de 5 años (0-4 … 85-89) más la
abierta 90+, mediante el solape vectorizado:

```
overlap_ij = max(0, min(edad_salida, sup_j) − max(edad_entrada, inf_j))
```

Total: **6,73 millones de años-persona**. Los fallecidos se asignan a la banda
de salida con `cut(edad_salida)`.

### 3.2 Tablas de vida municipales (Chiang, 1968)

Para cada estrato municipio×sexo (y sexos combinados) con datos suficientes se
construye una tabla de vida abreviada:

* Tasa de mortalidad en la banda: `M_x = D_x / PY_x`.
* Probabilidad de muerte en la banda (Chiang): `q_x = n·M_x / (1 + a_x·M_x)`
  con `a_x = n/2` (distribución uniforme de las defunciones) y
  `q_x = 1` en el intervalo abierto.
* Columnas clásicas `l_x, d_x, L_x, T_x`; el intervalo abierto usa
  `L_abierto = l_abierto / M_abierto`.
* **Esperanza de vida al nacer**: `e(0) = T_0 / l_0`.

**Reglas de fiabilidad para muestras pequeñas** (clave a escala municipal):

1. **Mínimo de defunciones**: ≥ 30 por sexo (≥ 40 sexos combinados).
2. **Mortalidad anciana observada**: ≥ 3 defunciones a los 80+ años. Un estrato
   sin ninguna defunción a edades altas (p. ej., algunos municipios costeros de
   Almería con muestras BDLPA sin ancianos fallecidos) devolvería una e(0)
   absurda (miles de años), porque la mortalidad del intervalo abierto se
   estimaría ≈ 0.
3. **Suelo del intervalo abierto**: `M(90+) ≥ 0,15` (equivale a una vida
   restante a los 90 de ≤ ~6,7 años; la mortalidad española a 90+ es ~0,2-0,3).
   Evita la explosión del tramo abierto en estratos con pocas defunciones
   ancianas.
4. **Corte de probabilidades**: `q_x ∈ [0,1]` (cuando `M_x > 0,4` la fórmula de
   Chiang supera 1; se recorta para que la columna de supervivientes no sea
   negativa).

> **Justificación estadística del suelo (ref G1, `gpai_workflow/REGISTRO_GPAI.md`):**
> el estimador del tramo abierto `e_open = 1/M_open` tiene, con defunciones
> Poisson, sesgo ≈ `1/(Pλ²)` y varianza ≈ `1/(Pλ³)`; es inutilizable cuando
> `D(90+) = 0`. No existe una regla que minimice el MSE universalmente, así que
> `0,15` es una cota de estabilidad cercana a la tasa real española a 90+
> (e(90) ≈ 5-6 años). La tasa agrupada 85+ se intenta primero, pero cuando
> queda por debajo de `0,15` (caso habitual) el suelo la sustituye, porque
> agrupar 85-89 con 90+ **subestima** `M(90+)` (la mortalidad 85-89 < 90+).

**Resultado**: 461 tablas municipio×sexo (246 hombres, 215 mujeres) y 406
tablas sexos-combinados.

### 3.3 Esperanza de vida por causa (eliminación de causas)

Para estimar la e(0) sin la causa C se sustituye
`q_x` por `q*_x = 1 − (1 − q_x)^R_x`, donde `R_x` es la proporción de
defunciones en la banda NO debidas a C (método de eliminación de Chiang,
supuesto de independencia entre causas, igual que en el pipeline provincial).
La ganancia es `e(0) sin C − e(0)`.

### 3.4 Renta mediana municipal

Del Atlas de Distribución de Renta de los Hogares (INE) se toman los 6.136
códigos de sección andaluces (códigos de 10 dígitos; se rellena el cero inicial
perdido). La renta municipal se aproxima como la **media ponderada por
población** de las rentas medianas por unidad de consumo de sus secciones,
promediada sobre los 8 años disponibles (2015-2022; las secciones sin dato en
un año se omiten ese año). Cobertura: **776 de 778 municipios**.

### 3.5 Relación e(0) - renta

* **Correlación** de Pearson y Spearman entre e(0) municipal y renta mediana.
* **Regresión lineal** ponderada por población (pendiente en años por 1.000 €).
* **Quintiles de renta**: los municipios con e(0) válida y renta se ordenan por
  renta y se dividen en 5 grupos (Q1 = 20 % más pobre, Q5 = 20 % más rico). Para
  cada quintil se reporta la **e(0) media ponderada por población**. El resultado
  principal es la **diferencia Q5 − Q1** en años de vida.
* **Test t de Welch** comparando las e(0) municipales de Q1 y Q5 (no ponderado).

---

## 4. Resultados

### 4.1 Esperanza de vida municipal

| Indicador | Hombres | Mujeres |
|---|---|---|
| Mediana | 79,7 | 85,0 |
| Media | 78,8 | 83,8 |
| Rango | 57,3 – 85,9 | 59,1 – 89,8 |

Municipios con e(0): 246 (hombres), 215 (mujeres); 197 con ambos sexos
(necesarios para el análisis de quintiles).

### 4.2 Correlación con la renta

| Variable | n | Pearson | Spearman | Pendiente (años/1.000 €) |
|---|---|---|---|---|
| Ambos sexos | 197 | 0,122 | 0,181 | 0,43 |
| Hombres | 197 | 0,146 | 0,173 | 0,49 |
| Mujeres | 197 | 0,073 | 0,103 | 0,32 |

Existe una asociación **positiva aunque modesta** entre la renta municipal y la
esperanza de vida; es algo más fuerte en hombres que en mujeres.

### 4.3 Esperanza de vida por quintil de renta municipal

| Quintil | Municipios | Renta mediana (€/UC) | e(0) ambos | e(0) hombres | e(0) mujeres |
|---|---|---|---|---|---|
| Q1 (más pobre) | 40 | 10.860 | 80,2 | 77,9 | 82,7 |
| Q2 | 40 | 11.549 | 81,6 | 78,9 | 84,4 |
| Q3 | 39 | 12.105 | 81,5 | 78,8 | 84,1 |
| Q4 | 39 | 12.666 | 80,2 | 77,4 | 82,9 |
| Q5 (más rico) | 39 | 14.169 | 82,7 | 80,4 | 84,9 |

**Diferencia Q5 − Q1 (media ponderada por población):**

* Ambos sexos: **+2,48 años**
* Hombres: **+2,51 años**
* Mujeres: **+2,22 años**

**Test t de Welch (e(0) municipal, Q5 vs Q1):** diferencia **+2,12 años**,
p = 0,0127 (significativa al 5 %).

> Los municipios del quintil más rico viven ~2,1-2,5 años más que los del más
> pobre. La relación no es estrictamente monótona (Q2 y Q3 por encima de Q4),
> lo que refleja el ruido de los estimadores municipales de muestras pequeñas.

### 4.4 Ganancia de e(0) por causa eliminada (media municipal, ponderada por defunciones)

| Causa | Hombres (años) | Mujeres (años) |
|---|---|---|
| Tumores | 3,52 | 2,43 |
| Circulatorio | 2,69 | 2,46 |
| Respiratorio | 0,98 | 0,57 |
| Resto de causas | 0,93 | 0,96 |
| Digestivo | 0,49 | 0,42 |
| Causas externas | 0,44 | 0,26 |
| Nervioso | 0,41 | 0,52 |
| Infecciosas | 0,36 | 0,31 |
| Endocrino | 0,24 | 0,26 |
| Alcohol | 0,06 | 0,01 |

Los **tumores y el sistema circulatorio** concentran la mayor parte del
potencial de ganancia de vida, con un peso algo mayor de los tumores en
hombres y del circulatorio en mujeres.

### 4.5 Salidas generadas (`salidas/`)

| Archivo | Contenido |
|---|---|
| `personas_municipal.rds` | Cohortes depurada (BDLPA + seguimiento + municipio) |
| `esperanza_vida_municipal.csv` | e(0) por municipio y sexo (ancho) |
| `tabla_vida_municipal_sexo.csv` | e(0) por municipio y sexo (largo, con defunciones y años-persona) |
| `esperanza_vida_causa_municipal.csv` | Ganancia por causa eliminada, municipio × sexo |
| `renta_mediana_municipal.csv` | Renta mediana por UC por municipio |
| `correlaciones_ev_renta.csv` | Correlaciones y pendientes |
| `ev_por_quintil.csv` | e(0) por quintil de renta |
| `mapa_ev_hombres.png`, `mapa_ev_mujeres.png`, `mapa_renta_mediana.png` | Cartogramas municipales |
| `mapa_ev_quintiles_Q1_Q5.png` | Mapa de Andalucía con e(0) completa y los municipios de Q1 y Q5 resaltados con contorno negro (Q1 a la izquierda, Q5 a la derecha) |
| `ev_renta_municipal.csv` | e(0), renta y quintil por municipio (para mapeo) |
| `scatter_ev_renta.png` | Dispersión e(0) vs renta |
| `ev_por_quintil.png` | e(0) por quintil |
| `ev_causa_sexo.png` | Ganancia media por causa y sexo |

---

## 5. Limitaciones

1. **Muestras municipales pequeñas**: 12 años de seguimiento dejan ~30-70
   defunciones por estrato de sexo en los municipios medianos; las tablas de
   vida directas son ruidosas y solo se construyen para municipios que superan
   los umbrales de fiabilidad (461 de 1.452 estratos). Los municipios pequeños
   quedan fuera del análisis.
2. **Pérdidas de vínculo del BDLPA**: no todas las defunciones se vinculan
   (especialmente en municipios con mucha población extranjera); si la pérdida
   es diferencial por municipio o por edad, introduce sesgo.
3. **Renta municipal aproximada**: la media ponderada de medianas por sección no
   es la mediana municipal exacta; los cambios a lo largo de 2015-2022 se
   promedian.
4. **Independencia de causas** en el análisis de eliminación (asumida, como en
   el pipeline provincial).
5. **Censo 2011 vs renta 2015-2022**: la cohorte parte del censo 2011 y la renta
   se mide después; la asociación e(0)-renta es ecológica (a nivel de municipio)
   y no debe interpretarse como causal.

---

## 6. Cómo reproducir

```bash
cd Analysis
Rscript EV_municipal/01_analisis_ev_municipal.R
```

Requiere los paquetes `dplyr`, `tidyr`, `sf`, `ggplot2`, `scales`, `patchwork`
y los datos en las rutas del apartado 1. El script genera automáticamente todos
los archivos de `salidas/` y reescribe el log completo por consola.

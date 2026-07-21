## =============================================================================
##  RENTASALUD — Reproducible Analysis Pipeline
##  =============================================================================
##  Single integrated script for reproducibility.
##  Combines: optimize_maps.R + pipeline_esperanza_vida_por_causa.R + global.R
##
##  Outputs: (see Paso 9 for full list)
##    - Tablas de vida (hombres/mujeres)
##    - Ganancia de EV por causa
##    - EV por provincia y sexo
##    - Shapefiles optimizados para la app Shiny
##
##  How to run:
##    cd RENTASALUD/Analysis
##    Rscript 00_run_all.R
## =============================================================================

## ---------------------------------------------------------------------------
## 0. Configuration: paths and parameters
## ---------------------------------------------------------------------------

ruta_mp11     <- "/mnt/user-data/uploads/mp11.txt"       # muestra censal de personas 2011
ruta_smp11cau <- "/mnt/user-data/uploads/smp11cau.txt"   # fichero de seguimiento + causa

# Fecha de referencia del Censo de 2011 (1 de noviembre de 2011)
FECHA_CENSO <- 2011 + 305/366

# Bandas de edad para tablas de vida (5 años, última abierta en 90+)
CORTES_EDAD <- c(seq(0, 90, by = 5), 120)

# Provincias andaluzas (códigos INE)
codigos_andalucia <- c("04", "11", "14", "18", "21", "23", "29", "41")

# Etiquetas de las bandas de edad
etiquetas_banda <- c(paste(seq(0, 85, by = 5), seq(4, 89, by = 5), sep = "-"), "90+")
n_bandas <- length(etiquetas_banda)

# Directorio de salida
dir.create("/mnt/user-data/outputs", showWarnings = FALSE)

cat("=", strrep("=", 69), "\n")
cat("  RENTASALUD — Reproducible Analysis Pipeline\n")
cat("=", strrep("=", 69), "\n\n")

library(dplyr)
library(sf)

## =============================================================================
## PARTE A: Optimización de shapefiles para la app
## =============================================================================

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

cat("\n", strrep("-", 50), "\n")
cat("  PARTE B: Esperanza de vida (BDLPA)\n")
cat("", strrep("-", 50), "\n")

## ---------------------------------------------------------------------------
## B1. Leer fichero de personas (mp11.txt)
## ---------------------------------------------------------------------------

lineas <- readLines(ruta_mp11, encoding = "latin1")
cat("  Personas en mp11.txt:", length(lineas), "\n")

longitud_linea <- nchar(lineas)
desplazamiento <- longitud_linea - 79L
pos_fnac <- (28 - 1) + desplazamiento

FNAC <- as.numeric(substr(lineas, pos_fnac + 1, pos_fnac + 5)) / 10
SEXO <- substr(lineas, pos_fnac + 6, pos_fnac + 6)
ID   <- substr(lineas, 1, 6)

codigos_provincia_validos <- codigos_andalucia
localizar_provincia <- function(linea, p0) {
  for (inicio in (max(0, p0 - 20)):(p0 - 10)) {
    candidato <- substr(linea, inicio + 1, inicio + 2)
    if (candidato %in% codigos_provincia_validos) return(candidato)
  }
  return(NA_character_)
}
PROVINCIA <- mapply(localizar_provincia, lineas, pos_fnac)

cat("  Comprobación SEXO:\n")
print(table(SEXO))
cat("  Comprobación PROVINCIA:\n")
print(table(PROVINCIA, useNA = "ifany"))

mp11 <- data.frame(ID = ID, PROVINCIA = PROVINCIA, FNAC = FNAC, SEXO = SEXO,
                    stringsAsFactors = FALSE)

## ---------------------------------------------------------------------------
## B2. Leer fichero de seguimiento (smp11cau.txt)
## ---------------------------------------------------------------------------

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
## B3. Unir ambos ficheros
## ---------------------------------------------------------------------------

datos <- merge(mp11, smp11, by = "ID", all.x = TRUE)
n_sin_seguimiento <- sum(is.na(datos$TIPOB))
cat("\n  Personas sin seguimiento (excluidas):", n_sin_seguimiento, "\n")
datos <- datos[!is.na(datos$TIPOB), ]
cat("  Personas en análisis:", nrow(datos), "\n")

## ---------------------------------------------------------------------------
## B4. Calcular edad de entrada y salida
## ---------------------------------------------------------------------------

datos$edad_entrada <- FECHA_CENSO - datos$FNAC
datos$fecha_salida <- datos$ABAJA + datos$DECAB / 10 + 0.05
datos$edad_salida  <- datos$fecha_salida - datos$FNAC

antes <- nrow(datos)
datos <- datos[datos$edad_salida >= datos$edad_entrada &
                 datos$edad_entrada >= 0 & datos$edad_salida <= 115, ]
cat("  Filas eliminadas por inconsistencias de edad:", antes - nrow(datos), "\n")

# Gran grupo de causa
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
## B5. Años-persona por banda de edad
## ---------------------------------------------------------------------------

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
## B6. Construir tabla de vida (Chiang, 1968)
## ---------------------------------------------------------------------------

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
## B7. Resultados: EV por sexo (toda Andalucía)
## ---------------------------------------------------------------------------

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
## B8. Ganancia de EV si se elimina cada causa
## ---------------------------------------------------------------------------

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
## B9. EV por provincia y sexo
## ---------------------------------------------------------------------------

cat("\n\n", strrep("=", 55), "\n")
cat("  EV AL NACER POR PROVINCIA Y SEXO\n")
cat("", strrep("=", 55), "\n")

nombres_provincia <- c(
  "04" = "Almeria", "11" = "Cadiz", "14" = "Cordoba", "18" = "Granada",
  "21" = "Huelva",  "23" = "Jaen",  "29" = "Malaga",  "41" = "Sevilla"
)

construir_tabla_vida_provincia <- function(codigo_provincia, sexo_codigo) {
  es_prov <- datos$PROVINCIA == codigo_provincia
  es_sexo <- datos$SEXO == sexo_codigo
  idx <- es_prov & es_sexo
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

cat("\n\n", strrep("-", 50), "\n")
cat("  PARTE C: Guardar resultados\n")
cat("", strrep("-", 50), "\n")

out_dir <- "/mnt/user-data/outputs"

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

## =============================================================================
##  ESPERANZA DE VIDA POR CAUSA DE MUERTE, EDAD Y SEXO
##  Guía comentada paso a paso — Estadísticas Longitudinales de Supervivencia
##  y Longevidad en Andalucía (BDLPA), cohorte censal 2011
## =============================================================================
##
##  FUENTE DE DATOS PRINCIPAL:
##    BDLPA — Base de Datos Longitudinal de Población de Andalucía
##    Estadísticas Longitudinales de Supervivencia y Longevidad, 2002–2023
##    Instituto de Estadística y Cartografía de Andalucía (IECA)
##    Documentación: Datos/INFOBDLA/microdatos-Descripcion_varaibles_2011.pdf
##                   Datos/INFOBDLA/DisenoDeRegistroMicrodatos.ods
##
##  FICHEROS DE ENTRADA:
##    mp11.txt       ~49 MB — Muestra censal de personas (Censo 2011, ~637k registros)
##        Columnas principales: ID (6 dígitos), FNAC (fecha nacimiento ×10),
##        SEXO (1=hombre, 6=mujer), PROVINCIA (2 dígitos INE)
##    smp11cau.txt   ~11 MB — Seguimiento + causa de muerte (ancho fijo, 17 chars)
##        Columnas: ID, ABAJA (año baja), DECAB (décima), TIPOB (1=fallecido,
##        2=traslado, 3=vivo), CODCAU (código causa, 5 dígitos)
##
##  FUENTE DE DATOS SECUNDARIA (para la app Shiny):
##    Atlas de Distribución de Renta de los Hogares (ADRH), INE, 2015–2022
##    Documentación: Datos/INFORENTA/Renta_media_Definiciones.pdf
##
##  Este script está pensado para alguien que:
##    - Sabe algo de R pero no es programador/a profesional.
##    - No tiene por qué conocer conceptos de demografía o epidemiología.
##
##  Por eso, cada bloque de código va precedido de una explicación en
##  castellano llano de QUÉ vamos a hacer y POR QUÉ. Cuando aparezca un
##  término técnico nuevo (p.ej. "años-persona", "tabla de vida"), lo
##  definimos la primera vez que se usa, con un ejemplo pequeño antes de
##  aplicarlo a los datos reales.
##
##  IDEA GENERAL DEL PROBLEMA (léela antes de tocar el código)
##  ------------------------------------------------------------------
##  Tenemos una muestra de personas del Censo de 2011 (fichero mp11.txt)
##  a las que se ha hecho seguimiento hasta el 31-12-2023 (fichero
##  smp11cau.txt): sabemos si siguen vivas, si se han ido de Andalucía,
##  o si han fallecido y, en ese caso, de qué causa.
##
##  Con esa información NO podemos simplemente hacer la media de la edad
##  a la que muere la gente (eso estaría muy sesgado: mucha gente joven
##  en 2011 seguirá viva en 2023, así que "no ha tenido tiempo" de morir
##  todavía). La forma correcta de resumir esto es construir una TABLA DE
##  VIDA: una tabla que, para cada edad, estima la probabilidad de morir
##  en el año siguiente, y a partir de esas probabilidades calcula la
##  ESPERANZA DE VIDA (años que le quedarían por vivir a una persona de
##  esa edad, si las condiciones actuales de mortalidad se mantuvieran).
##
##  Para "quitar" una causa de muerte del cálculo (y ver cuánto ganaría
##  la esperanza de vida si esa causa no existiera) usamos un método
##  clásico de demografía llamado el MÉTODO DE CHIANG (1968), que
##  explicamos en el Paso 6.
##
## =============================================================================


## =============================================================================
## PASO 0. Rutas a los ficheros y parámetros generales
## =============================================================================
##
##  ESTRUCTURA DE DIRECTORIOS:
##    RENTASALUD/
##    ├── Analysis/                         ← directorio de trabajo (este script)
##    │   ├── pipeline_esperanza_vida_por_causa.R
##    │   ├── 00_run_all.R
##    │   ├── app.R / global.R
##    │   └── SHP/ / SHP_opt/
##    ├── Datos/                            ← datos brutos
##    │   ├── mp11.txt           (~49 MB)   Muestra censal de personas 2011
##    │   ├── smp11cau.txt       (~11 MB)   Seguimiento y causa de muerte
##    │   ├── INFORENTA/                    Metadatos de renta (PDF/XLSX)
##    │   └── INFOBDLA/                     Metadatos BDLPA (PDF/ODS)
##    └── Resultados/                       ← salida de este script
##        ├── ev_por_provincia_ancho.csv
##        ├── ganancia_esperanza_vida_por_causa.csv
##        ├── tabla_vida_hombres.csv / tabla_vida_mujeres.csv
##        └── grafico_ganancia_por_causa.png
##
##  FUENTE DE LOS MICRODATOS:
##    BDLPA — Base de Datos Longitudinal de Población de Andalucía
##    (Estadísticas Longitudinales de Supervivencia y Longevidad)
##    Cohortes censales 2001 y 2011, con seguimiento hasta 2023.
##    Instituto de Estadística y Cartografía de Andalucía (IECA).
##    Documentación: Datos/INFOBDLA/microdatos-Descripcion_varaibles_2011.pdf

# Auto-detección de rutas: servidor (Shiny Server / shinyapps.io) vs local
if (dir.exists("/mnt/user-data/uploads")) {
  # Entorno de servidor desplegado
  ruta_mp11     <- "/mnt/user-data/uploads/mp11.txt"
  ruta_smp11cau <- "/mnt/user-data/uploads/smp11cau.txt"
  ruta_salida   <- "/mnt/user-data/outputs"
} else {
  # Entorno local de desarrollo
  ruta_mp11     <- "../Datos/mp11.txt"
  ruta_smp11cau <- "../Datos/smp11cau.txt"
  ruta_salida   <- "../Resultados"
}
stopifnot(file.exists(ruta_mp11))
stopifnot(file.exists(ruta_smp11cau))
dir.create(ruta_salida, showWarnings = FALSE, recursive = TRUE)

# Fecha de referencia del Censo de 2011 (1 de noviembre de 2011), expresada
# como año con decimales: el 1 de noviembre es aproximadamente el día 305
# del año, así que 2011 + 305/366 =~ 2011.83
FECHA_CENSO <- 2011 + 305/366

# Anchura de las bandas de edad que usaremos en la tabla de vida (en años).
# Usamos bandas de 5 años, y la última banda queda "abierta" (90 años o más).
CORTES_EDAD <- c(seq(0, 90, by = 5), 120)


## =============================================================================
## PASO 1. Leer el fichero de personas (mp11.txt)
## =============================================================================
##
##  Este fichero es de "ancho fijo": cada variable ocupa siempre las mismas
##  columnas de texto dentro de cada línea (no hay comas ni tabulaciones
##  separando los valores). El diseño oficial (el .ods que acompaña a los
##  datos) dice en qué columna empieza cada variable.
##
##  PROBLEMA A RESOLVER: si lees el fichero tal cual, verás que las líneas
##  no tienen todas la misma longitud (algunas 76 caracteres, otras 77, 78
##  o 79). Esto ocurre porque el campo FELEV (el "factor de elevación", es
##  decir, el peso muestral de cada persona) se ha guardado como un número
##  sin ceros a la izquierda, así que ocupa más o menos caracteres según su
##  valor. Como consecuencia, TODAS las columnas que van después de FELEV
##  se desplazan una cantidad distinta en cada línea.
##
##  SOLUCIÓN: en lugar de fiarnos ciegamente de la columna que dice el
##  diseño oficial, usamos una variable que sabemos identificar sin
##  ambigüedad como "ancla": la fecha de nacimiento (FNAC). FNAC es un
##  número de 5 cifras que representa "año de nacimiento x 10" (p.ej.
##  1964.1 se guarda como 19641). Sabemos que ese valor SIEMPRE está
##  entre 18800 (año 1880.0) y 20120 (año 2012.0), así que podemos
##  localizarlo mirando la longitud de cada línea. Una vez localizado
##  FNAC, el resto de columnas (sexo, provincia, etc.) están siempre a
##  una distancia fija de él, así que las podemos recortar sin error.
##
##  No hace falta que entiendas todos los detalles de este truco para
##  seguir el resto del script: lo importante es el resultado, que
##  comprobamos justo después (SEXO solo debe tener los valores 1 y 6).

lineas <- readLines(ruta_mp11, encoding = "latin1")
cat("Número de personas en mp11.txt:", length(lineas), "\n")

longitud_linea <- nchar(lineas)

# Desplazamiento de la posición de FNAC en cada línea, calculado a partir
# de la longitud total de la línea (encontrado de forma empírica y
# comprobado sobre las 637.404 líneas del fichero).
desplazamiento <- longitud_linea - 79L
pos_fnac <- (28 - 1) + desplazamiento   # posición 0-indexada de inicio de FNAC

# En R, substr(x, inicio, fin) usa posiciones 1-indexadas e inclusivas,
# así que sumamos 1 al convertir desde la posición 0-indexada.
FNAC <- as.numeric(substr(lineas, pos_fnac + 1, pos_fnac + 5)) / 10
SEXO <- substr(lineas, pos_fnac + 6, pos_fnac + 6)
ID   <- substr(lineas, 1, 6)

# La PROVINCIA no guarda una distancia fija con FNAC (hay otro campo
# variable por delante), así que la localizamos buscando, en la zona
# donde debería estar, un código de 2 dígitos que sea uno de los 8
# códigos válidos de provincia andaluza.
codigos_provincia_validos <- c("04","11","14","18","21","23","29","41")

localizar_provincia <- function(linea, p0) {
  # p0 es la posición (0-indexada) de inicio de FNAC en esa línea.
  # Miramos la ventana de caracteres justo antes de FNAC.
  for (inicio in (max(0, p0 - 20)):(p0 - 10)) {
    candidato <- substr(linea, inicio + 1, inicio + 2)
    if (candidato %in% codigos_provincia_validos) return(candidato)
  }
  return(NA_character_)
}
PROVINCIA <- mapply(localizar_provincia, lineas, pos_fnac)

# --- Comprobación (muy importante: nunca te fíes de un parseo sin comprobarlo) ---
cat("\nComprobación SEXO (solo debería haber '1' y '6'):\n")
print(table(SEXO))
cat("\nComprobación PROVINCIA (deberían salir 8 códigos válidos, sin NA):\n")
print(table(PROVINCIA, useNA = "ifany"))

mp11 <- data.frame(ID = ID, PROVINCIA = PROVINCIA, FNAC = FNAC, SEXO = SEXO,
                    stringsAsFactors = FALSE)


## =============================================================================
## PASO 2. Leer el fichero de seguimiento y causa de muerte (smp11cau.txt)
## =============================================================================
##
##  Este fichero SÍ es de ancho fijo "de verdad" (todas las líneas miden
##  17 caracteres), así que no necesitamos ningún truco: recortamos
##  directamente según las posiciones del diseño oficial.
##
##  Contiene, para cada persona:
##    ABAJA  = año en que termina su seguimiento (año de "baja")
##    DECAB  = en qué décima parte de ese año ocurrió (0 a 9)
##    TIPOB  = por qué termina el seguimiento:
##               1 = ha fallecido
##               2 = se ha ido de Andalucía (dejamos de saber de ella)
##               3 = ha llegado el final del estudio (31-12-2023) con
##                   vida
##    CODCAU = causa de la muerte (solo si TIPOB = 1); un código como
##             "02_01" que corresponde a "Cáncer de estómago", etc.
##             (la tabla de equivalencias está en la pestaña
##             "Grupos_de_Causas" del diseño de registro)

lineas2 <- readLines(ruta_smp11cau, encoding = "latin1")
cat("\nNúmero de registros de seguimiento:", length(lineas2), "\n")
cat("¿Todas las líneas miden lo mismo? ->",
    length(unique(nchar(lineas2))) == 1, "\n")

smp11 <- data.frame(
  ID     = substr(lineas2, 1, 6),
  ABAJA  = as.integer(substr(lineas2, 7, 10)),
  DECAB  = as.integer(substr(lineas2, 11, 11)),
  TIPOB  = as.integer(substr(lineas2, 12, 12)),
  CODCAU = trimws(substr(lineas2, 13, 17)),
  stringsAsFactors = FALSE
)

cat("\nMotivo de salida del seguimiento (TIPOB):\n")
print(table(smp11$TIPOB))


## =============================================================================
## PASO 3. Unir los dos ficheros por el identificador de persona (ID)
## =============================================================================

datos <- merge(mp11, smp11, by = "ID", all.x = TRUE)

# Algunas personas de mp11 no tienen seguimiento enlazado en la BDLPA
# (no se pudieron casar los registros). No podemos calcular su tiempo de
# seguimiento, así que las excluimos del análisis.
n_sin_seguimiento <- sum(is.na(datos$TIPOB))
cat("\nPersonas sin seguimiento enlazado (se excluyen):", n_sin_seguimiento, "\n")
datos <- datos[!is.na(datos$TIPOB), ]
cat("Personas que quedan para el análisis:", nrow(datos), "\n")


## =============================================================================
## PASO 4. Calcular la edad de entrada y de salida de cada persona
## =============================================================================
##
##  EDAD DE ENTRADA = edad que tenía la persona el día del Censo (2011.83)
##  EDAD DE SALIDA   = edad que tenía cuando terminó su seguimiento
##                      (por fallecimiento, salida de Andalucía, o fin
##                      de estudio)
##
##  DECAB nos dice en qué DÉCIMA parte del año ocurrió la salida (0 a 9),
##  así que aproximamos la fecha exacta como el punto medio de esa décima
##  parte: año + décima/10 + 0.05

datos$edad_entrada <- FECHA_CENSO - datos$FNAC
datos$fecha_salida <- datos$ABAJA + datos$DECAB / 10 + 0.05
datos$edad_salida  <- datos$fecha_salida - datos$FNAC

# Limpieza: eliminamos posibles inconsistencias (edad de salida antes que
# la de entrada, o edades fuera de un rango humano razonable)
antes <- nrow(datos)
datos <- datos[datos$edad_salida >= datos$edad_entrada &
                 datos$edad_entrada >= 0 & datos$edad_salida <= 115, ]
cat("\nFilas eliminadas por inconsistencias de edad:", antes - nrow(datos), "\n")

# Gran grupo de causa (los dos primeros dígitos del código, p.ej. "02" de
# "02_01" = tumores). Solo tiene sentido para quien falleció (TIPOB == 1).
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
cat("\nFallecimientos por gran grupo de causa:\n")
print(sort(table(nombres_grupo_causa[datos$grupo_causa]), decreasing = TRUE))


## =============================================================================
## PASO 5. De "una fila por persona" a "años-persona por banda de edad"
## =============================================================================
##
##  ¿POR QUÉ HACE FALTA ESTE PASO? — Ejemplo con una sola persona
##  ------------------------------------------------------------------
##  Imagina una persona que en el Censo (2011.83) tenía 47.3 años, y que
##  sigue viva hasta el final del estudio (2023.83), con lo que sale con
##  59.3 años. Esa persona ha "pasado" por dos bandas de edad de 5 años:
##
##      banda 45-49:  desde los 47.3 hasta los 50 años -> 2.7 años en riesgo
##      banda 50-54:  desde los 50   hasta los 54 años -> 4.0 años en riesgo
##      banda 55-59:  desde los 55   hasta los 59.3     -> 4.3 años en riesgo
##
##  A cada una de esas bandas le "aporta" un trozo de su tiempo de
##  seguimiento. A ese tiempo aportado se le llama AÑOS-PERSONA, y es el
##  denominador que necesitamos para calcular tasas de mortalidad: no
##  basta con contar cuántas personas de 50-54 años murieron, hace falta
##  saber cuántos años-persona ha "vivido" el grupo de 50-54 años en total
##  (porque no todo el mundo aporta el mismo tiempo a cada banda).
##
##  Con casi 600.000 personas no podemos hacer esto a mano ni con un
##  bucle uno por uno (sería lentísimo). En su lugar, calculamos de golpe,
##  para TODAS las personas y TODAS las bandas a la vez, el solapamiento
##  entre el intervalo [edad_entrada, edad_salida] de cada persona y cada
##  banda de edad. Es la misma operación que en el ejemplo de arriba,
##  pero vectorizada.

etiquetas_banda <- c(paste(seq(0, 85, by = 5), seq(4, 89, by = 5), sep = "-"), "90+")
n_bandas <- length(etiquetas_banda)

edad_ini <- datos$edad_entrada
edad_fin <- datos$edad_salida

limite_inf <- matrix(CORTES_EDAD[1:n_bandas],       nrow = length(edad_ini), ncol = n_bandas, byrow = TRUE)
limite_sup <- matrix(CORTES_EDAD[2:(n_bandas + 1)], nrow = length(edad_ini), ncol = n_bandas, byrow = TRUE)

# Solapamiento entre [edad_ini, edad_fin] y [limite_inf, limite_sup]:
# el máximo de 0 y (el mínimo de los dos límites superiores, menos el
# máximo de los dos límites inferiores). Es geometría de intervalos.
anos_persona <- pmax(0, pmin(edad_fin, limite_sup) - pmax(edad_ini, limite_inf))
dim(anos_persona) <- c(length(edad_ini), n_bandas)   # pmin/pmax "olvidan" que era una matriz
colnames(anos_persona) <- etiquetas_banda

# A qué banda de edad pertenece la salida de cada persona (ahí es donde,
# si hay fallecimiento, se debe contar la muerte)
datos$banda_salida <- cut(edad_fin, breaks = CORTES_EDAD, labels = etiquetas_banda, right = FALSE)

cat("\nTotal de años-persona acumulados en toda la muestra:",
    format(round(sum(anos_persona)), big.mark = "."), "\n")


## =============================================================================
## PASO 6. Construir la tabla de vida (y la tabla de vida "sin la causa")
## =============================================================================
##
##  QUÉ ES UNA TABLA DE VIDA (explicación con palabras sencillas)
##  ------------------------------------------------------------------
##  Imagina 100.000 personas recién nacidas ("radix" de la tabla). La
##  tabla de vida sigue a ese grupo imaginario edad a edad, aplicando en
##  cada banda la probabilidad de morir que hemos observado en la
##  población real, y va contando cuántas de esas 100.000 personas
##  seguirían vivas a cada edad. Con eso se puede calcular cuántos años
##  de vida le quedan, en promedio, a alguien de cada edad: eso es la
##  ESPERANZA DE VIDA.
##
##  Columnas que vamos a calcular, edad a edad:
##    nMx = tasa de mortalidad observada  = muertes / años-persona
##    nqx = probabilidad de morir en la banda, estimada a partir de nMx
##    lx  = de 100.000 nacidos, cuántos siguen vivos al llegar a esa edad
##    ndx = cuántos mueren en esa banda (= diferencia entre lx sucesivos)
##    nLx = años-persona vividos por el grupo dentro de esa banda
##    Tx  = años-persona que le quedan por vivir al grupo a partir de esa edad
##    ex  = esperanza de vida en esa edad = Tx / lx  (años que le quedan,
##          en promedio, a alguien que llega vivo a esa edad)
##
##  EL MÉTODO DE CHIANG PARA "ELIMINAR" UNA CAUSA DE MUERTE
##  ------------------------------------------------------------------
##  Para responder "¿cuánto ganaríamos si esta causa no existiera?" no
##  basta con borrar esas muertes sin más: hay que ajustar la
##  probabilidad de morir de forma coherente. La idea del método de
##  Chiang (1968), muy usada en demografía, es sencilla:
##
##    R = proporción de las muertes de esa banda que NO se deben a la
##        causa que queremos eliminar (si el 30% de las muertes de 70-74
##        años son por cáncer, R = 0.70 para esa banda)
##
##    nueva probabilidad de SEGUIR VIVO = (probabilidad de seguir vivo
##        observada) elevada a R
##
##  Cuanto más pesa una causa en una banda de edad (R más pequeño), más
##  sube la probabilidad de sobrevivir esa banda al "eliminarla", y por
##  tanto más gana la esperanza de vida.

anchura_banda <- diff(CORTES_EDAD)
anchura_banda[n_bandas] <- NA   # la última banda (90+) es abierta, no tiene anchura fija

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

  Mx <- muertes_totales / py                       # tasa de mortalidad observada
  R  <- 1 - (muertes_causa / muertes_totales)       # Chiang: proporción de riesgo NO debida a la causa
  R[is.nan(R)] <- 1                                 # si no hubo muertes en esa banda, no hay nada que ajustar

  n  <- anchura_banda
  ax <- n / 2                                       # supuesto estándar: las muertes se reparten
                                                     # uniformemente dentro de cada banda de 5 años
  qx <- (n * Mx) / (1 + ax * Mx)
  qx[n_bandas] <- 1                                 # en la última banda abierta, la probabilidad de
                                                     # morir "alguna vez" es, por definición, 1

  qx_ajustada <- 1 - (1 - qx) ^ R                    # tabla de vida "sin" la causa (Chiang)
  qx_ajustada[n_bandas] <- 1

  calcular_ex <- function(qx_vec) {
    lx <- numeric(n_bandas + 1)
    lx[1] <- 100000
    for (i in 1:n_bandas) lx[i + 1] <- lx[i] * (1 - qx_vec[i])
    dx <- -diff(lx)
    Lx <- numeric(n_bandas)
    for (i in 1:(n_bandas - 1)) Lx[i] <- n[i] * lx[i + 1] + ax[i] * dx[i]
    Lx[n_bandas] <- lx[n_bandas] / Mx[n_bandas]      # intervalo abierto: se asume mortalidad constante
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


## =============================================================================
## PASO 7. Resultados: esperanza de vida observada, por sexo
## =============================================================================

cat("\n\n=====================================================================\n")
cat("  ESPERANZA DE VIDA OBSERVADA (todas las causas juntas)\n")
cat("=====================================================================\n")

tabla_hombres <- construir_tabla_vida(sexo_codigo = "1")
tabla_mujeres <- construir_tabla_vida(sexo_codigo = "6")

cat("\n--- Hombres ---\n")
print(tabla_hombres[, c("banda","anos_persona","muertes","tasa_mortalidad","esperanza_vida")])
cat(sprintf("\nEsperanza de vida al nacer (hombres): %.2f años\n", tabla_hombres$esperanza_vida[1]))

cat("\n--- Mujeres ---\n")
print(tabla_mujeres[, c("banda","anos_persona","muertes","tasa_mortalidad","esperanza_vida")])
cat(sprintf("\nEsperanza de vida al nacer (mujeres): %.2f años\n", tabla_mujeres$esperanza_vida[1]))


## =============================================================================
## PASO 7.5. Esperanza de vida por provincia y sexo (para la app web)
## =============================================================================
##
##  ¿POR QUÉ A NIVEL DE PROVINCIA Y NO DE SECCIÓN CENSAL?
##  ------------------------------------------------------------------
##  La app web (AnalisisGeograficoChatQuery.R) trabaja con datos a nivel
##  de sección censal (código CUSEC de 10 dígitos: CPRO+CMUN+CDIS+CSEC).
##  Lo ideal sería poder calcular la esperanza de vida para cada sección
##  censal y mostrarla directamente en el mapa, pero esto NO es posible
##  con los datos disponibles. He aquí por qué:
##
##  1. El ID de persona en la BDLPA (campo ID, 6 dígitos) es un número
##     secuencial de registro (p.ej. "006431", "006432", "006433"...),
##     NO un código geográfico. No contiene provincia, municipio, distrito
##     ni sección censal. La única variable geográfica disponible en el
##     fichero de personas (mp11.txt) es PROVINCIA (2 dígitos), que hemos
##     extraído buscando códigos provinciales válidos dentro de cada línea.
##
##  2. Existe un segundo fichero, smv11cau.txt (viviendas), que SÍ contiene
##     un código geográfico detallado en las posiciones 18-27. Ese código
##     tiene formato propio de 8 dígitos + sufijo de 2 (p.ej. "2110105_99"),
##     NO el CUSEC estándar de 10 dígitos del INE. Además, smv11cau solo
##     cubre ~140.000 IDs de los ~637.000 del fichero de personas (un 22%),
##     por lo que no es viable como fuente de geolocalización para toda
##     la muestra censal.
##
##  3. El ID de 10 dígitos que usa la app (CUSEC = CPRO+CMUN+CDIS+CSEC)
##     proviene del shapefile de secciones censales del INE, NO de la
##     BDLPA. No hay una tabla puente que relacione los IDs de la BDLPA
##     con las secciones del shapefile.
##
##  SOLUCIÓN ADOPTADA:
##  ------------------------------------------------------------------
##  Calculamos la esperanza de vida al nacer para cada combinación de
##  provincia x sexo (8 provincias x 2 sexos = 16 tablas de vida), usando
##  la variable PROVINCIA que ya tenemos disponible en el fichero de
##  personas. El resultado se guarda como un CSV que la app web carga y
##  asigna a todas las secciones censales dentro de cada provincia.
##  Al hacer clic en cualquier sección de, p.ej., Granada, la app
##  mostrará la EV de la provincia de Granada.
##
##  NOTA SOBRE ESTABILIDAD DE LAS ESTIMACIONES:
##  ------------------------------------------------------------------
##  La muestra total (~637k personas) se reparte entre 8 provincias
##  (~80k personas por provincia de media) y luego entre 2 sexos (~40k
##  por grupo). En provincias pequeñas y bandas de edad extremas (0-4 años
##  o 90+), el número de muertes observadas puede ser muy bajo o incluso
##  cero, lo que hace que la tasa de mortalidad estimada sea inestable.
##  Para la tabla completa por bandas de edad (que se usa internamente)
##  esto es esperable; solo se exporta al CSV la esperanza de vida al
##  nacer (primera banda), que es el indicador más robusto porque acumula
##  información de todas las edades.
##  Los resultados son apropiados como indicador descriptivo en la app,
##  no para inferencia estadística formal.

# Mapa: código de provincia (2 dígitos) -> nombre para el CSV
# Usamos los mismos nombres que aparecen en datos_rentapop_long.RData
# para que el merge en la app sea directo.
nombres_provincia <- c(
  "04" = "Almeria",
  "11" = "Cadiz",
  "14" = "Cordoba",
  "18" = "Granada",
  "21" = "Huelva",
  "23" = "Jaen",
  "29" = "Malaga",
  "41" = "Sevilla"
)

cat("\n\n=====================================================================\n")
cat("  ESPERANZA DE VIDA AL NACER POR PROVINCIA Y SEXO\n")
cat("  (para integrar en la app web de sección censal)\n")
cat("=====================================================================\n")

# Función: tabla de vida para una provincia x sexo concretos
construir_tabla_vida_provincia <- function(codigo_provincia, sexo_codigo) {
  es_prov <- datos$PROVINCIA == codigo_provincia
  es_sexo <- datos$SEXO == sexo_codigo
  idx <- es_prov & es_sexo

  # Si no hay suficientes datos en esta provincia, devolvemos NA
  if (sum(idx) < 50) {
    return(data.frame(
      provincia = nombres_provincia[codigo_provincia],
      sexo = ifelse(sexo_codigo == "1", "Hombres", "Mujeres"),
      esperanza_vida_nacer = NA_real_,
      n_personas = sum(idx),
      n_muertes = NA_integer_
    ))
  }

  py <- colSums(anos_persona[idx, , drop = FALSE])
  es_fallecido <- datos$TIPOB == 1 & idx
  muertes_totales <- as.numeric(table(factor(datos$banda_salida[es_fallecido], levels = etiquetas_banda)))

  Mx <- muertes_totales / py
  n  <- anchura_banda
  ax <- n / 2
  qx <- (n * Mx) / (1 + ax * Mx)
  qx[n_bandas] <- 1

  # Tabla de vida
  lx <- numeric(n_bandas + 1)
  lx[1] <- 100000
  for (i in 1:n_bandas) lx[i + 1] <- lx[i] * (1 - qx[i])
  dx <- -diff(lx)
  Lx <- numeric(n_bandas)
  for (i in 1:(n_bandas - 1)) Lx[i] <- n[i] * lx[i + 1] + ax[i] * dx[i]
  Lx[n_bandas] <- lx[n_bandas] / Mx[n_bandas]
  Tx <- rev(cumsum(rev(Lx)))
  ex_nacer <- Tx[1] / lx[1]

  data.frame(
    provincia = nombres_provincia[codigo_provincia],
    sexo = ifelse(sexo_codigo == "1", "Hombres", "Mujeres"),
    esperanza_vida_nacer = round(ex_nacer, 2),
    n_personas = sum(idx),
    n_muertes = sum(muertes_totales)
  )
}

# Recorremos las 8 provincias x 2 sexos
resultados_ev_provincia <- do.call(rbind, lapply(names(nombres_provincia), function(cod_prov) {
  hombres <- construir_tabla_vida_provincia(cod_prov, "1")
  mujeres <- construir_tabla_vida_provincia(cod_prov, "6")
  rbind(hombres, mujeres)
}))

rownames(resultados_ev_provincia) <- NULL
cat("\nEsperanza de vida al nacer por provincia y sexo:\n")
print(resultados_ev_provincia)

# También guardamos una versión "ancha" (una fila por provincia) que es más
# fácil de mergear con la tabla de datos de la app:
ev_provincia_ancho <- reshape(
  resultados_ev_provincia[, c("provincia", "sexo", "esperanza_vida_nacer")],
  idvar = "provincia", timevar = "sexo", direction = "wide"
)
names(ev_provincia_ancho) <- c("provincia", "EV_Hombres", "EV_Mujeres")
cat("\nFormato ancho (para merge con app):\n")
print(ev_provincia_ancho)

# Guardamos ambos formatos
write.csv(resultados_ev_provincia, file.path(ruta_salida, "ev_por_provincia_sexo.csv"), row.names = FALSE)
write.csv(ev_provincia_ancho, file.path(ruta_salida, "ev_por_provincia_ancho.csv"), row.names = FALSE)

cat("\nFicheros guardados:\n")
cat("  - ev_por_provincia_sexo.csv (formato largo: provincia x sexo)\n")
cat("  - ev_por_provincia_ancho.csv (formato ancho: una columna por sexo)\n")


## =============================================================================
## PASO 8. Resultados: ganancia de esperanza de vida si se elimina cada causa
## =============================================================================

cat("\n\n=====================================================================\n")
cat("  GANANCIA EN ESPERANZA DE VIDA AL NACER SI SE ELIMINARA CADA CAUSA\n")
cat("=====================================================================\n")

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


## =============================================================================
## PASO 9. Guardar resultados
## =============================================================================

write.csv(resumen, file.path(ruta_salida, "ganancia_esperanza_vida_por_causa.csv"), row.names = FALSE)
write.csv(tabla_hombres, file.path(ruta_salida, "tabla_vida_hombres.csv"), row.names = FALSE)
write.csv(tabla_mujeres, file.path(ruta_salida, "tabla_vida_mujeres.csv"), row.names = FALSE)

cat("\n\nFicheros guardados en", ruta_salida, ":\n")
cat("  - ganancia_esperanza_vida_por_causa.csv\n")
cat("  - tabla_vida_hombres.csv\n")
cat("  - tabla_vida_mujeres.csv\n")
cat("  - ev_por_provincia_sexo.csv (EV al nacer por provincia y sexo)\n")
cat("  - ev_por_provincia_ancho.csv (EV al nacer, formato ancho para app)\n")


## =============================================================================
## PASO 10. Un gráfico sencillo para visualizar los resultados
## =============================================================================

png(file.path(ruta_salida, "grafico_ganancia_por_causa.png"), width = 1000, height = 700, res = 120)
par(mar = c(5, 14, 4, 2))
resumen_h <- resumen[resumen$sexo == "Hombres", ]
resumen_h <- resumen_h[order(resumen_h$ganancia_anos), ]
barplot(resumen_h$ganancia_anos, names.arg = resumen_h$causa, horiz = TRUE, las = 1,
        col = "#1a5276", border = NA,
        main = "Ganancia en esperanza de vida al nacer si se elimina la causa\n(Hombres, cohorte censal Andalucía 2011)",
        xlab = "Años ganados")
dev.off()
cat("\nGráfico guardado en", file.path(ruta_salida, "grafico_ganancia_por_causa.png"), "\n")


## =============================================================================
## PASO 11. LIMITACIONES QUE HAY QUE TENER EN CUENTA (léelas antes de publicar
##          ningún resultado basado en este script)
## =============================================================================
##
##  1. ESTO ES UNA MUESTRA, NO EL CENSO COMPLETO. En las bandas de edad
##     con pocas muertes (los extremos: niños, o el grupo 90+) la tasa de
##     mortalidad estimada puede ser inestable. Si necesitas precisión en
##     esas edades, conviene suavizar las tasas (por ejemplo, con un
##     modelo de Poisson con splines) en vez de usar la tasa cruda.
##
##  2. LA "GANANCIA" DE CADA CAUSA NO SE PUEDE SUMAR SIN MÁS. Si eliminas
##     el cáncer, la gente que se salva de morir de cáncer acabará
##     muriendo antes o después de otra causa. Por eso la suma de las
##     ganancias de todas las causas NO coincide con "vivir para
##     siempre"; cada ganancia se interpreta de una en una, no todas a
##     la vez.
##
##  3. ES UNA TABLA DE VIDA "DE PERÍODO", no el seguimiento real de una
##     única generación de personas desde que nace hasta que muere.
##     Combina, en un mismo cálculo, la mortalidad observada en personas
##     de distintas edades durante 2011-2023, como si un grupo
##     imaginario de 100.000 recién nacidos fuera a experimentar esas
##     mismas tasas a lo largo de su vida. Es la forma estándar de
##     calcular una esperanza de vida (así lo hace el INE), pero conviene
##     saber que no es literalmente "lo que le pasó a una generación
##     real".
##
##  4. LA FECHA EXACTA DE SALIDA ES APROXIMADA. Solo sabemos en qué
##     décima parte del año ocurrió cada baja (variable DECAB), así que
##     hemos usado el punto medio de ese intervalo. El error que esto
##     introduce es pequeño (como mucho unas semanas) y no afecta a las
##     conclusiones.
##
##  5. LA CLASIFICACIÓN DE CAUSAS ES AGREGADA (10 grandes grupos), no la
##     clasificación CIE-10 completa. Es apropiada para este tipo de
##     análisis de esperanza de vida, pero no permite bajar a
##     diagnósticos muy específicos dentro de cada grupo.
##
## =============================================================================

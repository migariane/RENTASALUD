library(sf)
library(dplyr)

codigos_andalucia <- c("04", "11", "14", "18", "21", "23", "29", "41", "51", "52")

dir.create("SHP_opt", showWarnings = FALSE)

years <- 2015:2022

for (year in years) {
  carpeta <- paste0("SHP/seccionado_", year)
  if (dir.exists(carpeta)) {
    archivo <- list.files(carpeta, pattern = "\\.shp$", full.names = TRUE)
    if (length(archivo) > 0) {
      cat("Procesando año", year, "...\n")
      m <- st_read(archivo[1], quiet = TRUE)
      
      m_and <- m %>% 
        filter(CPRO %in% codigos_andalucia) %>%
        st_transform(4326)
      
      # Guardar como RDS
      saveRDS(m_and, paste0("SHP_opt/seccionado_", year, ".rds"))
    }
  }
}
cat("¡Terminado!\n")

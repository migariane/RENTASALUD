# Desigualdades Sociales en Andalucía

Aplicación web interactiva (Shiny) para visualizar datos socioeconómicos y de renta de los hogares en Andalucía a nivel de sección censal (2015-2022). Incluye un Asistente Inteligente impulsado por IA que permite hacer preguntas sobre los datos en lenguaje natural garantizando la máxima privacidad, ya que se ejecuta íntegramente de forma local.

**Autores:** Miguel Angel Luque Fernandez, Gustavo Rivas Gervilla, Mario Rivera Izquierdo, Miguel Angel Montero Alonso y Juan Manuel Melchor Rodriguez (Doctores de la UGR)

---

## Cómo ejecutar la aplicación en tu propio ordenador

### 1. Requisitos Previos (R y RStudio)
Necesitas tener instalados **R** y **RStudio** en tu equipo. Además, la primera vez que abras el proyecto, asegúrate de instalar las librerías necesarias ejecutando el siguiente código en la consola de RStudio:
```R
install.packages(c("shiny", "bslib", "leaflet", "dplyr", "sf", "stringr", "htmltools", "ellmer"))
```
*(Nota: la librería `querychat` puede requerir instalación desde GitHub si no se encuentra en CRAN).*

### 2. Configurar el Asistente Inteligente (Ollama)
Esta aplicación utiliza **Ollama** para que la Inteligencia Artificial procese tus preguntas de manera 100% local, sin enviar tus datos a la nube (garantizando tu privacidad).

Sigue estos pasos para configurarlo:
1. **Descarga e instala Ollama**: Ve a [https://ollama.com](https://ollama.com) y descarga el instalador para tu sistema operativo (Windows, Mac o Linux).
2. **Descarga el modelo de lenguaje**: Abre tu terminal (en Mac/Linux) o Símbolo del sistema/PowerShell (en Windows) y ejecuta el siguiente comando para descargar el modelo necesario:
   ```bash
   ollama pull llama3.2
   ```
   *(Este proceso puede tardar unos minutos dependiendo de tu conexión a internet).*
3. **Mantén Ollama abierto**: Asegúrate de que la aplicación de Ollama se está ejecutando en segundo plano (verás el icono de una llama en tu barra de tareas o barra superior).

### 3. Ejecutar la Aplicación
1. Abre el archivo `app.R` en RStudio.
2. Haz clic en el botón **"Run App"** (situado en la parte superior del panel de código).
3. ¡Listo! Ya puedes explorar los mapas sociodemográficos y hacerle preguntas al asistente inteligente en la pestaña "Asistente IA".

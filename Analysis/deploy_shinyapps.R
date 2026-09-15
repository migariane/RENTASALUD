## =============================================================================
##  deploy_shinyapps.R — deploy the RENTASALUD atlas as a SELF-CONTAINED bundle
## =============================================================================
##  WHY THIS SCRIPT EXISTS:
##    global.R loads, at startup, the income RData and the four pipeline CSVs
##    (ev_por_provincia_ancho, ganancia_esperanza_vida_por_causa,
##    tabla_vida_hombres, tabla_vida_mujeres). It looks for them in
##    ../Resultados/ (local) or /mnt/user-data/outputs/ (server), and finally
##    falls back to the bare filename IN THE APP DIRECTORY.
##
##    On shinyapps.io neither ../Resultados/ nor /mnt/user-data/ exists, and
##    `deployApp(appDir = "Analysis")` does NOT bundle files that live outside
##    the app dir. So the CSVs were missing and the app crashed at startup:
##      "The application failed to start. exit status 1" (HTTP 500).
##
##    This script stages the needed files into a clean temporary bundle (so the
##    repository working tree is never polluted) and deploys that bundle.
##
##  USAGE:
##    Rscript Analysis/deploy_shinyapps.R
##    INCLUDE_MAPS=false Rscript Analysis/deploy_shinyapps.R   # skip 94 MB of maps
##
##  CREDENTIALS:
##    Uses the stored rsconnect account (rsconnect::accounts()) when present.
##    Otherwise set SHINYAPPS_ACCOUNT / SHINYAPPS_TOKEN / SHINYAPPS_SECRET.
## =============================================================================

options(warn = 1)
cat("deploy_shinyapps.R — self-contained bundle\n")

## ── Self-locate the repo root (works under Rscript + RStudio) ──
if (interactive()) {
  script_dir <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile)),
                         error = function(e) getwd())
} else {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- sub("^--file=", "", args[grep("^--file=", args)])
  script_dir <- if (length(file_arg) > 0 && file_arg != "")
    dirname(normalizePath(file_arg)) else getwd()
}
repo_root <- dirname(script_dir)
app_src   <- file.path(repo_root, "Analysis")
res_dir   <- file.path(repo_root, "Resultados")
cat("  repo root:", repo_root, "\n")

## ── Resolve the pipeline outputs (real run first, then CI run) ──
csv_names <- c("ev_por_provincia_ancho.csv", "ganancia_esperanza_vida_por_causa.csv",
               "tabla_vida_hombres.csv", "tabla_vida_mujeres.csv")
has_all <- function(dir) all(file.exists(file.path(dir, csv_names)))
src_data <- if (has_all(res_dir)) res_dir else
            if (has_all(file.path(res_dir, "test_run"))) file.path(res_dir, "test_run") else
            stop("Pipeline outputs not found in Resultados/ nor Resultados/test_run/.\n",
                 "  Run Analysis/00_run_all.R first.")
cat("  pipeline outputs:", src_data, "\n")

## ── Build a clean bundle ──
bundle <- file.path(tempdir(), paste0("rentasalud_bundle_", format(Sys.time(), "%Y%m%d%H%M%S")))
dir.create(bundle, recursive = TRUE, showWarnings = FALSE)

copiar <- function(from, to) {
  if (!file.exists(from)) stop("missing input: ", from)
  if (!file.copy(from, to, overwrite = TRUE)) stop("failed to copy: ", from)
}

copiar(file.path(app_src, "app.R"), bundle)
copiar(file.path(app_src, "global.R"), bundle)
copiar(file.path(app_src, "datos_rentapop_long.RData"), bundle)
for (f in csv_names) copiar(file.path(src_data, f), bundle)

## Maps are optional: app.R only reads SHP_opt/seccionado_<year>.rds lazily
## (readRDS guarded by file.exists), so the app starts without them.
include_maps <- tolower(Sys.getenv("INCLUDE_MAPS", "true")) %in% c("true", "1", "yes")
shp_src <- file.path(app_src, "SHP_opt")
shp_rds <- if (dir.exists(shp_src)) list.files(shp_src, pattern = "\\.rds$", full.names = TRUE) else character(0)
if (include_maps && length(shp_rds) > 0) {
  dir.create(file.path(bundle, "SHP_opt"), showWarnings = FALSE)
  ok <- file.copy(shp_rds, file.path(bundle, "SHP_opt"), overwrite = TRUE)
  cat("  bundled maps:", sum(ok), "RDS files\n")
} else {
  cat("  [note] maps not bundled — the app starts but maps render empty\n")
}

cat("  bundle files:\n")
print(list.files(bundle, recursive = TRUE))

## ── Preflight: run the exact startup path in the bundle ──
preflight <- local({
  old <- setwd(bundle); on.exit(setwd(old))
  tryCatch({
    env <- new.env(parent = globalenv())
    sys.source("global.R", envir = env)
    sys.source("app.R",    envir = env)
    "OK"
  }, error = function(e) conditionMessage(e))
})
if (!identical(preflight, "OK")) stop("bundle preflight failed: ", preflight)
cat("  [OK] bundle preflight: global.R + app.R load cleanly\n")

## ── Deploy ──
if (!requireNamespace("rsconnect", quietly = TRUE))
  install.packages("rsconnect", repos = "https://cloud.r-project.org/")
library(rsconnect)

acct <- Sys.getenv("SHINYAPPS_ACCOUNT")
tok  <- Sys.getenv("SHINYAPPS_TOKEN")
sec  <- Sys.getenv("SHINYAPPS_SECRET")
if (nzchar(acct) && nzchar(tok) && nzchar(sec)) {
  rsconnect::setAccountInfo(name = acct, token = tok, secret = sec)
} else if (!nzchar(acct)) {
  acct <- "watzile"
}
cat("  deploying to account:", acct, "\n")

rsconnect::deployApp(appDir = bundle, appName = "RENTASALUD",
                     account = acct, forceUpdate = TRUE)
cat("Deploy finished.\n")

# wave2-compat probe: R starts, C and C++ R CMD SHLIB load, Rcpp from
# CRAN source, a C++ exception crosses into R (Rcpp::stop and a
# std::exception caught by R's tryCatch). Each step prints
# "PROBE <step>: ok|FAIL <message>"; the script never stops early.
# Env: PROBE_LIB (library dir), PROBE_PKGS (extra CRAN packages to
# install from source after Rcpp, space separated), PROBE_NCPUS.
res <- character()
step <- function(name, expr) {
  r <- tryCatch({ force(expr); "ok" },
                error = function(e) paste("FAIL", conditionMessage(e)))
  res[[name]] <<- r
  cat(sprintf("PROBE %s: %s\n", name, r))
}
cat("R:", R.version.string, "| R_HOME:", R.home(), "\n")
glibc <- tryCatch(system("getconf GNU_LIBC_VERSION", intern = TRUE), error = function(e) "?")
cat("host:", glibc, "\n")
lib <- Sys.getenv("PROBE_LIB", file.path(tempdir(), "lib"))
dir.create(lib, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(lib, .libPaths()))
loaded_cxx <- function() unique(sub(".* ", "", grep("libstdc\\+\\+|libc\\+\\+|libgcc_s",
  readLines("/proc/self/maps"), value = TRUE)))
cat("C++ runtime loaded at start:", loaded_cxx(), sep = "\n  ")

td <- tempfile("shlib"); dir.create(td); owd <- setwd(td)
writeLines(c("#include <R.h>", "#include <Rinternals.h>",
  "SEXP addc(SEXP a, SEXP b) { return Rf_ScalarReal(Rf_asReal(a) + Rf_asReal(b)); }"), "c1.c")
writeLines(c("#include <R.h>", "#include <Rinternals.h>",
  "#include <stdexcept>", "#include <string>", "#include <vector>",
  "extern \"C\" SEXP cxx(SEXP n) {",
  "  std::vector<std::string> v;",
  "  for (int i = 0; i < Rf_asInteger(n); i++) v.push_back(std::to_string(i));",
  "  try { throw std::runtime_error(\"-caught\"); }",
  "  catch (const std::exception& e) { return Rf_mkString((v.back() + e.what()).c_str()); }",
  "}"), "cxx1.cpp")
R <- file.path(R.home("bin"), "R")
step("shlib-c", {
  out <- system2(R, c("CMD", "SHLIB", "c1.c"), stdout = TRUE, stderr = TRUE)
  cat(out, sep = "\n"); if (!file.exists("c1.so")) stop("no c1.so")
  dyn.load("c1.so"); stopifnot(.Call("addc", 1, 2) == 3)
})
step("shlib-cxx", {
  out <- system2(R, c("CMD", "SHLIB", "cxx1.cpp"), stdout = TRUE, stderr = TRUE)
  cat(out, sep = "\n"); if (!file.exists("cxx1.so")) stop("no cxx1.so")
  dyn.load("cxx1.so"); v <- .Call("cxx", 3L); print(v); stopifnot(v == "2-caught")
})
setwd(owd)
ncpus <- as.integer(Sys.getenv("PROBE_NCPUS", "4"))
repos <- "https://cloud.r-project.org"
step("install-jsonlite-c", {
  install.packages("jsonlite", lib = lib, repos = repos, type = "source", quiet = TRUE)
  library(jsonlite, lib.loc = lib); stopifnot(toJSON(1:2) == "[1,2]")
})
step("install-Rcpp", {
  install.packages("Rcpp", lib = lib, repos = repos, type = "source", quiet = TRUE)
  library(Rcpp, lib.loc = lib)
})
step("rcpp-stop", {
  Rcpp::cppFunction('int dbl(int x) { if (x < 0) Rcpp::stop("negative: %d", x); return 2 * x; }')
  stopifnot(dbl(2L) == 4L)
  m <- tryCatch(dbl(-1L), error = function(e) conditionMessage(e)); print(m)
  stopifnot(grepl("negative: -1", m))
})
step("cxx-throw-std", {
  Rcpp::cppFunction('int thr() { throw std::range_error("range!"); return 0; }')
  m <- tryCatch(thr(), error = function(e) conditionMessage(e)); print(m)
  stopifnot(grepl("range!", m))
})
for (p in strsplit(Sys.getenv("PROBE_PKGS"), " +")[[1]]) if (nzchar(p)) step(paste0("install-", p), {
  install.packages(p, lib = lib, repos = repos, type = "source", Ncpus = ncpus,
                   dependencies = c("Depends", "Imports", "LinkingTo"))
  if (!requireNamespace(p, lib.loc = lib, quietly = TRUE)) stop("not installed: ", p)
  loadNamespace(p, lib.loc = lib)
  if (p == "terra") { r <- terra::rast(nrows = 3, ncols = 3, vals = 1:9)
    f <- tempfile(fileext = ".tif"); terra::writeRaster(r, f); print(terra::global(terra::rast(f), "sum"))
    print(tryCatch(terra::rast("/nonexistent.tif"), error = function(e) conditionMessage(e))) }
  if (p == "sf") { print(sf::sf_extSoftVersion())
    g <- sf::st_buffer(sf::st_sfc(sf::st_point(c(0, 0)), crs = 4326), 1000); print(sf::st_area(g))
    print(tryCatch(sf::st_read("/nonexistent.gpkg", quiet = TRUE), error = function(e) conditionMessage(e))) }
  if (p == "magick") { print(magick::magick_config()$version)
    print(magick::image_info(magick::image_blank(10, 10, "red")))
    print(tryCatch(magick::image_read("/nonexistent.png"), error = function(e) conditionMessage(e))) }
})
cat("C++ runtime loaded at end:", loaded_cxx(), sep = "\n  ")
cat("PROBE-SUMMARY:", sprintf("%s=%s", names(res), substr(res, 1, 4)), "\n")

# terra (row smoke `@terra.R`): a raster, an EPSG code through PROJ's
# proj.db, and a failed read as an R error (GDAL through terra's C++ code),
# not a crash (chore-release-12 M-10).
print(libVersion("all"))
r <- rast(nrows = 2, ncols = 2)
code <- crs(rast(crs = "EPSG:3857"), describe = TRUE)$code
miss <- inherits(try(rast(file.path(tempdir(), "missing.tif")), silent = TRUE), "try-error")
print(list(code = code, missing_is_error = miss))
nrow(r) == 2 && identical(as.character(code), "3857") && miss

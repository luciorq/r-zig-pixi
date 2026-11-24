# sf (row smoke `@sf.R`): a transform through PROJ (EPSG codes need
# proj.db), the PROJ search paths printed (Windows: sf's share/proj, copied
# from R_TOOLS_SOFT at install; chore-release-12 M-10), and a failed read
# as an R error (GDAL through sf's C++ code), not a crash.
print(sf_extSoftVersion())
print(sf_proj_search_paths())
p <- st_crs(st_transform(st_sfc(st_point(c(0, 0)), crs = 4326), 3857))$epsg
miss <- inherits(try(st_read(file.path(tempdir(), "missing.gpkg"), quiet = TRUE), silent = TRUE), "try-error")
print(list(epsg = p, missing_is_error = miss))
isTRUE(p == 3857) && miss

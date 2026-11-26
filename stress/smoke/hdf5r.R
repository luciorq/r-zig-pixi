# hdf5r (row smoke `@hdf5r.R`): a dataset and an attribute written, the
# file closed and read back; opening a missing file is an R error (HDF5's
# error stack through hdf5r's C code), not a crash. On windows-aarch64 the
# library is the Rtools45 tree's HDF5 1.12.1 (chore-release-12 M-10: more
# than creating a file).
f <- tempfile(fileext = ".h5")
h <- H5File$new(f, "w")
h[["x"]] <- 1:10
d <- h[["x"]]
h5attr(d, "unit") <- "m"
h$close_all()
h <- H5File$new(f, "r")
x <- h[["x"]][]
u <- h5attr(h[["x"]], "unit")
h$close_all()
miss <- inherits(try(H5File$new(file.path(tempdir(), "missing.h5"), "r"), silent = TRUE), "try-error")
print(list(x = x, unit = u, missing_is_error = miss))
identical(x, 1:10) && identical(u, "m") && miss

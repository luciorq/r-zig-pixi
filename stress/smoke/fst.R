# fst (row smoke `@fst.R`): a write and a read with two OpenMP threads
# (fstcore). On Windows also one OpenMP runtime in the process
# (chore-release-12 M-10: the tree's libomp import against the env's
# libomp): tasklist's module list of this R, the omp DLLs printed.
threads_fst(2)
f <- tempfile(fileext = ".fst")
write_fst(mtcars, f, compress = 50)
ok <- isTRUE(all.equal(read_fst(f), mtcars, check.attributes = FALSE))
if (.Platform$OS.type == "windows") {
  m <- system2("tasklist", c("/m", "/fo", "csv", "/nh", "/fi", paste0('"PID eq ', Sys.getpid(), '"')), stdout = TRUE)
  mods <- trimws(unlist(strsplit(gsub('"', "", paste(m, collapse = ",")), ",")))
  omp <- unique(tolower(grep("^(lib[gi]?omp|vcomp).*\\.dll$", mods, ignore.case = TRUE, value = TRUE)))
  cat("modules:", length(mods), "; OpenMP:", omp, "\n")
  ok <- ok && length(mods) > 3 && length(omp) <= 1
}
ok

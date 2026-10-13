# M5 on kappa: exports / imports / argv parity of the zig and make installs; run after m5-kappa.bat's installs
W <- "C:/Users/admin/rz-m5"; objdump <- "x86_64-w64-mingw32-objdump"
exports <- function(dll) {
  out <- system2(objdump, c("-p", shQuote(dll)), stdout = TRUE)
  i <- grep("\\[Ordinal/Name Pointer\\] Table", out); if (!length(i)) return(character())
  out <- out[(i + 1):length(out)]; j <- grep("^\\s*$", out); if (length(j)) out <- out[seq_len(j[1] - 1)]
  sort(sub("^\\s*\\[\\s*\\d+\\]\\s+", "", out))
}
imports <- function(dll) { out <- system2(objdump, c("-p", shQuote(dll)), stdout = TRUE); sort(unique(sub("^\\s*DLL Name:\\s*", "", grep("DLL Name:", out, value = TRUE)))) }
argv <- function(log) { l <- readLines(log, warn = FALSE); l <- grep("^(zig-cc|zig-cxx|zig-fc|gcc|g\\+\\+|rzig)(\\.exe)?: ", l, value = TRUE); l <- grep("--version", l, value = TRUE, invert = TRUE)
  l <- gsub("[^ ]*[\\\\/]([^\\\\/ ]+)", "\\1", l); sort(l) }
for (p in c("cli", "digest", "quadprog", "Rcpp")) {
  z <- file.path(W, "lib-zig", p, "libs/x64", paste0(p, ".dll")); m <- file.path(W, "lib-make", p, "libs/x64", paste0(p, ".dll"))
  ez <- if (file.exists(z)) exports(z) else NULL; em <- if (file.exists(m)) exports(m) else NULL
  cat(sprintf("%-9s exports zig: %s | make: %s | %s\n", p, if (is.null(ez)) "no dll" else length(ez), if (is.null(em)) "no dll" else length(em),
    if (!is.null(ez) && !is.null(em)) { if (identical(ez, em)) "identical" else paste("DIFFER: zig-only", paste(setdiff(ez, em), collapse = " "), "make-only", paste(setdiff(em, ez), collapse = " ")) } else ""))
  if (!is.null(ez) && !is.null(em)) { iz <- imports(z); im <- imports(m); cat(sprintf("          imports %s | zig: %s\n", if (identical(iz, im)) "identical" else paste("DIFFER; make:", paste(im, collapse = " ")), paste(iz, collapse = " "))) }
  lz <- file.path(W, "logs", paste0(p, "-zig.log")); lm <- file.path(W, "logs", paste0(p, "-make.log"))
  if (file.exists(lz) && file.exists(lm)) { az <- argv(lz); am <- argv(lm); cat(sprintf("          rzig argv %s (%d zig / %d make lines)\n", if (identical(az, am)) "identical" else "DIFFER", length(az), length(am)))
    if (!identical(az, am)) { cat("          zig-only:\n"); writeLines(paste("           ", head(setdiff(az, am), 4))); cat("          make-only:\n"); writeLines(paste("           ", head(setdiff(am, az), 4))) } }
}
q <- file.path(W, "lib-zig/quadprog/libs/x64/quadprog.dll"); if (file.exists(q)) cat("quadprog zig exports:", paste(exports(q), collapse = " "), "\n")
z <- file.path(W, "lib-t2/zighello/libs/x64/zighello.dll"); if (file.exists(z)) cat("zighello exports:", paste(exports(z), collapse = " "), "| imports:", paste(imports(z), collapse = " "), "\n")
for (p in c("cli", "quadprog", "zighello")) { l <- file.path(W, "logs", paste0(p, "-zig.log")); if (!file.exists(l)) l <- file.path(W, "logs", paste0(p, ".log")); if (file.exists(l)) { x <- readLines(l, warn = FALSE); cat(sprintf("%-9s def step in trace: %s | .def on the link line: %s\n", p, any(grepl("rzig(\\.exe)? def ", x)), any(grepl("\\.def( |$)", grep("-shared|-o .*\\.dll", x, value = TRUE))))) } }

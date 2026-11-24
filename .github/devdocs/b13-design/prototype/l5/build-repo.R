## L5 prototype (b13-design PLAN.md): build CRAN source packages into
## binaries with this R (r-zig, the `build` env) and lay them out as a
## CRAN-like binary repository.
##   Rscript build-repo.R <work dir> <pkg,pkg,...>
## <work>/src/contrib      the sources (a CRAN mirror slice; PACKAGES)
## <work>/repo/bin/linux/<key>/contrib/<x.y>
##                         the binaries, PACKAGES/.gz/.rds with extra fields
## <work>/times.tsv        per package: build seconds, binary size
args <- commandArgs(TRUE)
work <- normalizePath(args[1], mustWork = FALSE)
targets <- strsplit(args[2], ",")[[1]]
cran <- "https://cloud.r-project.org"
say <- function(...) cat(sprintf(...), "\n", sep = "")

## The ABI key: what a binary is valid for (PLAN.md L5 design, D9).
## R's x.y, the platform, and r-zig's package ABI epoch. The build number
## is recorded per package but is not part of the key.
rver <- paste(R.version$major, strsplit(R.version$minor, ".", fixed = TRUE)[[1]][1], sep = ".")
arch <- R.version$arch
abi <- Sys.getenv("RZIG_ABI", "1")
key <- sprintf("%s-rzig%s", arch, abi)
rzig_build <- Sys.getenv("RZIG_BUILD", "unknown")

src <- file.path(work, "src/contrib"); dir.create(src, recursive = TRUE, showWarnings = FALSE)
bin <- file.path(work, "repo/bin/linux", key, "contrib", rver); dir.create(bin, recursive = TRUE, showWarnings = FALSE)
lib <- file.path(work, "buildlib"); unlink(lib, recursive = TRUE); dir.create(lib)
.libPaths(c(lib, .libPaths()))

## 1. sources: the targets and their hard dependencies, in install order
av <- available.packages(repos = cran, type = "source")
base <- rownames(installed.packages(priority = "base"))
deps <- tools::package_dependencies(targets, av, which = c("Depends", "Imports", "LinkingTo"), recursive = TRUE)
all <- setdiff(unique(c(unlist(deps), targets)), base)
order <- character()
visit <- function(p) {
  if (p %in% order) return()
  for (d in setdiff(tools::package_dependencies(p, av, which = c("Depends", "Imports", "LinkingTo"))[[1]], base)) visit(d)
  order <<- c(order, p)
}
for (p in all) visit(p)
got <- download.packages(order, src, repos = cran, type = "source", quiet = TRUE)
tools::write_PACKAGES(src, type = "source")
say("sources: %s", paste(order, collapse = " "))

## 2. binaries: R CMD INSTALL --build, one at a time, timed
rcmd <- file.path(R.home("bin"), "R")
times <- data.frame()
old <- setwd(file.path(work, "buildlib"))
for (p in order) {
  tgz <- got[got[, 1] == p, 2]
  log <- file.path(work, paste0("build-", p, ".log"))
  t <- system.time(st <- system(paste(shQuote(rcmd), "CMD INSTALL --build -l", shQuote(lib), shQuote(tgz),
                                      ">", shQuote(log), "2>&1")))[["elapsed"]]
  if (st != 0) stop("build failed: ", p, " (see build-", p, ".log)")
  out <- list.files(".", paste0("^", p, "_.*_R_.*\\.tar\\.gz$"))
  ## CRAN-like name: <pkg>_<ver>.tar.gz (write_PACKAGES parses it so)
  ver <- read.dcf(file.path(lib, p, "DESCRIPTION"), "Version")[1, 1]
  dest <- file.path(bin, sprintf("%s_%s.tar.gz", p, ver))
  file.rename(out, dest)
  times <- rbind(times, data.frame(package = p, version = ver, build_s = round(t, 1),
                                   size_kb = round(file.size(dest) / 1024), compiled = dir.exists(file.path(lib, p, "libs"))))
  say("built %-12s %6.1f s %6d KB", p, t, round(file.size(dest) / 1024))
}
setwd(old)

## 3. the index: CRAN's fields plus Built (R CMD INSTALL's) and what this
## repository adds: the ABI key, the r-zig build, and the shared libraries
## outside R and the C runtime that each package's .so needs (SystemLibs,
## as Posit's manylinux binaries record them).
needed <- function(p) {
  so <- list.files(file.path(lib, p, "libs"), "\\.so$", full.names = TRUE)
  if (!length(so)) return("")
  n <- unlist(lapply(so, function(f) {
    o <- suppressWarnings(system2("readelf", c("-d", shQuote(f)), stdout = TRUE))
    sub(".*\\[(.*)\\].*", "\\1", grep("(NEEDED)", o, value = TRUE, fixed = TRUE))
  }))
  sys <- "^(libR\\.so|libc\\.so|libm\\.so|libdl\\.so|libpthread\\.so|librt\\.so|libgcc_s\\.so|libstdc\\+\\+\\.so|ld-linux)"
  paste(sort(unique(n[!grepl(sys, n)])), collapse = ", ")
}
t <- system.time(tools::write_PACKAGES(bin, type = "source", fields = c("Built", "NeedsCompilation")))[["elapsed"]]
pk <- read.dcf(file.path(bin, "PACKAGES"))
pk <- cbind(pk, "RZig-ABI" = key, "RZig-Build" = rzig_build,
            SystemLibs = vapply(pk[, "Package"], needed, ""))
write.dcf(pk, file.path(bin, "PACKAGES"))
con <- gzfile(file.path(bin, "PACKAGES.gz"), "wt"); write.dcf(pk, con); close(con)
saveRDS(pk, file.path(bin, "PACKAGES.rds"), compress = "xz")
say("index: %d packages, %.2f s; key %s", nrow(pk), t, key)
write.table(times, file.path(work, "times.tsv"), sep = "\t", row.names = FALSE, quote = FALSE)

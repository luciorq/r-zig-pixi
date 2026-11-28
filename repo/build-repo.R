## r-zig binary repository builder (repo/README.md; b14-l5 PLAN.md).
##
##   Rscript repo/build-repo.R <out> [<packages.tsv>]
##
## Run it with the R of a conda env that holds a published r-zig build
## and its toolchain (r-zig-toolchain) plus the -devel libraries the
## packages link (repo.yaml's specs). It downloads the packages of
## packages.tsv and their hard dependencies from CRAN, builds each with
## `R CMD INSTALL`, puts the libraries its .so files need outside R's own
## beside them (below), tars it as R CMD INSTALL --build does, and writes
## a CRAN-like repository:
##
##   <out>/repo/linux-<arch>-rzig<abi>/<R x.y>/src/contrib/
##       <pkg>_<version>.tar.gz   the binaries (installed packages, tarred)
##       PACKAGES PACKAGES.gz PACKAGES.rds
##   <out>/build.tsv   per package: version, seconds, KB, result
##   <out>/logs/       each package's R CMD INSTALL output
##
## `<out>/repo/linux-<arch>-rzig<abi>/<R x.y>` is a repository root for
## `options(repos = ...)`: R adds /src/contrib to it and installs the
## binaries as "source" packages, which R CMD INSTALL recognizes as built
## (Posit P3M's linux trick; no R change). The path below <out> is also
## the GitHub Release tag the workflow uploads it to, so the URL of the
## root is .../releases/download/repo/linux-<arch>-rzig<abi>/<R x.y>.
##
## The key, what a binary is valid for (b13-design D9): R's x.y, the
## platform, and r-zig's package ABI epoch (`abi` below). The r-zig build
## that made a binary is a PACKAGES field (RZig-Build), not part of the
## key. Bump the epoch when a binary built before cannot load or behave
## the same in the new build: libR's exported ABI, the C++ standard
## library (build 12's libc++ to libstdc++ switch), the OpenMP runtime,
## the glibc floor, and the libraries libR loads (`r_libs` below: a
## binary relies on them and does not carry them). A new epoch is a new
## repository, built from scratch.
##
## Experimental (b14-l5, the user's U3): this layout, the key and the
## bundling below are to be reviewed again in a later build.
abi <- 1L

## A binary needs nothing outside R (b14-l5, the user's U5): R from any
## conda env, the r-zig wheel in a plain venv, and R embedded in a Python
## from anywhere load it with no environment variable. So the shared
## libraries its ELF files need (DT_NEEDED) that libR does not load
## itself (`r_libs`) are copied from the build env's lib/ into
## <pkg>/libs/, beside the package's .so, with what they need in turn
## (xml2: libxml2.so.16 and ICU's libicuuc/libicudata; data.table:
## libomp.so), and found there through the only rpath the package's
## files carry, $ORIGIN: the build runs with R_ZIG_ENV_RPATH=origin
## (rzig, r-zig build 14 on). A copied library that needs another copied
## one must find it the same way: conda-forge's carry `$ORIGIN/.` or
## `$ORIGIN/` (b14-l5 F24), so this is a plain copy (no patchelf), and a
## library without such an rpath fails the package (`origin_dir`). Where a
## library of that SONAME is already loaded (libomp by an R with OpenMP,
## or another package's libxml2), the loader uses that one: no second
## copy in the process (b14-l5 F22). Each package's bundled files are
## recorded in <pkg>/rzig-bundled/: SOURCES (conda package, version,
## build, URL, sha256, licence, files) and LICENSES/<conda package>/
## (its info/licenses). A file with an absolute rpath fails the package
## (an rzig before build 14 ignores R_ZIG_ENV_RPATH), as does a library
## the build env's lib/ does not have.
##
## Extra fields per package: RZig-ABI and RZig-Build as above;
## RZig-Bundled, the bundled libraries with their conda packages, as
## `libxml2.so.16 (libxml2-16 2.15.4)`; SHA256 of the tarball.

args <- commandArgs(TRUE)
if (length(args) < 1L) stop("usage: Rscript build-repo.R <out> [<packages.tsv>]")
## this script's directory: Rscript passes --file=<file>; r-zig's Rscript
## before build 14 passed -f <file>. R's front end shows a space in it
## as ~+~.
ca <- commandArgs(FALSE)
here <- dirname(normalizePath(gsub("~+~", " ", c(sub("^--file=", "", grep("^--file=", ca, value = TRUE)), ca[match("-f", ca) + 1])[1], fixed = TRUE)))
dir.create(args[1], recursive = TRUE, showWarnings = FALSE)
out <- normalizePath(args[1])
list_file <- if (length(args) >= 2L) args[2] else file.path(here, "packages.tsv")
cran <- Sys.getenv("RZIG_REPO_CRAN", "https://cloud.r-project.org")
say <- function(...) cat(sprintf(...), "\n", sep = "")
if (R.version$os != "linux-gnu") stop("linux only for now (repo/README.md)")

rxy <- sub("^([0-9]+\\.[0-9]+).*", "\\1", getRversion())
key <- sprintf("linux-%s-rzig%d", R.version$arch, abi)
prefix <- normalizePath(file.path(R.home(), "../.."))

## The r-zig build: r-zig-slim's conda-meta record, e.g.
## `r-zig-slim 4.6.2 h3e03716_12`
meta <- list.files(file.path(prefix, "conda-meta"), "\\.json$")
slim <- grep("^r-zig-slim-[^-]+-[^-]+\\.json$", meta, value = TRUE)
if (length(slim) != 1L) stop("not a conda env with r-zig-slim: ", prefix)
rzig_build <- sub("^(r-zig-slim)-([^-]+)-([^-]+)\\.json$", "\\1 \\2 \\3", slim)

rows <- read.delim(list_file, comment.char = "#", quote = "", colClasses = "character")
targets <- rows$package
## a row's env column: NAME=VALUE;NAME=VALUE for its own build
pkg_env <- function(p) {
  e <- rows$env[match(p, rows$package)]
  if (is.na(e) || e == "-") character() else strsplit(e, ";", fixed = TRUE)[[1]]
}
contrib <- file.path(out, "repo", key, rxy, "src", "contrib")
work <- file.path(out, "work")
lib <- file.path(work, "lib")
logs <- file.path(out, "logs")
unlink(c(contrib, work, logs), recursive = TRUE)
for (d in c(contrib, file.path(work, "src"), lib, logs)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(lib, .libPaths()))
Sys.setenv(R_ZIG_ENV_RPATH = "origin")
if (!nzchar(Sys.getenv("MAKEFLAGS"))) Sys.setenv(MAKEFLAGS = paste0("-j", parallel::detectCores()))
say("key %s, %s, %s, %d targets", key, rzig_build, prefix, length(targets))

## 1. The sources: the targets and their hard dependencies, in an order
## where each comes after what it needs. Base packages are R's.
av <- available.packages(repos = cran, type = "source")
miss <- setdiff(targets, rownames(av))
if (length(miss)) stop("not on CRAN: ", paste(miss, collapse = " "))
base <- rownames(installed.packages(priority = "base"))
hard <- c("Depends", "Imports", "LinkingTo")
order <- character()
visit <- function(p) {
  if (p %in% order) return()
  for (d in setdiff(tools::package_dependencies(p, av, which = hard)[[1]], base)) visit(d)
  order <<- c(order, p)
}
for (p in targets) visit(p)
got <- download.packages(order, file.path(work, "src"), repos = cran, type = "source", quiet = TRUE)
say("sources (%d): %s", length(order), paste(order, collapse = " "))

## The dynamic section of an ELF64 little-endian file (linux-64 and
## linux-aarch64): its DT_NEEDED, DT_RPATH and DT_RUNPATH strings. Read
## here, so the build host needs no binutils.
elf_dynamic <- function(f) {
  b <- readBin(f, "raw", file.size(f))
  u <- function(off, n) sum(as.numeric(b[off + seq_len(n)]) * 256^(seq_len(n) - 1))
  if (!identical(b[1:6], as.raw(c(0x7f, 0x45, 0x4c, 0x46, 2, 1)))) stop(f, ": not an ELF64 little-endian file")
  shoff <- u(0x28, 8); shentsize <- u(0x3a, 2); shnum <- u(0x3c, 2)
  sh <- function(i) { o <- shoff + i * shentsize; list(type = u(o + 4, 4), offset = u(o + 24, 8), size = u(o + 32, 8), link = u(o + 40, 4)) }
  str_at <- function(strtab, off) {
    s <- strtab$offset + off; e <- s
    while (b[e + 1] != as.raw(0)) e <- e + 1
    rawToChar(b[(s + 1):e])
  }
  res <- list(needed = character(), rpath = character())
  for (i in seq_len(shnum) - 1) {
    s <- sh(i)
    if (s$type != 6) next # SHT_DYNAMIC
    strtab <- sh(s$link)
    for (o in seq(s$offset, by = 16, length.out = s$size / 16)) {
      tag <- u(o, 8)
      if (tag == 0) break
      if (tag == 1) res$needed <- c(res$needed, str_at(strtab, u(o + 8, 8)))
      if (tag %in% c(15, 29)) res$rpath <- c(res$rpath, strsplit(str_at(strtab, u(o + 8, 8)), ":", fixed = TRUE)[[1]])
    }
  }
  res
}

## What a binary does not carry: the C runtime (glibc), R's own
## libraries, and what libR itself needs, so every R has loaded it before
## a package: the intersection of libR's DT_NEEDED closures in r-zig-slim
## and in the wheel's minimal tree (b14-l5 F19; libomp, ICU and
## libdeflate only slim's libR loads). libRlapack is R's, found as R's
## modules find it.
r_libs <- paste0("^(", paste(c(
  "ld-linux.*", "libc\\.so\\.6", "libm\\.so\\.6", "libdl\\.so\\.2", "libpthread\\.so\\.0", "librt\\.so\\.1",
  "libutil\\.so\\.1", "libresolv\\.so\\.2", "libmvec\\.so\\.1",
  "libR\\.so", "libRblas\\.so", "libRlapack\\.so",
  "libstdc\\+\\+\\.so\\.6", "libgcc_s\\.so\\.1", "libz\\.so\\.1", "libbz2\\.so\\.1\\.0", "liblzma\\.so\\.5",
  "libzstd\\.so\\.1", "libpcre2-8\\.so\\.0", "libiconv\\.so\\.2"), collapse = "|"), ")$")
## The conda package of the build env whose files include lib/<soname>:
## its conda-meta record (name, version, build, url, sha256, license,
## extracted_package_dir for its info/licenses).
owner <- local({
  recs <- lapply(meta, function(m) readLines(file.path(prefix, "conda-meta", m), warn = FALSE))
  ## a top-level string field: rattler writes the record with a
  ## two-space indent, and paths_data's per-file sha256 sit deeper
  field <- function(j, k) {
    m <- grep(sprintf('^  "%s": "', k), j, value = TRUE)
    if (length(m)) sub('^  "[^"]*": "([^"]*)",?$', "\\1", m[1]) else NA_character_
  }
  function(so) {
    hit <- which(vapply(recs, function(j) any(grepl(paste0("\"lib/", so, "\""), j, fixed = TRUE)), NA))
    if (!length(hit)) return(NULL)
    vapply(c("name", "version", "build", "url", "sha256", "license", "extracted_package_dir"), function(k) field(recs[[hit[1]]], k), "")
  }
})
## An rpath entry relative to the file: $ORIGIN or ${ORIGIN}, alone or
## followed by a "/" (b14-review B8: ${ORIGIN} was accepted by origin_dir
## and refused as "other than $ORIGIN" by the two checks that use this).
origin_rel <- function(rpath) grepl("^\\$(ORIGIN|\\{ORIGIN\\})(/|$)", rpath)
## An rpath entry that is the file's own directory: $ORIGIN, $ORIGIN/,
## $ORIGIN/. (also as ${ORIGIN}). A file that needs a carried library
## needs one, since the library sits beside it in libs/.
origin_dir <- function(rpath) any(grepl("^\\$(ORIGIN|\\{ORIGIN\\})(/\\.?)?/?$", rpath))
is_elf <- function(f) {
  con <- file(f, "rb"); on.exit(close(con))
  identical(readBin(con, "raw", 4L), as.raw(c(0x7f, 0x45, 0x4c, 0x46)))
}
## Bundle into <lib>/<p>/libs what the package's ELF files need outside
## r_libs and the package itself, from the build env's lib/, with what
## those need in turn. Returns list(why = "" or the reason it cannot,
## files = each bundled SONAME with its conda package and version).
bundle <- function(p) {
  pdir <- file.path(lib, p)
  libs <- file.path(pdir, "libs")
  elf <- Filter(is_elf, list.files(pdir, recursive = TRUE, full.names = TRUE))
  dyn <- lapply(elf, elf_dynamic)
  rp <- unique(unlist(lapply(dyn, `[[`, "rpath")))
  abs_rpath <- rp[!origin_rel(rp)]
  if (length(abs_rpath)) return(list(why = paste("rpath other than $ORIGIN:", paste(abs_rpath, collapse = ":"), "(rzig before build 14 ignores R_ZIG_ENV_RPATH)")))
  own <- basename(elf)
  need <- setdiff(grep(r_libs, unique(unlist(lapply(dyn, `[[`, "needed"))), value = TRUE, invert = TRUE), own)
  users <- vapply(dyn, function(d) any(d$needed %in% need), NA)
  if (length(need) && !all(dirname(elf[users]) == libs))
    return(list(why = paste("a file outside libs/ needs", paste(need, collapse = " "))))
  if (length(need) && !all(vapply(dyn[users], function(d) origin_dir(d$rpath), NA)))
    return(list(why = paste("a file in libs/ needs", paste(need, collapse = " "), "but has no $ORIGIN rpath")))
  done <- character()
  src <- list()
  while (length(need)) {
    so <- need[1]; need <- need[-1]
    if (so %in% done) next
    f <- file.path(prefix, "lib", so)
    o <- owner(so)
    if (!file.exists(f) || is.null(o)) return(list(why = paste(so, "is needed but not a conda package's file in", file.path(prefix, "lib"))))
    d <- elf_dynamic(f)
    bad <- d$rpath[!origin_rel(d$rpath)]
    if (length(bad)) return(list(why = paste(so, "has rpath", paste(bad, collapse = ":"))))
    more <- setdiff(grep(r_libs, d$needed, value = TRUE, invert = TRUE), own)
    if (length(more) && !origin_dir(d$rpath))
      return(list(why = paste(so, "needs", paste(more, collapse = " "), "but has no $ORIGIN rpath to find them beside it")))
    if (!file.copy(normalizePath(f), file.path(libs, so), copy.mode = TRUE)) return(list(why = paste("cannot copy", f)))
    Sys.chmod(file.path(libs, so), "755")
    done <- c(done, so)
    src[[so]] <- o
    need <- c(need, setdiff(more, done))
  }
  if (length(done)) {
    rec <- file.path(pdir, "rzig-bundled")
    dir.create(file.path(rec, "LICENSES"), recursive = TRUE)
    blocks <- character()
    for (pkg in unique(vapply(src, `[[`, "", "name"))) {
      o <- src[[which(vapply(src, `[[`, "", "name") == pkg)[1]]]
      lic <- file.path(o[["extracted_package_dir"]], "info", "licenses")
      ## an empty info/licenses is no licence (b14-review B8)
      lf <- if (is.na(o[["extracted_package_dir"]])) character() else list.files(lic, full.names = TRUE)
      ## conda-forge's recipe-scripts-license.txt is the licence of its
      ## recipe scripts, not of the library (b14-review M1)
      real <- if (length(lf)) setdiff(basename(list.files(lic, recursive = TRUE)), "recipe-scripts-license.txt") else character()
      if (!length(real)) return(list(why = paste("no licence files of", pkg, "at", lic)))
      dir.create(file.path(rec, "LICENSES", pkg))
      if (!all(file.copy(lf, file.path(rec, "LICENSES", pkg), recursive = TRUE)))
        return(list(why = paste("cannot copy the licence files of", pkg, "from", lic)))
      files <- names(src)[vapply(src, `[[`, "", "name") == pkg]
      blocks <- c(blocks, paste0(c(
        sprintf("package: %s", pkg), sprintf("version: %s", o[["version"]]), sprintf("build: %s", o[["build"]]),
        sprintf("url: %s", o[["url"]]), sprintf("sha256: %s", o[["sha256"]]), sprintf("license: %s", o[["license"]]),
        sprintf("file: libs/%s %s", files, unname(tools::sha256sum(file.path(libs, files))))), collapse = "\n"))
    }
    writeLines(c("# Libraries in libs/ that this binary carries from conda-forge (r-zig's repo/build-repo.R),",
                 "# each with the conda package it is from; their licences are in LICENSES/<package>/.", "",
                 paste(blocks, collapse = "\n\n")), file.path(rec, "SOURCES"))
  }
  list(why = "", files = vapply(names(src), function(so) sprintf("%s (%s %s)", so, src[[so]][["name"]], src[[so]][["version"]]), ""))
}

## 2. The binaries, one at a time (MAKEFLAGS gives each its cores). A
## failed package skips the ones that need it; the rest go on. Each is
## installed into <work>/lib, gets its bundled libraries there, and is
## tarred from there as R CMD INSTALL --build tars it (<pkg>/ at the top,
## DESCRIPTION's Built field marks it as built).
rcmd <- file.path(R.home("bin"), "R")
res <- data.frame()
fields <- list()
failed <- character()
old <- setwd(work)
for (p in order) {
  deps <- setdiff(tools::package_dependencies(p, av, which = hard)[[1]], base)
  ver <- av[p, "Version"]
  if (any(deps %in% failed)) {
    failed <- c(failed, p)
    res <- rbind(res, data.frame(package = p, version = ver, seconds = NA, kb = NA, result = "skipped (dependency failed)"))
    next
  }
  log <- file.path(logs, paste0(p, ".log"))
  t <- system.time(st <- system2(rcmd, c("CMD", "INSTALL", "-l", shQuote(lib), shQuote(got[got[, 1] == p, 2])), stdout = log, stderr = log, env = pkg_env(p)))[["elapsed"]]
  b <- if (st == 0 && file.exists(file.path(lib, p, "DESCRIPTION"))) bundle(p) else list(why = "build failed")
  if (nzchar(b$why)) {
    failed <- c(failed, p)
    res <- rbind(res, data.frame(package = p, version = ver, seconds = round(t, 1), kb = NA, result = b$why))
    say("FAILED %-12s %s (logs/%s.log)", p, b$why, p)
    next
  }
  dest <- file.path(contrib, sprintf("%s_%s.tar.gz", p, ver))
  local({ o <- setwd(lib); on.exit(setwd(o)); utils::tar(dest, p, compression = "gzip", tar = "internal") })
  fields[[p]] <- c("RZig-Bundled" = if (length(b$files)) paste(b$files, collapse = ", ") else NA,
                   SHA256 = unname(tools::sha256sum(dest)))
  res <- rbind(res, data.frame(package = p, version = ver, seconds = round(t, 1), kb = round(file.size(dest) / 1024), result = "ok"))
  say("built  %-12s %6.1f s %6d KB %s", p, t, round(file.size(dest) / 1024), if (length(b$files)) fields[[p]][["RZig-Bundled"]] else "")
}
setwd(old)
unlink(work, recursive = TRUE)

## 3. The index: CRAN's fields, R CMD INSTALL's Built, and this
## repository's own.
t <- system.time(tools::write_PACKAGES(contrib, type = "source", fields = c("Built", "NeedsCompilation")))[["elapsed"]]
pk <- if (length(fields)) read.dcf(file.path(contrib, "PACKAGES")) else matrix(character(), 0, 1, dimnames = list(NULL, "Package"))
if (nrow(pk)) {
  extra <- do.call(rbind, fields[pk[, "Package"]])
  pk <- cbind(pk, "RZig-ABI" = key, "RZig-Build" = rzig_build, extra)
}
## one line per field, as long as it is (no NA fields: RZig-Bundled)
write.dcf(pk, file.path(contrib, "PACKAGES"), width = 10000)
con <- gzfile(file.path(contrib, "PACKAGES.gz"), "wt"); write.dcf(pk, con, width = 10000); close(con)
saveRDS(pk, file.path(contrib, "PACKAGES.rds"), compress = "xz")
write.table(res, file.path(out, "build.tsv"), sep = "\t", row.names = FALSE, quote = FALSE, na = "-")
say("index: %d packages in %.2f s; %d failed; root %s", nrow(pk), t, length(failed), dirname(dirname(contrib)))
if (length(failed)) quit(status = 1)

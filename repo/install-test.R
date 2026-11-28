## r-zig binary repository: install the curated packages from a finished
## repository into a new library and run each row's smoke (repo/README.md).
##
##   Rscript repo/install-test.R <repository root> <library> [<packages.tsv>]
##
## <repository root> is what users put in options(repos): a URL, or a
## directory (`file://` is added), e.g.
## <out>/repo/linux-x86_64-rzig1/4.6 from build-repo.R. Only that
## repository is used, so every dependency must be in it. Run it with an
## R that has no toolchain and nothing else (r-zig-slim alone, or the
## r-zig wheel): a package that would need compiling fails, and so does
## one whose libraries are not all in it or in R. After the smokes, each
## bundled library (PACKAGES' RZig-Bundled) that the process mapped must
## come from the package's libs/ or from R's own prefix, never from the
## host (b14-l5 F25).
args <- commandArgs(TRUE)
if (length(args) < 2L) stop("usage: Rscript install-test.R <repository root> <library> [<packages.tsv>]")
## this script's directory: Rscript passes --file=<file>; r-zig's Rscript
## before build 14 passed -f <file>. R's front end shows a space in it
## as ~+~.
ca <- commandArgs(FALSE)
here <- dirname(normalizePath(gsub("~+~", " ", c(sub("^--file=", "", grep("^--file=", ca, value = TRUE)), ca[match("-f", ca) + 1])[1], fixed = TRUE)))
root <- args[1]
if (!grepl("^[a-z]+://", root)) root <- paste0("file://", normalizePath(root))
lib <- args[2]
rows <- read.delim(if (length(args) >= 3L) args[3] else file.path(here, "packages.tsv"), comment.char = "#", quote = "", colClasses = "character")
say <- function(...) cat(sprintf(...), "\n", sep = "")

say("make on PATH: '%s'", Sys.which("make"))
unlink(lib, recursive = TRUE); dir.create(lib, recursive = TRUE)
av <- available.packages(repos = root, type = "source", fields = c("RZig-ABI", "RZig-Build", "RZig-Bundled"))
say("repository %s: %d packages, %s, %s", root, nrow(av), av[1, "RZig-ABI"], av[1, "RZig-Build"])
t <- system.time(install.packages(rows$package, lib = lib, repos = root, type = "source", quiet = TRUE))[["elapsed"]]
inst <- list.dirs(lib, recursive = FALSE, full.names = FALSE)
say("installed %d packages in %.1f s: %s", length(inst), t, paste(inst, collapse = " "))

.libPaths(c(lib, .libPaths()))
bad <- 0L
for (i in seq_len(nrow(rows))) {
  p <- rows$package[i]
  r <- tryCatch({
    loadNamespace(p)
    v <- eval(str2lang(rows$smoke[i]), globalenv())
    if (isTRUE(v)) "ok" else paste("smoke gave", format(v)[1])
  }, error = function(e) paste("ERROR:", conditionMessage(e)))
  built <- if (p %in% inst) packageDescription(p, lib.loc = lib)$Built else "-"
  if (r != "ok") bad <- bad + 1L
  say("SMOKE %-12s %s  (Built: %s)", p, r, built)
}
say("%d of %d smokes ok", nrow(rows) - bad, nrow(rows))

## where the bundled libraries came from
sonames <- unique(sub(" .*", "", unlist(strsplit(na.omit(av[, "RZig-Bundled"]), ", ", fixed = TRUE))))
maps <- unique(sub("^\\S+\\s+\\S+\\s+\\S+\\s+\\S+\\s+\\S+\\s+", "", grep("/", readLines("/proc/self/maps"), value = TRUE)))
ok_dirs <- normalizePath(c(lib, file.path(R.home(), "../..")))
for (so in sonames) {
  m <- maps[startsWith(basename(maps), so)]
  where <- if (!length(m)) "not loaded" else paste(m, collapse = " ")
  host <- length(m) && !all(vapply(m, function(f) any(startsWith(normalizePath(f), paste0(ok_dirs, "/"))), NA))
  if (host) bad <- bad + 1L
  say("LIB   %-18s %s%s", so, where, if (host) "  <- NOT from the package or R" else "")
}
if (bad) quit(status = 1)

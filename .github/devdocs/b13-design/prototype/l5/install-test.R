## L5 prototype (b13-design PLAN.md): install the binaries from the
## file:// repository into a fresh library of an R with no toolchain.
##   Rscript install-test.R <work dir> <pkg,pkg,...> <mode> <label>
## mode contriburl: install.packages(contriburl = <bin/linux/<key>/contrib/x.y>)
## mode repos:      install.packages(repos = <root>), the root's src/contrib
##                  being the same binaries (the P3M layout, no R change)
args <- commandArgs(TRUE)
work <- normalizePath(args[1]); targets <- strsplit(args[2], ",")[[1]]
mode <- args[3]; label <- args[4]
say <- function(...) cat(sprintf(...), "\n", sep = "")
rver <- paste(R.version$major, strsplit(R.version$minor, ".", fixed = TRUE)[[1]][1], sep = ".")
key <- sprintf("%s-rzig%s", R.version$arch, Sys.getenv("RZIG_ABI", "1"))
bin <- file.path(work, "repo/bin/linux", key, "contrib", rver)
say("toolchain in this R: %s", file.exists(file.path(R.home("bin"), "toolchain", "zig-cc")))
say("make on PATH: '%s'", Sys.which("make"))
lib <- file.path(work, paste0("lib-", label)); unlink(lib, recursive = TRUE); dir.create(lib)
t <- system.time(
  if (mode == "contriburl") {
    install.packages(targets, lib = lib, contriburl = paste0("file://", bin), type = "source", quiet = TRUE)
  } else {
    root <- file.path(work, "p3m", key); dir.create(file.path(root, "src"), recursive = TRUE, showWarnings = FALSE)
    if (!file.exists(file.path(root, "src/contrib"))) file.symlink(bin, file.path(root, "src/contrib"))
    install.packages(targets, lib = lib, repos = paste0("file://", root), type = "source", quiet = TRUE)
  }
)[["elapsed"]]
inst <- list.dirs(lib, recursive = FALSE, full.names = FALSE)
say("installed %d packages in %.2f s (%s): %s", length(inst), t, mode, paste(inst, collapse = " "))
.libPaths(c(lib, .libPaths()))
for (p in targets) {
  built <- if (p %in% inst) packageDescription(p, lib.loc = lib)$Built else "-"
  r <- tryCatch({
    switch(p,
      Rcpp = { Rcpp::evalCpp; TRUE },
      jsonlite = identical(jsonlite::fromJSON("[1,2]"), c(1L, 2L)),
      cli = nchar(cli::ansi_strip(cli::format_inline("{.pkg x}"))) > 0,
      data.table = data.table::data.table(a = 1:3)[, sum(a)] == 6L,
      xml2 = xml2::xml_text(xml2::read_xml("<a>hi</a>")) == "hi",
      { loadNamespace(p); TRUE })
  }, error = function(e) paste("ERROR:", conditionMessage(e)))
  say("SMOKE %s %-10s %s  (Built: %s)", label, p, r, built)
}

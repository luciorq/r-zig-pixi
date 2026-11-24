## L4 prototype on kappa (b13-design PLAN.md): run.bat's R side.
##   test.R <cfg> probe          what R sees: tools, shells, make
##   test.R <cfg> fetch          the CRAN sources, once, as a local repo
##   test.R <cfg> install [pkgs] each target into a fresh library, timed
##   test.R <cfg> bake           the F1 change into this env's tools package
args <- commandArgs(TRUE)
cfg <- args[1]; step <- args[2]
S <- "C:/Users/admin/rz-b13-design"
repo <- paste0("file:///", S, "/cran")
targets <- c("jsonlite", "minqa", "ps", "Rmpfr", "RcppParallel")
deps <- c("Rcpp", "gmp")
say <- function(...) cat(sprintf(...), "\n", sep = "")

if (step == "probe") {
  say("R %s, R_HOME %s", getRversion(), R.home())
  say("R_CUSTOM_TOOLS_PATH=%s", Sys.getenv("R_CUSTOM_TOOLS_PATH"))
  for (t in c("sh", "bash", "make", "sed", "grep", "awk", "rm", "cp", "chmod",
              "uname", "tar", "find", "pkg-config", "nm", "zip", "unzip"))
    say("which %-10s %s", t, Sys.which(t))
  say("PATH in session:"); writeLines(paste0("  ", strsplit(Sys.getenv("PATH"), ";")[[1]]))
  rcmd <- file.path(R.home("bin"), "Rcmd.exe")
  out <- system2(rcmd, c("sh", "-c", shQuote("echo sh=$0; uname -a; command -v make sed; echo PATH=$PATH | cut -c1-200")),
                 stdout = TRUE, stderr = TRUE)
  writeLines(paste0("R CMD sh: ", out))
  out <- system2(rcmd, c("config", "SHELL"), stdout = TRUE, stderr = TRUE)
  writeLines(paste0("R CMD config SHELL: ", out))
  out <- system2("make", "--version", stdout = TRUE, stderr = TRUE)
  writeLines(paste0("make: ", head(out, 2)))
  ## busybox's /c/ question (RcppParallel's MSYS Makefiles)
  out <- system2(rcmd, c("sh", "-c", shQuote("cd /c/Windows && pwd || echo no-/c/")), stdout = TRUE, stderr = TRUE)
  writeLines(paste0("cd /c/Windows: ", out))
  for (i in 1:2) {
    t <- system.time(for (j in 1:100) system2(rcmd, c("sh", "-c", "true")))[["elapsed"]]
    say("100x R CMD sh -c true: %.2f s", t)
  }
  mk <- file.path(tempdir(), "bench.mk")
  writeLines(c("all:", paste0("\t@", rep("sh -c true", 200), collapse = "\n")), mk)
  for (i in 1:2) {
    t <- system.time(system2("make", c("-s", "-f", mk)))[["elapsed"]]
    say("200x sh -c true from make: %.2f s", t)
  }
}

if (step == "fetch") {
  d <- file.path(S, "cran/src/contrib"); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  av <- available.packages(repos = "https://cloud.r-project.org", type = "source")
  need <- unique(c(targets, deps))
  need <- unique(c(need, unlist(tools::package_dependencies(need, av, recursive = TRUE))))
  need <- setdiff(need, rownames(installed.packages(priority = "base")))
  got <- download.packages(need, d, repos = "https://cloud.r-project.org", type = "source")
  tools::write_PACKAGES(d, type = "source")
  writeLines(paste(basename(got[, 2])), file.path(S, "cran/fetched.txt"))
  say("fetched %d: %s", nrow(got), paste(basename(got[, 2]), collapse = " "))
}

if (step == "bake") {
  ## Test-only stand-in for ../0016-install-make-args-windows-quotes.patch
  ## (PLAN.md L4-F3): the patch's line, inserted before .shlib_internal's
  ## `cmd <- paste(MAKE, ...)`, then written into this env's tools
  ## lazy-load DB (R CMD SHLIB and INSTALL read no profile that could do it).
  ns <- asNamespace("tools")
  orig <- new.env(); lazyLoad(file.path(system.file("R", package = "tools"), "tools"), envir = orig)
  vars <- ls(orig, all.names = TRUE)
  invisible(lapply(vars, function(v) get(v, envir = ns)))
  f <- get(".shlib_internal", envir = ns); bd <- as.list(body(f))
  at <- which(vapply(bd, function(e) startsWith(paste(deparse(e), collapse = ""), "cmd <- paste(MAKE"), NA))
  stopifnot(length(at) == 1L)
  fix <- quote(if (WINDOWS) makeargs <- gsub("'", "\"", makeargs, fixed = TRUE))
  body(f) <- as.call(c(bd[seq_len(at - 1L)], fix, bd[at:length(bd)]))
  unlockBinding(".shlib_internal", ns); assign(".shlib_internal", f, envir = ns); lockBinding(".shlib_internal", ns)
  say("inserted before body element %d of .shlib_internal", at)
  out <- file.path(S, "tdb", "tools"); dir.create(dirname(out), showWarnings = FALSE)
  tools:::makeLazyLoadDB(ns, out, variables = vars)
  say("wrote %s (%d objects); copy tools.rdb/rdx over %s", out, length(vars), system.file("R", package = "tools"))
}

if (step == "install") {
  pk <- if (length(args) > 2) strsplit(args[3], ",")[[1]] else targets
  res <- data.frame()
  for (p in pk) {
    lib <- file.path(S, "lib", cfg, p); unlink(lib, recursive = TRUE); dir.create(lib, recursive = TRUE)
    log <- file.path(S, "logs", cfg, paste0(p, ".log")); dir.create(dirname(log), recursive = TRUE, showWarnings = FALSE)
    t <- system.time(
      install.packages(p, lib = lib, repos = repo, type = "source", Ncpus = 1L,
                       keep_outputs = file.path(S, "logs", cfg), quiet = TRUE)
    )[["elapsed"]]
    ok <- dir.exists(file.path(lib, p))
    smoke <- if (!ok) "not installed" else tryCatch({
      .libPaths(c(lib, .libPaths()))
      switch(p,
        jsonlite = identical(jsonlite::fromJSON("[1,2]"), c(1L, 2L)),
        minqa = abs(minqa::bobyqa(c(1, 1), function(x) sum((x - 2)^2))$par[1] - 2) < 1e-4,
        ps = ps::ps_pid(ps::ps_handle()) == Sys.getpid(),
        Rmpfr = format(Rmpfr::mpfr(1, 80) / 3) != "",
        RcppParallel = RcppParallel::defaultNumThreads() >= 1)
    }, error = function(e) conditionMessage(e))
    built <- if (ok) {
      ## which builder: rzig build leaves no .o beside the sources; the log says
      lg <- file.path(S, "logs", cfg, paste0(p, ".out"))
      if (file.exists(lg)) { l <- readLines(lg, warn = FALSE); r <- grep("^rzig build: ", l, value = TRUE); if (length(r)) r[1] else "rzig build" } else ""
    } else ""
    res <- rbind(res, data.frame(cfg = cfg, package = p, ok = ok, smoke = as.character(smoke), seconds = round(t, 1), builder = built))
    say("RESULT %s %s ok=%s smoke=%s %.1fs %s", cfg, p, ok, smoke, t, built)
  }
  if (cfg %in% c("N", "M")) {
    lib <- file.path(S, "lib", cfg, "minqa")   # has Rcpp
    .libPaths(c(lib, .libPaths()))
    t <- system.time(r <- tryCatch({
      Rcpp::cppFunction("int twice(int x) { return 2 * x; }"); twice(21L) == 42L
    }, error = function(e) conditionMessage(e)))[["elapsed"]]
    say("RESULT %s cppFunction smoke=%s %.1fs", cfg, r, t)
  }
  write.table(res, file.path(S, "logs", cfg, "results.tsv"), sep = "\t", row.names = FALSE, quote = FALSE)
}

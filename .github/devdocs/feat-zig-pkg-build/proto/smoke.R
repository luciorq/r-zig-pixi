lib <- commandArgs(TRUE)[1]
.libPaths(c(lib, .libPaths()))
chk <- function(name, expr) { v <- tryCatch(expr, error = function(e) paste("ERROR:", conditionMessage(e))); cat(sprintf("%-10s %s\n", name, paste(format(v), collapse = " "))) }
library(cli); chk("cli", nchar(cli::rule()) > 10); chk("cli-md5", cli::hash_md5("abc"))
library(digest); chk("digest", digest::digest("abc", algo = "sha256", serialize = FALSE))
library(quadprog); chk("quadprog", quadprog::solve.QP(diag(2), c(1, 1), diag(2), c(0, 0))$solution)
library(Rcpp); chk("Rcpp", is.loaded("Rcpp_precious_remove", PACKAGE = "Rcpp")); chk("Rcpp-reg", length(getDLLRegisteredRoutines("Rcpp")$.Call))
for (p in c("cli", "digest", "quadprog", "Rcpp")) { chk(paste0("dll-", p), basename(getLoadedDLLs()[[p]][["path"]])); unloadNamespace(p) }
cat("unloaded all; exiting\n")

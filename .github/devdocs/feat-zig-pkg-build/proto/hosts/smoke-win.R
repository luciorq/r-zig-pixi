lib <- commandArgs(TRUE)[1]; .libPaths(c(lib, .libPaths()))
chk <- function(name, expr) { v <- tryCatch(expr, error = function(e) paste("ERROR:", conditionMessage(e))); cat(sprintf("%-10s %s\n", name, paste(format(v), collapse = " "))) }
library(cli); chk("cli", nchar(cli::rule()) > 10); chk("cli-md5", cli::hash_md5("abc"))
chk("cli-reg", length(getDLLRegisteredRoutines("cli")$.Call)); chk("cli-sym", is.loaded("clic_md5", PACKAGE = "cli"))
if (dir.exists(file.path(lib, "quadprog"))) { library(quadprog); chk("quadprog", quadprog::solve.QP(diag(2), c(1, 1), diag(2), c(0, 0))$solution); chk("qp-sym", is.loaded("qpgen2", PACKAGE = "quadprog")) }
for (p in c("cli", "quadprog")) if (p %in% loadedNamespaces()) { chk(paste0("dll-", p), basename(getLoadedDLLs()[[p]][["path"]])); unloadNamespace(p) }
cat("unloaded all; exiting\n")

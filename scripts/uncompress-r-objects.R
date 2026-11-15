## verify-tree.sh's view into R's compressed files
## (fix-no-build-leftovers PLAN.md). The byte search for build paths
## cannot read a lazy-load database or an .rds file: what they hold is
## compressed. This writes each one under R_HOME out uncompressed, to the
## same relative name under OUT, so the same search reads the objects. A
## database (an .rdx with its .rdb) becomes the list of the entries R can
## load from it: its variables, then the environments they refer to, in
## turn (each an entry of its own; here an empty stand-in where it is
## referred to). The variable .__NAMESPACE__., with what only it refers
## to, goes to a file of its own, <name>.rdx.namespace: R CMD INSTALL
## saves the namespace's information, its install directory in it, with
## the package's code, and R never loads it (share/R/nspackloader.R:
## lazyLoad(..., filter = function(n) n != ".__NAMESPACE__.")), so a
## check can tell it apart. Fetching tcltk's entries loads tcltk, which
## warns without a display.
##
## Usage: Rscript --vanilla uncompress-r-objects.R R_HOME OUT

args <- commandArgs(TRUE)
home <- args[1L]
out <- args[2L]
for (f in list.files(home, "[.](rdx|rds)$", recursive = TRUE, all.files = TRUE)) {
    x <- readRDS(file.path(home, f))
    if (endsWith(f, ".rdx")) {
        rdb <- file.path(home, sub("x$", "b", f))
        map <- x
        seen <- character()
        queue <- character()
        ## lazyLoadDBexec's envhook: an environment's name, met once
        stub <- function(name) {
            if (!(name %in% seen)) {
                seen <<- c(seen, name)
                queue <<- c(queue, name)
            }
            new.env(parent = emptyenv())
        }
        fetch <- function(keys) suppressWarnings(
            lapply(keys, lazyLoadDBfetch, rdb, map$compressed, stub))
        walk <- function(keys) {
            x <- fetch(keys)
            while (length(queue)) {
                k <- map$references[[queue[1L]]]
                queue <<- queue[-1L]
                ## an environment saved with lazy parts (a srcfile's lines
                ## and parse data: survival's data) is a list of keys,
                ## eagerKey and lazyKeys, each fetched as an entry
                x <- c(x, fetch(if (is.list(k)) c(list(k$eagerKey), k$lazyKeys) else list(k)))
            }
            x
        }
        ns <- names(map$variables) == ".__NAMESPACE__."
        x <- walk(map$variables[!ns])
        if (any(ns)) {
            dir.create(dirname(file.path(out, f)), FALSE, TRUE)
            writeBin(serialize(walk(map$variables[ns]), NULL),
                     file.path(out, paste0(f, ".namespace")))
        }
    }
    dir.create(dirname(file.path(out, f)), FALSE, TRUE)
    writeBin(serialize(x, NULL), file.path(out, f))
}

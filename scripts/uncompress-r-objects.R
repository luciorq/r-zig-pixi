## verify-tree.sh's view into R's compressed files
## (fix-no-build-leftovers PLAN.md). The byte search for build paths
## cannot read a lazy-load database or an .rds file: what they hold is
## compressed. This writes each one under R_HOME out uncompressed, to the
## same relative name under OUT, so the same search reads the objects. A
## database (an .rdx with its .rdb) becomes the list of all its entries.
## The environments they refer to are entries of their own, so here they
## are empty stand-ins. Fetching tcltk's entries loads tcltk, which warns
## without a display.
##
## Usage: Rscript --vanilla uncompress-r-objects.R R_HOME OUT

args <- commandArgs(TRUE)
home <- args[1L]
out <- args[2L]
stub <- function(name) new.env(parent = emptyenv())
for (f in list.files(home, "[.](rdx|rds)$", recursive = TRUE, all.files = TRUE)) {
    x <- readRDS(file.path(home, f))
    if (endsWith(f, ".rdx")) {
        rdb <- file.path(home, sub("x$", "b", f))
        x <- suppressWarnings(lapply(c(x$variables, x$references), lazyLoadDBfetch,
                                     rdb, x$compressed, stub))
    }
    dir.create(dirname(file.path(out, f)), FALSE, TRUE)
    writeBin(serialize(x, NULL), file.path(out, f))
}

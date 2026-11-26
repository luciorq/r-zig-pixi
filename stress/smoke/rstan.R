# rstan (row smoke `@rstan.R`): compile and sample a one-parameter model.
# The model compiles through inline's R CMD SHLIB (rzig build). inline's
# compileCode keeps that command's output (errmsg) only for its error, cut
# to the last warning.length characters, and drops it after a success. A
# tracer at its `unlink(errfile)` step prints all of it, after a success
# too (chore-release-12 M-2: the compiler's error on Windows; CI6: rzig's
# `rzig build: R CMD SHLIB, tier 1` line under --trace). An exit tracer
# would not run: compileCode's own on.exit() replaces it. message(), not
# cat(): rstan sinks stdout while it compiles.
cc <- get("compileCode", asNamespace("inline"))
at <- which(vapply(as.list(body(cc)), function(e) startsWith(deparse(e)[1], "unlink(errfile)"), NA))
if (length(at) == 1) {
  trace("compileCode", where = asNamespace("inline"), at = at, print = FALSE,
        tracer = quote(message("inline's R CMD SHLIB output:\n", errmsg)))
} else message("inline's compileCode has no unlink(errfile) step: its output is not shown")
m <- stan_model(model_code = "parameters { real y; } model { y ~ normal(0, 1); }")
if (length(at) == 1) untrace("compileCode", where = asNamespace("inline"))
f <- sampling(m, chains = 1, iter = 400, refresh = 0, seed = 1)
abs(mean(as.matrix(f)[, "y"])) < 0.5

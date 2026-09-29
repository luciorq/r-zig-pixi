## TLS trust check for the standalone tree and the wheel, shared by
## scripts/verify-bundle.sh and scripts/wheel-test.sh. Run it with
## `Rscript --vanilla` in an emptied environment (`env -i`).
##
## The vendored libcurl/OpenSSL carry the build env's CA paths compiled
## in. The tree ships etc/ca-bundle.crt and sets R_ZIG_CA_BUNDLE in
## etc/Renviron; R's libcurl.c (patched by scripts/zig-build.sh) picks
## CURL_CA_BUNDLE, else SSL_CERT_FILE, else the system bundle, else the
## shipped file. Callers read the "TLS: " lines: "requests OK" is printed
## only when HTTPS requests really ran, so an offline machine is reported
## as a skip, never as a pass.

fail <- function(...) {
  cat("error: ", ..., "\n", sep = "", file = stderr())
  quit(status = 1)
}

home <- normalizePath(R.home())

## R must not export CURL_CA_BUNDLE: every program R starts (curl,
## Python's requests, ...) would drop its own trust for the shipped copy.
if (nzchar(Sys.getenv("CURL_CA_BUNDLE")))
  fail("CURL_CA_BUNDLE is set in R's environment (", Sys.getenv("CURL_CA_BUNDLE"),
       "); only R_ZIG_CA_BUNDLE should be")

ca <- Sys.getenv("R_ZIG_CA_BUNDLE")
if (!nzchar(ca) || !file.exists(ca) || !startsWith(normalizePath(ca), home))
  fail("R_ZIG_CA_BUNDLE is not a file inside R_HOME: '", ca, "'")
if (!any(grepl("BEGIN CERTIFICATE", readLines(ca, warn = FALSE), fixed = TRUE)))
  fail("R_ZIG_CA_BUNDLE has no certificates: ", ca)

## Overridable to exercise the offline branch (an unresolvable host).
url <- Sys.getenv("R_ZIG_TLS_CHECK_URL", "https://cloud.r-project.org/")
head_url <- function() tryCatch({
  curlGetHeaders(url, timeout = 20L)
  "ok"
}, error = function(e) trimws(gsub("\\s+", " ", conditionMessage(e))))
cert_error <- function(msg)
  grepl("error code (35|58|60|77|83)|certificate|trust anchor|SSL", msg, ignore.case = TRUE)

## 1. Default trust: the system bundle, or the shipped one where there is
##    none.
res <- head_url()
if (!identical(res, "ok")) {
  if (cert_error(res)) fail("HTTPS certificate verification failed: ", res)
  cat("TLS: offline, requests skipped (", res, ")\n", sep = "")
  quit(status = 0)
}

## 2. The shipped bundle itself, through SSL_CERT_FILE.
Sys.setenv(SSL_CERT_FILE = ca)
res <- head_url()
if (!identical(res, "ok")) fail("HTTPS with the shipped bundle failed: ", res)

## 3. The CA rule is compiled in: an SSL_CERT_FILE without certificates
##    must make verification fail. An unpatched libcurl.c ignores it and
##    silently uses the compiled-in (build machine's) path.
empty <- tempfile(fileext = ".pem")
invisible(file.create(empty))
Sys.setenv(SSL_CERT_FILE = empty)
res <- head_url()
if (identical(res, "ok"))
  fail("R ignored SSL_CERT_FILE: the libcurl.c CA patch is not in this build")
if (!cert_error(res)) fail("unexpected error with an empty SSL_CERT_FILE: ", res)
Sys.unsetenv("SSL_CERT_FILE")

cat("TLS: requests OK (default trust, shipped bundle, CA rule active; bundle ",
    sub(home, "R_HOME", normalizePath(ca), fixed = TRUE), ")\n", sep = "")

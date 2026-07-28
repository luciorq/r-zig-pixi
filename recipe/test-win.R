set.seed(1)
m <- matrix(rnorm(64), 8, 8)
stopifnot(max(abs(solve(m) %*% m - diag(8))) < 1e-9)
stopifnot(abs(det(qr.R(qr(m)))) > 0)
stopifnot(max(Mod(fft(fft(1:8), inverse = TRUE) / 8 - 1:8)) < 1e-9)
stopifnot(
  grepl("[0-9]+", "R 4", perl = TRUE),
  identical(memDecompress(memCompress("x")), charToRaw("x"))
)
caps <- capabilities()
stopifnot(caps[["png"]], caps[["iconv"]], caps[["libcurl"]], caps[["cairo"]])
cat("conda R OK\n")

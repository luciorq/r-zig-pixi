## r-zig-recommended's test (recipe.yaml), and verify-recommended.sh's
## against the dev tree (base R with R_LIBS at the staging library): R's
## 15 recommended packages are installed, each loads, and each family of
## compiled code runs one real computation. Run with Rscript.

stopifnot(requireNamespace("tools", quietly = TRUE))
want <- tools:::.get_standard_package_names()$recommended
ip <- installed.packages(priority = "recommended")
have <- unique(rownames(ip))
if (!setequal(have, want))
    stop("installed recommended packages: ", paste(sort(have), collapse = " "),
         "; R names: ", paste(sort(want), collapse = " "))
stopifnot(length(have) == 15L)
## each one's licence is recorded (recipe.yaml's about.license names them)
lic <- ip[match(want, ip[, "Package"]), "License"]
if (anyNA(lic) || any(!nzchar(lic)))
    stop("no License field: ", paste(want[is.na(lic) | !nzchar(lic)], collapse = " "))
for (p in want) {
    suppressPackageStartupMessages(library(p, character.only = TRUE))
    ## R's own version, as R's source carries it
    stopifnot(packageDescription(p)$Built != "")
}
cat("recommended: 15 installed and loaded:", paste(want, collapse = " "), "\n")

near <- function(x, y, tol = 1e-3) isTRUE(all(abs(x - y) <= tol * pmax(1, abs(y))))
set.seed(1)

## Matrix (C, its bundled SuiteSparse): a sparse Cholesky and an LU solve
n <- 200L
A <- Matrix::sparseMatrix(i = c(1:n, 2:n), j = c(1:n, 1:(n - 1)),
                          x = c(rep(4, n), rep(-1, n - 1)), symmetric = TRUE)
b <- rnorm(n)
x1 <- Matrix::solve(Matrix::Cholesky(A), b)
x2 <- Matrix::solve(Matrix::lu(A), b)
stopifnot(near(as.vector(A %*% x1), b, 1e-8), near(as.vector(x2), as.vector(x1), 1e-8))

## mgcv (C, OpenMP): a penalized regression spline, on two threads
d <- mgcv::gamSim(1, n = 400, verbose = FALSE)
g <- mgcv::gam(y ~ s(x0) + s(x1) + s(x2) + s(x3), data = d,
               control = mgcv::gam.control(nthreads = 2))
stopifnot(summary(g)$r.sq > 0.6, sum(g$edf) > 5)

## survival (C): Cox model of the lung data, coefficient of sex
cf <- coef(survival::coxph(survival::Surv(time, status) ~ age + sex, data = survival::lung))
stopifnot(near(cf[["sex"]], -0.5132, 1e-2))

## nlme (C): a linear mixed model of the Orthodont data
fe <- nlme::fixef(nlme::lme(distance ~ age, data = nlme::Orthodont, random = ~ 1 | Subject))
stopifnot(near(fe, c(16.7611, 0.6602), 1e-3))

## MASS (C): negative binomial GLM and a resistant regression (lqs)
nb <- MASS::glm.nb(Days ~ Sex + Age, data = MASS::quine)
stopifnot(nb$converged, nb$theta > 0)
stopifnot(is.finite(coef(MASS::lqs(stack.loss ~ ., data = stackloss))[[1]]))

## cluster (C), class (C), nnet (C), rpart (C), spatial (C)
stopifnot(length(cluster::pam(iris[, 1:4], 3)$medoids) == 12L)
cl <- class::knn(iris[, 1:4], iris[, 1:4], iris$Species, k = 3)
stopifnot(mean(cl == iris$Species) > 0.9)
nn <- nnet::nnet(Species ~ ., data = iris, size = 2, trace = FALSE)
stopifnot(is.finite(nn$value))
rp <- rpart::rpart(Species ~ ., data = iris)
stopifnot(nrow(rp$frame) > 1L)
sf <- spatial::surf.ls(2, spatial::topo)
stopifnot(is.finite(sum(spatial::trmat(sf, 0, 6.5, 0, 6.5, 10)$z)))

## KernSmooth (Fortran): a binned kernel density
k <- KernSmooth::bkde(faithful$eruptions)
stopifnot(near(sum(k$y) * diff(k$x[1:2]), 1, 1e-2))

## foreign (C): a dBase file written and read back
f <- tempfile(fileext = ".dbf")
foreign::write.dbf(data.frame(a = 1:3, b = c("x", "y", "z")), f)
stopifnot(identical(foreign::read.dbf(f, as.is = TRUE)$b, c("x", "y", "z")))

## lattice (C), boot, codetools (R only)
stopifnot(inherits(lattice::xyplot(1:3 ~ 1:3), "trellis"))
bt <- boot::boot(1:20, function(x, i) mean(x[i]), R = 50)
stopifnot(length(bt$t) == 50L)
stopifnot(is.character(codetools::findGlobals(function() x + 1)))

cat("recommended: computations OK\n")

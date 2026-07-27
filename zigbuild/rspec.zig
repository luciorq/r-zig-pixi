//! Source inventory for building R with zig build — the "what" extracted
//! from R 4.6.1's generated Makefiles (see devdocs feat-zig-build).
//! Every list mirrors the resolved SOURCES/OBJECTS variables of the
//! milestone-1 autoconf build (captured in make-vars.txt); keep them in
//! that order so object-link order matches the make build.

/// C sources of src/main linked into libR.so (Rmain.c is the executable,
/// listed separately).
pub const main_c = [_][]const u8{
    "CommandLineArgs.c", "Rdynload.c",   "Renviron.c",   "RNG.c",
    "agrep.c",           "altclasses.c", "altrep.c",     "apply.c",
    "arithmetic.c",      "array.c",      "attrib.c",     "bind.c",
    "builtin.c",         "character.c",  "clippath.c",   "coerce.c",
    "colors.c",          "complex.c",    "connections.c", "context.c",
    "cum.c",             "dcf.c",        "datetime.c",   "debug.c",
    "deparse.c",         "devices.c",    "dotcode.c",    "dounzip.c",
    "dstruct.c",         "duplicate.c",  "edit.c",       "engine.c",
    "envir.c",           "errors.c",     "eval.c",       "flexiblas.c",
    "format.c",          "gevents.c",    "gram.c",       "gram-ex.c",
    "graphics.c",        "grep.c",       "identical.c",  "inlined.c",
    "inspect.c",         "internet.c",   "iosupport.c",  "lapack.c",
    "list.c",            "localecharset.c", "logic.c",   "machine.c",
    "main.c",            "mapply.c",     "mask.c",       "match.c",
    "memory.c",          "names.c",      "objects.c",    "options.c",
    "paste.c",           "patterns.c",   "platform.c",   "plot.c",
    "plot3d.c",          "plotmath.c",   "print.c",      "printarray.c",
    "printvector.c",     "printutils.c", "qsort.c",      "radixsort.c",
    "random.c",          "raw.c",        "registration.c", "relop.c",
    "rlocale.c",         "saveload.c",   "scan.c",       "seq.c",
    "serialize.c",       "sort.c",       "source.c",     "split.c",
    "sprintf.c",         "startup.c",    "subassign.c",  "subscript.c",
    "subset.c",          "summary.c",    "sysutils.c",   "times.c",
    "unique.c",          "util.c",       "version.c",    "g_alab_her.c",
    "g_cntrlify.c",      "g_fontdb.c",   "g_her_glyph.c",
};

pub const appl_c = [_][]const u8{
    "integrate.c", "interv.c", "maxcol.c", "optim.c", "pretty.c", "uncmin.c",
};

pub const appl_f = [_][]const u8{
    "dpbfa.f", "dpbsl.f", "dpoco.f", "dpodi.f", "dpofa.f", "dposl.f",
    "dqrdc.f", "dqrdc2.f", "dqrls.f", "dqrsl.f", "dqrutl.f", "dsvdc.f",
    "dtrco.f", "dtrsl.f",
};

pub const nmath_c = [_][]const u8{
    "mlutils.c",   "d1mach.c",    "i1mach.c",    "fmax2.c",
    "fmin2.c",     "fprec.c",     "fround.c",    "ftrunc.c",
    "sign.c",      "fsign.c",     "imax2.c",     "imin2.c",
    "chebyshev.c", "log1p.c",     "lgammacor.c", "gammalims.c",
    "stirlerr.c",  "bd0.c",       "gamma.c",     "lgamma.c",
    "gamma_cody.c", "beta.c",     "lbeta.c",     "polygamma.c",
    "cospi.c",     "bessel_i.c",  "bessel_j.c",  "bessel_k.c",
    "bessel_y.c",  "choose.c",    "snorm.c",     "sexp.c",
    "dgamma.c",    "pgamma.c",    "qgamma.c",    "rgamma.c",
    "dbeta.c",     "pbeta.c",     "qbeta.c",     "rbeta.c",
    "dunif.c",     "punif.c",     "qunif.c",     "runif.c",
    "dnorm.c",     "pnorm.c",     "qnorm.c",     "rnorm.c",
    "dlnorm.c",    "plnorm.c",    "qlnorm.c",    "rlnorm.c",
    "df.c",        "pf.c",        "qf.c",        "rf.c",
    "dnf.c",       "dt.c",        "pt.c",        "qt.c",
    "rt.c",        "dnt.c",       "dchisq.c",    "pchisq.c",
    "qchisq.c",    "rchisq.c",    "rnchisq.c",   "dbinom.c",
    "pbinom.c",    "qbinom.c",    "rbinom.c",    "rmultinom.c",
    "dcauchy.c",   "pcauchy.c",   "qcauchy.c",   "rcauchy.c",
    "dexp.c",      "pexp.c",      "qexp.c",      "rexp.c",
    "dgeom.c",     "pgeom.c",     "qgeom.c",     "rgeom.c",
    "dhyper.c",    "phyper.c",    "qhyper.c",    "rhyper.c",
    "dnbinom.c",   "pnbinom.c",   "qnbinom.c",   "qnbinom_mu.c",
    "rnbinom.c",   "dpois.c",     "ppois.c",     "qpois.c",
    "rpois.c",     "dweibull.c",  "pweibull.c",  "qweibull.c",
    "rweibull.c",  "dlogis.c",    "plogis.c",    "qlogis.c",
    "rlogis.c",    "dnchisq.c",   "pnchisq.c",   "qnchisq.c",
    "dnbeta.c",    "pnbeta.c",    "qnbeta.c",    "pnf.c",
    "pnt.c",       "qnf.c",       "qnt.c",       "ptukey.c",
    "qtukey.c",    "toms708.c",   "wilcox.c",    "signrank.c",
};

pub const tre_c = [_][]const u8{
    "regcomp.c", "regerror.c", "regexec.c", "tre-ast.c", "tre-compile.c",
    "tre-match-approx.c", "tre-match-backtrack.c", "tre-match-parallel.c",
    "tre-mem.c", "tre-parse.c", "tre-stack.c",
};

pub const tzone_c = [_][]const u8{ "localtime.c", "strftime.c" };

pub const xdr_c = [_][]const u8{
    "xdr.c", "xdr_float.c", "xdr_mem.c", "xdr_stdio.c",
};

pub const unix_c = [_][]const u8{
    "Rembedded.c", "dynload.c", "system.c", "sys-unix.c", "sys-std.c", "X11.c",
};

pub const blas_f = [_][]const u8{ "blas.f", "cmplxblas.f" };
pub const blas_f90 = [_][]const u8{ "blas2.f90", "cmplxblas2.f90" };

/// libRlapack Fortran, in module-dependency order: la_constants provides
/// the .mod la_xisnan needs; both are used by the lartg/lassq routines.
pub const rlapack_f90_ordered = [_][]const u8{
    "la_constants.f90", "la_xisnan.f90", "dlassq.f90", "zlassq.f90",
    "dlartg.f90",       "zlartg.f90",
};
pub const rlapack_f = [_][]const u8{ "dlamch.f", "dlapack.f", "cmplx.f" };

pub const internet_c = [_][]const u8{
    "Rhttpd.c", "Rsock.c", "internet.c", "libcurl.c", "sock.c", "sockconn.c",
};

pub const stats_c = [_][]const u8{
    "init.c",     "kmeans.c",     "ansari.c",   "bandwidths.c",
    "chisqsim.c", "d2x2xk.c",     "fexact.c",   "kendall.c",
    "ks.c",       "line.c",       "smooth.c",   "prho.c",
    "swilk.c",    "ksmooth.c",    "loessc.c",   "monoSpl.c",
    "isoreg.c",   "Srunmed.c",    "dblcen.c",   "distance.c",
    "hclust-utils.c", "nls.c",    "rWishart.c", "HoltWinters.c",
    "PPsum.c",    "arima.c",      "burg.c",     "filter.c",
    "mAR.c",      "pacf.c",       "starma.c",   "stl.c",
    "port.c",     "family.c",     "sbart.c",    "approx.c",
    "loglin.c",   "lowess.c",     "massdist.c", "splines.c",
    "lm.c",       "complete_cases.c", "cov.c",  "deriv.c",
    "fft.c",      "fourier.c",    "model.c",    "optim.c",
    "optimize.c", "integrate.c",  "random.c",   "distn.c",
    "zeroin.c",   "rcont.c",      "influence.c", "permdist.c",
};

pub const stats_f = [_][]const u8{
    "bsplvd.f", "bvalue.f", "bvalus.f", "loessf.f", "ppr.f", "qsbart.f",
    "sgram.f", "sinerp.f", "sslvrg.f", "stxwx.f", "hclust.f", "kmns.f",
    "eureka.f", "portsrc.f", "lminfl.f",
};

pub const graphics_c = [_][]const u8{
    "init.c", "base.c", "graphics.c", "par.c", "plot.c", "plot3d.c", "stem.c",
};

pub const grdevices_c = [_][]const u8{
    "axis_scales.c", "chull.c", "devices.c", "init.c", "stubs.c", "colors.c",
    "clippath.c", "patterns.c", "mask.c", "group.c", "devCairo.c",
    "devPicTeX.c", "devPS.c", "devQuartz.c",
};

pub const grid_c = [_][]const u8{
    "clippath.c", "gpar.c", "grid.c", "just.c", "layout.c", "mask.c",
    "matrix.c", "path.c", "register.c", "state.c", "typeset.c", "unit.c",
    "util.c", "viewport.c",
};

pub const methods_c = [_][]const u8{
    "do_substitute_direct.c", "init.c", "methods_list_dispatch.c", "slot.c",
    "class_support.c", "tests.c", "utils.c",
};

pub const parallel_c = [_][]const u8{ "init.c", "rngstream.c", "fork.c" };

pub const splines_c = [_][]const u8{"splines.c"};

pub const tools_c = [_][]const u8{
    "text.c", "init.c", "Rmd5.c", "md5.c", "signals.c", "install.c",
    "getfmts.c", "http.c", "gramLatex.c", "gramRd.c", "pdscan.c",
    "Rsha256.c", "sha256.c",
};

pub const utils_c = [_][]const u8{
    "init.c", "io.c", "size.c", "sock.c", "stubs.c", "utils.c", "hashtab.c",
};

/// full variant only (src/library/tcltk/src/Makefile.in SOURCES_C, unix
/// build — excludes tcltk_win.c).
pub const tcltk_c = [_][]const u8{ "init.c", "tcltk.c", "tcltk_unix.c" };

/// Public API headers installed to R_HOME/include (src/include/Makefile.in
/// SRC_HEADERS; OBJ_HEADERS Rconfig.h/Rmath.h/Rversion.h are generated).
pub const public_headers = [_][]const u8{
    "R.h", "Rdefines.h", "Rembedded.h", "Rinternals.h", "Rinterface.h",
};

/// R front-end scripts copied verbatim from src/scripts into R_HOME/bin.
pub const scripts_s = [_][]const u8{
    "BATCH", "COMPILE", "INSTALL", "LINK", "REMOVE", "Rd2pdf", "Rdconv",
    "Rdiff", "Rprof", "SHLIB", "Stangle", "Sweave", "build", "check",
    "config",
};

/// Scripts generated by @VAR@ substitution from src/scripts/*.in.
pub const scripts_b = [_][]const u8{
    "Rcmd", "javareconf", "mkinstalldirs", "pager", "rtags",
};

/// All base packages, in R_PKGS_BASE order (share/make/vars.mk).
pub const pkgs_base = [_][]const u8{
    "base", "tools", "utils", "grDevices", "graphics", "stats", "datasets",
    "methods", "grid", "splines", "stats4", "tcltk", "compiler", "parallel",
};

// ----------------------------------------------------------------------
// Windows (F6): gnuwin32 has no config.status, so these lists come from
// a ground-truth extraction off kappa's own already-built gnuwin32
// objdir (see FINALIZATION.md F6.1a) — Makefile.win SOURCES/OBJECTS
// variables read directly, not guessed. Per F6.0's CLI-only scoping
// decision, only what R.dll/Rblas.dll/Rlapack.dll/Rgraphapp.dll/
// Riconv.dll/Rscript.exe need — no Rgui.exe/Rterm.exe/Rcmd.exe/etc.
// main_c/appl_c/nmath_c/tre_c/tzone_c/xdr_c above are reused as-is —
// R.dll links the exact same objects unix does for those groups.
// ----------------------------------------------------------------------

/// src/gnuwin32/*.c — R.dll's own required core (console/GUI plumbing
/// baked in architecturally, gnuwin32 has no seam to drop it — F6.0).
pub const win_gnuwin32_c = [_][]const u8{
    "console.c", "dos_wglob.c", "dynload.c",   "editor.c",
    "embeddedR.c", "extra.c",   "opt.c",       "pager.c",
    "preferences.c", "psignal.c", "rhome.c",   "rt_complete.c",
    "rui.c",     "run.c",       "shext.c",     "sys-win32.c",
    "system.c",
};

/// src/extra/graphapp/*.c — Rgraphapp.dll, R.dll's required link-time
/// dependency (not prunable — F6.0). All files, gnuwin32 has no partial
/// build (Makefile.win uses `$(wildcard *.c)`).
pub const win_graphapp_c = [_][]const u8{
    "arith.c", "array.c", "bitmaps.c", "buttons.c", "clipboard.c",
    "context.c", "controls.c", "cursors.c", "dialogs.c", "drawing.c",
    "drawtext.c", "events.c", "fonts.c", "gbuttons.c", "gdraw.c",
    "gif.c", "gimage.c", "gmenus.c", "image.c", "init.c",
    "menus.c", "metafile.c", "objects.c", "printer.c", "rgb.c",
    "status.c", "stdimg.c", "strings.c", "tooltips.c", "windows.c",
};

/// src/extra/intl/*.c — Windows' own bundled gettext (a third distinct
/// NLS story: linux gets it free from glibc, macOS needs -lintl +
/// CoreFoundation, Windows needs this compiled). Exact Makefile.win
/// SOURCES list — several more .c files exist in the directory
/// (intl-compat.c, printf-args.c, vasnprintf.c, etc.) but are NOT in
/// SOURCES and are not compiled (likely #included by printf.c/gettext.c,
/// matching trio's compat.o/trio.o #include pattern below).
pub const win_intl_c = [_][]const u8{
    "bindtextdom.c", "dcgettext.c", "dgettext.c",  "gettext.c",
    "finddomain.c",  "loadmsgcat.c", "textdomain.c", "l10nflist.c",
    "explodename.c", "dcigettext.c", "dcngettext.c", "dngettext.c",
    "ngettext.c",    "plural.c",    "plural-exp.c", "langprefs.c",
    "localcharset.c", "localename.c", "printf.c",    "osdep.c",
    "hash-string.c",
};

/// src/extra/trio/*.c — printf-family replacement MinGW needs. Only 2
/// files actually compiled; trionan.c/triostr.c are #included by trio.c.
pub const win_trio_c = [_][]const u8{ "compat.c", "trio.c" };

/// src/extra/win_iconv/*.c — Riconv.dll (R's own bundled iconv; built
/// from source rather than risking an ABI/symbol mismatch substituting
/// conda's libiconv, since R.dll calls this specific `Riconv`-prefixed
/// API — see F6.0).
pub const win_iconv_c = [_][]const u8{"win_iconv.c"};

/// src/extra/blas/*.{f,f90} — Rblas.dll, internal (non-ATLAS/OpenBLAS)
/// path only. Far more aggregated than unix's per-routine split.
pub const win_blas_f = [_][]const u8{ "blas.f", "cmplxblas.f" };
pub const win_blas_f90 = [_][]const u8{ "blas2.f90", "cmplxblas2.f90" };

/// src/modules/lapack/*.f90 — same la_constants -> la_xisnan module-
/// dependency chain as unix's rlapack_f90_ordered (this is the one place
/// Windows' LAPACK layout still matches unix's shape), in compile order.
pub const win_lapack_f90_ordered = [_][]const u8{
    "la_constants.f90", "la_xisnan.f90",
    "dlartg.f90", "dlassq.f90", "zlartg.f90", "zlassq.f90",
};
/// src/modules/lapack/*.f — dlapack.f is a single file aggregating what
/// unix splits across ~15 files; dlamch.f needs -ffloat-store (Makefile.win:
/// `dlamch-FFLAGS = -ffloat-store`, non-LLVM only) and cmplx.f is the
/// complex-routines file (same family as the gfortran-darwin miscompile
/// found on macOS — flag this as unverified-on-Windows, check `make check`
/// there before trusting complex LAPACK).
pub const win_lapack_f = [_][]const u8{ "dlamch.f", "dlapack.f", "cmplx.f" };
/// modules/lapack.dll (the loadable module, unix's mod_lapack equivalent)
/// is just Lapack.c — "flexiblas not supported on Windows" per
/// Makefile.win, so no flexiblas.c counterpart here.
pub const win_lapack_module_c = [_][]const u8{"Lapack.c"};

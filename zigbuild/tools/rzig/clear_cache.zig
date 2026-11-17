//! Windows on ARM links: the instruction-cache flush zig's compiler_rt
//! lacks there (chore-release-11 finding 36). Code that writes machine
//! code at run time calls __clear_cache before it runs it: libffi's
//! ffi_prep_closure_loc, in magick's clang-aarch64 r-windows bundle, so
//! magick's link stops on windows-11-arm ("lld-link: error: undefined
//! symbol: __clear_cache"). LLVM's compiler-rt defines it on Windows with
//! FlushInstructionCache (clear_cache.c, _WIN32), which is how Rtools45's
//! aarch64 clang and r-universe link the bundle; zig's
//! compiler_rt/clear_cache.zig leaves the Windows branch as a TODO, in
//! conda-forge's and upstream's 0.17.1. x86_64 needs no flush (its
//! instruction cache is coherent), and there zig defines none either.
//!
//! The fix is compiler-rt's function, clear_cache.c. R's build compiles
//! it for aarch64 Windows into R_HOME/bin/toolchain/clear_cache.o, beside
//! rzig (build.zig's linkObject), as cfguard.o on x86_64, and
//! compiler.zig passes it on the same links (cfguard.zig's `wanted`): an
//! -o, no compile-only flag, no -r. Nothing calls it unless the link's
//! code does; other links carry its few bytes. The definition is weak: a
//! link that defines __clear_cache itself keeps its own, with no
//! duplicate symbol, and a zig whose compiler_rt gains one links either
//! (both zigs, cross-built on linux-64). It is excluded from lld's MinGW
//! auto-export with the `-exclude-symbols:` directive, as cfguard.S's
//! symbol: a DLL exports what it exported before.
//!
//! No object when the file is missing: the link goes on without it, with
//! a warning.

/// The file in rzig's directory (compiler.zig's linkObject).
pub const file = "clear_cache.o";
pub const consequence = "code that calls __clear_cache (libffi's closures) cannot link";

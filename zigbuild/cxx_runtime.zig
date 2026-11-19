//! linux: one reference each to gcc's C++ runtime, libstdc++.so.6 and
//! libgcc_s.so.1, linked into libR.so (build.zig's linkCxxRuntime), so
//! libR needs both (DT_NEEDED). zig links every shared library with
//! --as-needed and drops one nothing references; build.zig's
//! linkSystemLibrary(.needed) cannot name them (zig maps stdc++ to its
//! libc++ and drops gcc_s). R itself has no C++. Every package's C++
//! links against R's runtime (rzig's libstdcxx.zig), and libR loading it
//! first, through its RUNPATH, makes the tree's or the env's runtime the
//! process's in every variant: minimal, whose libR needs no ICU (which
//! would load it), included. Else packages bind the host's libstdc++,
//! which may be older than the headers they were compiled with
//! (feat-linux-libstdcxx; probe F8).
//! Exported, so the linker keeps it: a hidden symbol is garbage
//! collected with its references.
extern fn _ZSt9terminatev() callconv(.c) noreturn;
extern fn _Unwind_Resume(*anyopaque) callconv(.c) noreturn;

export const R_zig_cxx_runtime = [_]*const anyopaque{ &_ZSt9terminatev, &_Unwind_Resume };

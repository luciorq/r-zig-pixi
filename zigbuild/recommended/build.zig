//! R's recommended packages (MASS, lattice, Matrix, ..., mgcv: 15 in R
//! 4.6.2), installed from the tarballs R's source carries
//! (src/library/Recommended/) by the R this build made, with its own
//! compilers, as R's `make recommended-packages` does it, which the R
//! build leaves out (--without-recommended-packages; build.zig builds the
//! base packages only). Its own build root, as the toolchain build's is:
//!   zig build --build-file zigbuild/recommended/build.zig \
//!     -Dprefix=<tree> -Dr=<R tree> -Dsrc=<R source> [-Djobs=<n>]
//! installs each package into <tree>/lib/R/library/<pkg>/ (Windows:
//! <tree>/Library/lib/R/library/<pkg>/). scripts/zig-recommended.sh
//! (pixi run recommended) runs it with the compile tree's R (the built
//! tree plus the toolchain groups, scripts/compile-tree.sh) into a tree of
//! its own, dist/recommended/<flavor>/R-<ver>-zig: the R tree, the base,
//! is only read. The conda build (recipe/build.sh) runs it with R's own
//! tree, the env, as both: there the recipe's outputs divide the files
//! (r-zig-recommended). `test` runs order.zig's unit tests and installs
//! nothing.
//!
//! Why not a step of R's build.zig: this needs no R configure and none of
//! that build's options, and it runs R from another tree than the one
//! that build installs (the compile tree, which exists only after the
//! toolchain build). .github/devdocs/feat-recommended-packages/PLAN.md.
//!
//! Nothing about the packages is typed here (order.zig): their names are
//! share/make/vars.mk's R_PKGS_RECOMMENDED, the order and INSTALL_OPTS
//! are src/library/Recommended/Makefile.in's. Each package is one R CMD
//! INSTALL, a step that depends on the steps of the packages the makefile
//! installs first. The steps pass R's output through, so zig runs one at
//! a time (a Run step that inherits stdio holds zig's global lock); a
//! package's own files compile in parallel, -Djobs at a time (rzig build's
//! tier 1, and make for a package with makefile rules: Matrix).
const std = @import("std");
const mem = std.mem;
const order = @import("order.zig");

pub fn build(b: *std.Build) !void {
    const arena = b.allocator;
    const io = b.graph.io;

    const test_step = b.step("test", "Run order.zig's unit tests (the makefile readers)");
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("order.zig"),
        .target = b.graph.host,
    }) })).step);

    // zig 0.17's configure step does not see --prefix, and nothing here is
    // installed by zig's install step: R CMD INSTALL writes the tree.
    const prefix_opt = b.option([]const u8, "prefix", "The tree the packages are installed into (its lib/R/library; Windows: Library/lib/R/library)");
    const r_opt = b.option([]const u8, "r", "The tree whose R installs them, with its compilers (default: -Dprefix, the conda build)");
    const src_opt = b.option([]const u8, "src", "R's source directory (share/make/vars.mk, src/library/Recommended/)");
    const jobs = b.option(usize, "jobs", "Compile jobs of one package (default: the CPU count)") orelse
        (std.Thread.getCpuCount() catch 1);

    // The configure step reads R's source and makes the library
    // directory: nothing zig's configure cache can track.
    b.graph.poisonCache();
    const how = "pass -Dprefix=<tree> and -Dsrc=<R source> (scripts/zig-recommended.sh does)";
    const prefix = try mem.replaceOwned(u8, arena, prefix_opt orelse {
        b.getInstallStep().dependOn(&b.addFail(how).step);
        return;
    }, "\\", "/");
    const src = try mem.replaceOwned(u8, arena, src_opt orelse {
        b.getInstallStep().dependOn(&b.addFail(how).step);
        return;
    }, "\\", "/");
    const r_tree = try mem.replaceOwned(u8, arena, r_opt orelse prefix, "\\", "/");

    const windows = b.graph.host.result.os.tag == .windows;
    const rhome = if (windows) "Library/lib/R" else "lib/R";
    // R's front end: bin/R, on Windows bin/x64/R.exe (R_ARCH is x64 on
    // both Windows arches), both of which run `CMD INSTALL`.
    const r_exe = b.fmt("{s}/{s}/{s}", .{ r_tree, rhome, if (windows) "bin/x64/R.exe" else "bin/R" });
    if (!pathExists(io, r_exe))
        return fail("no R at {s}: -Dr names the tree whose R installs the packages (pixi run compile-tree makes the dev one)", .{r_exe});

    const rec = b.fmt("{s}/src/library/Recommended", .{src});
    const vars_mk = try readFile(b, io, b.fmt("{s}/share/make/vars.mk", .{src}));
    const makefile = try readFile(b, io, b.fmt("{s}/Makefile.in", .{rec}));
    const pkgs = try order.words(arena, vars_mk, "R_PKGS_RECOMMENDED") orelse
        return fail("{s}/share/make/vars.mk assigns no R_PKGS_RECOMMENDED", .{src});
    if (pkgs.len == 0) return fail("{s}/share/make/vars.mk: R_PKGS_RECOMMENDED is empty", .{src});
    const opts = try order.installOpts(arena, makefile) orelse
        return fail("{s}/Makefile.in assigns no INSTALL_OPTS", .{rec});
    const tarballs = try fileNames(b, io, rec);

    // R CMD INSTALL wants the library to exist. An absolute path: R's
    // front end changes directory, and R records nothing of it in a
    // package (verify-recommended.sh looks).
    const lib_rel = b.fmt("{s}/{s}/library", .{ prefix, rhome });
    std.Io.Dir.cwd().createDirPath(io, lib_rel) catch |err|
        return fail("cannot make {s} ({t})", .{ lib_rel, err });
    const lib = try realPath(b, io, lib_rel);
    // A file name that does not exist, for the variables that name a
    // user's file: set to it, R reads none. (Unix R takes an empty value
    // the same way, bin/R's --vanilla; Windows cannot hold one.)
    const no_file = b.fmt("{s}/.no-user-file", .{lib});

    const all = b.getInstallStep();
    var steps: std.StringArrayHashMapUnmanaged(*std.Build.Step.Run) = .empty;
    for (pkgs) |pkg| {
        const found = order.tarball(tarballs, pkg) catch
            return fail("{s} has two tarballs of {s}", .{ rec, pkg });
        const tgz = found orelse
            return fail("{s} has no {s}_<version>.tar.gz, though vars.mk's R_PKGS_RECOMMENDED names it", .{ rec, pkg });
        const run = b.addSystemCommand(&.{ r_exe, "CMD", "INSTALL" });
        run.setName(b.fmt("R CMD INSTALL {s}", .{tgz}));
        run.addArgs(opts);
        // the makefile rule's own words: --byte-compile (every config of
        // this build byte-compiles packages) and the library
        run.addArgs(&.{ "--byte-compile", "-l", lib, try realPath(b, io, b.fmt("{s}/{s}", .{ rec, tgz })) });
        // The rule's environment: no user or site library, and no check
        // that the package's dependencies are installed (the order here
        // is the makefile's).
        run.removeEnvironmentVariable("R_LIBS");
        run.setEnvironmentVariable("R_LIBS_USER", "NULL");
        run.setEnvironmentVariable("R_LIBS_SITE", "NULL");
        run.setEnvironmentVariable("_R_CHECK_INSTALL_DEPENDS_", "no");
        // `R --vanilla` there; here also no user Makevars, whose flags
        // would reach files that ship.
        run.setEnvironmentVariable("R_ENVIRON_USER", no_file);
        run.setEnvironmentVariable("R_PROFILE_USER", no_file);
        run.setEnvironmentVariable("R_MAKEVARS_USER", no_file);
        // rzig adds the include/, lib/ and an rpath of R_ZIG_EXTRA_ENV,
        // the pixi env in dev runs (pixi.toml): not for files that ship.
        // The packages need R's own headers and libraries only.
        run.removeEnvironmentVariable("R_ZIG_EXTRA_ENV");
        // rzig build reads -j from MAKEFLAGS (R_ZIG_JOBS comes first), and
        // make runs Matrix's sub-makes with it.
        run.removeEnvironmentVariable("R_ZIG_JOBS");
        run.setEnvironmentVariable("MAKEFLAGS", b.fmt("-j{d}", .{jobs}));
        run.stdio = .inherit;
        all.dependOn(&run.step);
        try steps.put(arena, pkg, run);
    }
    for (pkgs) |pkg| {
        for (try order.deps(arena, makefile, pkg)) |dep| {
            const first = steps.get(dep) orelse
                return fail("{s}/Makefile.in installs {s} after {s}, which vars.mk's R_PKGS_RECOMMENDED does not name", .{ rec, pkg, dep });
            steps.get(pkg).?.step.dependOn(&first.step);
        }
    }
}

/// Prints a configure error of this build and returns the error that
/// stops it.
fn fail(comptime fmt: []const u8, args: anytype) error{RecommendedBuild} {
    std.debug.print("error: " ++ fmt ++ "\n", args);
    return error.RecommendedBuild;
}

fn readFile(b: *std.Build, io: std.Io, p: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, p, b.allocator, .limited(16 * 1024 * 1024)) catch |err|
        return fail("cannot read {s} ({t}): -Dsrc names R's source directory", .{ p, err });
}

/// The names of a directory's entries.
fn fileNames(b: *std.Build, io: std.Io, p: []const u8) ![]const []const u8 {
    var dir = std.Io.Dir.cwd().openDir(io, p, .{ .iterate = true }) catch |err|
        return fail("cannot read {s} ({t}): -Dsrc names R's source directory", .{ p, err });
    defer dir.close(io);
    var names: std.ArrayList([]const u8) = .empty;
    var it = dir.iterate();
    while (try it.next(io)) |e| try names.append(b.allocator, try b.allocator.dupe(u8, e.name));
    return names.toOwnedSlice(b.allocator);
}

/// A path that exists, absolute, with `/`.
fn realPath(b: *std.Build, io: std.Io, p: []const u8) ![]const u8 {
    const real = std.Io.Dir.cwd().realPathFileAlloc(io, p, b.allocator) catch |err|
        return fail("cannot resolve {s} ({t})", .{ p, err });
    return mem.replaceOwned(u8, b.allocator, real, "\\", "/");
}

fn pathExists(io: std.Io, p: []const u8) bool {
    std.Io.Dir.cwd().access(io, p, .{}) catch return false;
    return true;
}

//! macOS: what the shims did to a compiler command line on Darwin.
const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Ctx = @import("Ctx.zig");
const cmdline = @import("cmdline.zig");
const rzig_target = @import("target.zig");
const Args = cmdline.Args;

/// The deployment target and the SDK's search directories.
pub const Target = struct {
    /// Before the caller's arguments: `-target`, and the SDK's frameworks.
    before: Args,
    /// Last on a link line: the SDK's usr/lib.
    link_last: Args,
    /// No SDK answered (no Command Line Tools): compiler.zig warns on a
    /// link (`no_sdk`).
    no_sdk: bool = false,
};

/// The same floor idea as linux's glibc pin, as a deployment target
/// (floors.macos, R's own; see build.zig). The OS word must be the literal
/// "native" plus MAJOR.MINOR: zig then treats the OS as non-native
/// (LC_BUILD_VERSION minos 13.0, and no implicit LC_RPATH per -L
/// directory) but still finds the installed SDK's headers and libSystem.
/// "<arch>-macos.13.0" would lose the SDK's usr/include (net/if_media.h,
/// which ps needs), and "<arch>-native.13" is rejected. Two SDK search dirs
/// that the non-native link leaves out come back by hand:
/// -F<sdk>/System/Library/Frameworks (-framework X at link) and
/// -L<sdk>/usr/lib (SDK-only libs: -lz -liconv -lcurl -lresolv), the latter
/// LAST on link lines only, so a -lz whose headers came from a -L directory
/// the caller passed binds that library, not the SDK's .tbd.
/// -mmacosx-version-min and MACOSX_DEPLOYMENT_TARGET are ignored by zig.
/// The arch is R's, rzig's own (target.zig), not the machine's: under
/// Rosetta an x86_64 rzig compiles for x86_64, as `uname -m` said there.
pub fn target(ctx: *Ctx) !Target {
    const triple = rzig_target.zig(.macos, ctx.arch).?;
    const found = sdkPath(ctx);
    const sdk = switch (found) {
        .path => |p| p,
        .none, .not_run => return .{ .before = try ctx.arena.dupe([]const u8, &.{ "-target", triple }), .link_last = &.{}, .no_sdk = found == .none },
    };
    return .{
        .before = try ctx.arena.dupe([]const u8, &.{ "-target", triple, try ctx.fmt("-F{s}/System/Library/Frameworks", .{sdk}) }),
        .link_last = try ctx.arena.dupe([]const u8, &.{try ctx.fmt("-L{s}/usr/lib", .{sdk})}),
    };
}

/// The installed SDK, asked the way zig itself asks
/// (std.zig.system.darwin.getSdk) and build.zig asks for R: `xcrun --sdk
/// macosx --show-sdk-path`. Whatever it prints, its exit status aside, as
/// the shim's `$(...)` took it; `none` when it ran and printed nothing
/// (no Command Line Tools: "xcrun: error: invalid active developer path"
/// on stderr), `not_run` when it could not run (no /usr/bin/xcrun, which
/// every macOS has: a dry run on another OS, the unit tests' fixture).
fn sdkPath(ctx: *Ctx) union(enum) { path: []const u8, none, not_run } {
    const res = ctx.capture(&.{ ctx.xcrun, "--sdk", "macosx", "--show-sdk-path" });
    if (res.stdout.len > 0) return .{ .path = res.stdout };
    return if (res.not_run != null) .not_run else .none;
}

/// What a link says when xcrun named no SDK (backlog M-28): the Command
/// Line Tools are not installed, or DEVELOPER_DIR names a directory
/// without them (xcrun ran and named none; an xcrun that cannot run says
/// nothing: not macOS, `sdkPath`). zig then compiles and links
/// with its own macOS headers and libSystem stubs (checked on omicron
/// with zig 0.17.1, DEVELOPER_DIR at an empty directory: a plain C
/// program builds and runs), so the build goes on; what only the SDK
/// has fails later, and this line says why first: an SDK library
/// (-lz, -liconv, -lcurl, -lresolv) or a framework. Links only, where
/// those are needed: one line per package link, not one per object.
pub const no_sdk =
    "warning: no macOS SDK (`xcrun --sdk macosx --show-sdk-path` named none): " ++
    "linking with zig's own macOS headers and libSystem only; an SDK library " ++
    "(-lz, -liconv, -lcurl) or a -framework will not be found. " ++
    "Install the Command Line Tools: xcode-select --install";

/// dyld (macOS 12+) refuses a Mach-O that names the same library twice
/// ("duplicate linked dylib"), and R makes that easy: R CMD SHLIB appends
/// $(FLIBS) to every link with Fortran sources, and CRAN's recipe for
/// Fortran packages using BLAS is `PKG_LIBS = $(BLAS_LIBS) $(FLIBS)`
/// (quadprog, 2026-09-24). Same class as data.table's own -lomp on top of
/// R's (compiler.zig's OpenMP). Keep the first of each -l<name>: dylib
/// order is irrelevant and a repeated archive resolves nothing new on a
/// Mach-O link, so this is safe for both kinds.
pub fn dedupLibs(ctx: *Ctx, args: Args) !Args {
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    var out: std.ArrayList([]const u8) = .empty;
    for (args) |x| {
        if (cmdline.flagValue(x, "-l") != null) {
            if (seen.contains(x)) continue;
            try seen.put(ctx.arena, x, {});
        }
        try out.append(ctx.arena, x);
    }
    return out.items;
}

// ---------------------------------------------------------------------------

const testing = std.testing;
const testutil = @import("testutil.zig");
const expectArgs = testutil.expectArgs;

test "-l deduplicated by the whole argument, first kept; -L and files untouched" {
    var f: testutil.Fixture = undefined;
    try f.init(.macos);
    defer f.deinit();
    try expectArgs(
        &.{ "-L/a", "-lRlapack", "-lRblas", "/x/libflang_rt.runtime.a", "-lm", "-L/a", "-l", "m", "/x/libflang_rt.runtime.a" },
        try dedupLibs(&f.ctx, &.{ "-L/a", "-lRlapack", "-lRblas", "/x/libflang_rt.runtime.a", "-lm", "-L/a", "-lRblas", "-l", "m", "-lm", "/x/libflang_rt.runtime.a" }),
    );
}

test "target: native.13.0, SDK frameworks before, SDK usr/lib for links" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // shell-script stand-in for xcrun
    var f: testutil.Fixture = undefined;
    try f.init(.macos);
    defer f.deinit();
    const ctx = &f.ctx;
    const triple = @tagName(builtin.cpu.arch) ++ "-native.13.0";
    ctx.xcrun = f.path("nowhere/xcrun");
    var t = try target(ctx);
    try expectArgs(&.{ "-target", triple }, t.before);
    try expectArgs(&.{}, t.link_last);
    // no xcrun at all (not macOS): no SDK, nothing to say about it
    try testing.expect(!t.no_sdk);

    try f.write("bin/xcrun", "#!/bin/sh\n[ \"$*\" = '--sdk macosx --show-sdk-path' ] && echo /SDKs/MacOSX.sdk; echo; echo; exit 1\n", .fromMode(0o755));
    ctx.xcrun = f.path("bin/xcrun");
    t = try target(ctx);
    try expectArgs(&.{ "-target", triple, "-F/SDKs/MacOSX.sdk/System/Library/Frameworks" }, t.before);
    try expectArgs(&.{"-L/SDKs/MacOSX.sdk/usr/lib"}, t.link_last);
    try testing.expect(!t.no_sdk);
    // an xcrun that fails and prints nothing on stdout, as without the
    // Command Line Tools ("xcrun: error: invalid active developer path")
    try f.write("bin/xcrun", "#!/bin/sh\necho 'xcrun: error: invalid active developer path' >&2; exit 1\n", .fromMode(0o755));
    t = try target(ctx);
    try expectArgs(&.{ "-target", triple }, t.before);
    try testing.expect(t.no_sdk);
}

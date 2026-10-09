const std = @import("std");

/// Standalone `zig build` in this directory does nothing; R drives rbuild.
pub fn build(b: *std.Build) void {
    _ = b;
}

/// Called by r-zig's tier-2 root with the helper as `rpkg`.
pub fn rbuild(comptime rpkg: type, b: *std.Build, opts: rpkg.Options) std.Build.LazyPath {
    return rpkg.addLibrary(b, opts, .{ .root_source_file = b.path("hello.zig") });
}

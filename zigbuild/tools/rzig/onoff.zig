//! The one rule for every on/off switch in the environment, R_ZIG_* and
//! RZIG_* alike (b14-review B17, the user's menu 5, 2026-11-26): on when
//! the value is 1, true or yes, in any case; off when it is unset, empty,
//! 0, false or no; any other value is off, and its reader warns, naming
//! the variable (`message`). R's tools:::.rzig_on (patch 0009) and
//! scripts/verify-helpers.sh's `switch_on` (smoke-test.sh's
//! RZIG_SMOKE_CRAN) read the same way.
//!
//! Readers: rzig (Ctx.on: RZIG_TRACE, RZIG_PRINT_ARGV, RZIG_KEEP_ROOT,
//! R_ZIG_SYSTEM_LIBS, R_ZIG_NO_PREFLIGHT, R_ZIG_CONFIGURE), build.zig and
//! zigbuild/tools/bootgate.zig (R_ZIG_BOOTGATE_LIST). Variables with
//! values of their own (R_ZIG_ENV_RPATH: 0 or origin; R_ZIG_PKG_BUILDER;
//! the paths) do not use it.
const std = @import("std");

pub const State = enum { on, off, other };

/// The state of a switch whose value is `value` (null: unset).
pub fn parse(value: ?[]const u8) State {
    const v = value orelse return .off;
    for ([_][]const u8{ "1", "true", "yes" }) |w| if (std.ascii.eqlIgnoreCase(v, w)) return .on;
    for ([_][]const u8{ "", "0", "false", "no" }) |w| if (std.ascii.eqlIgnoreCase(v, w)) return .off;
    return .other;
}

/// The warning for a value that is neither on nor off; its arguments are
/// the variable's name and its value.
pub const message = "{s}='{s}' is neither on (1, true, yes) nor off (0, false, no, empty): taken as off";

test parse {
    for ([_][]const u8{ "1", "true", "TRUE", "True", "yes", "YES" }) |v| try std.testing.expectEqual(State.on, parse(v));
    for ([_]?[]const u8{ null, "", "0", "false", "FALSE", "no", "No" }) |v| try std.testing.expectEqual(State.off, parse(v));
    for ([_][]const u8{ "maybe", "2", "on", "y", " 1", "1 " }) |v| try std.testing.expectEqual(State.other, parse(v));
}

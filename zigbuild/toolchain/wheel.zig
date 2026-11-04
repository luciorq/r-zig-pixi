//! The toolchain build's reader of PyPI's ziglang wheel (feat-standalone-
//! toolchain B4, phase 5): what the compilers group's zig/ installs and
//! the SOURCES block that says so, as conda.zig is the conda-meta records'.
//! scripts/fetch-zig.sh downloads the wheel it pins, checks its sha256 and
//! unpacks it; its `.complete` marker holds what the wheel's own files
//! cannot say, where it came from. The wheel's METADATA gives the version,
//! licence and source repository, and its RECORD every file with the
//! wheel's sha256 of it, the counterpart of conda-meta's paths_data
//! (PHASE5 open points A, B). No I/O here: build.zig beside this file reads
//! the files and installs, and `zig build --build-file
//! zigbuild/toolchain/build.zig test` (pixi run toolchain-test) runs the
//! tests below on fixture text.
const std = @import("std");
const mem = std.mem;
const conda = @import("conda.zig");

/// fetch-zig.sh's `.complete`: the wheel's URL and sha256, and the
/// source its zig is built from, ziglang.org's release tarball, as
/// SOURCES' `source:` line has it (conda.zig writeUpstream).
pub const Marker = struct {
    url: []const u8,
    sha256: []const u8,
    source: conda.Source,
};

/// The wheel's METADATA fields SOURCES needs.
pub const Metadata = struct {
    version: []const u8,
    /// `License-Expression:`, the licence of zig itself; the bundled
    /// components' are in the wheel's dist-info/licenses (LICENSES/).
    license: []const u8,
    /// `Project-URL: Source Code, <url>`: the repository that makes the
    /// wheels (zig-pypi), SOURCES' `feedstock:` line.
    source_code: []const u8,
};

/// One file zig/ installs: its path in the wheel, its path in zig/ and
/// the wheel's sha256 of it (RECORD's), as 64 lowercase hex characters.
pub const Entry = struct {
    from: []const u8,
    to: []const u8,
    sha256: []const u8,
};

pub const Error = error{
    /// A field the text must have is not there (`missing` names it).
    MissingField,
    /// A `source:` line with no URL.
    BadSource,
    /// Not `<name>-<version>-<python>-<abi>-<platform>.whl`.
    BadWheelName,
    /// A RECORD line in CSV quotes (a path with a comma), or without its
    /// three fields.
    BadRecordLine,
    /// A RECORD entry with no `sha256=` hash.
    NoSha256,
    /// A hash that is not 32 bytes of urlsafe base64.
    BadHash,
    /// RECORD lists no zig binary.
    NoBinary,
};

/// The value of the header `key: value` in `text`, up to the first blank
/// line (METADATA's body, the README, follows it and is never read), each
/// line without a trailing `\r`. With `prefix`, the first such header
/// whose value starts with it, the rest of that value.
fn header(text: []const u8, key: []const u8, prefix: []const u8) ?[]const u8 {
    var lines = mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const l = mem.trimEnd(u8, raw, "\r");
        if (l.len == 0) break;
        if (l.len < key.len + 1 or !mem.startsWith(u8, l, key) or l[key.len] != ':') continue;
        const v = mem.trim(u8, l[key.len + 1 ..], " \t");
        if (mem.startsWith(u8, v, prefix)) return mem.trim(u8, v[prefix.len..], " \t");
    }
    return null;
}

fn need(text: []const u8, key: []const u8, prefix: []const u8, missing: *[]const u8) Error![]const u8 {
    return header(text, key, prefix) orelse {
        missing.* = key;
        return error.MissingField;
    };
}

/// The marker fetch-zig.sh writes:
///   url: <the wheel's URL>
///   sha256: <its sha256>
///   source: <URL> sha256:<hex>
/// A missing line is error.MissingField, with `missing` set to its key.
pub fn parseMarker(text: []const u8, missing: *[]const u8) Error!Marker {
    const url = try need(text, "url", "", missing);
    const sha256 = try need(text, "sha256", "", missing);
    var it = mem.tokenizeAny(u8, try need(text, "source", "", missing), " \t");
    var s: conda.Source = .{ .url = it.next() orelse return error.BadSource };
    while (it.next()) |t| {
        if (mem.startsWith(u8, t, "sha256:")) s.sha256 = t["sha256:".len..];
        if (mem.startsWith(u8, t, "md5:")) s.md5 = t["md5:".len..];
    }
    return .{ .url = url, .sha256 = sha256, .source = s };
}

/// METADATA's Version, License-Expression and Source Code URL (one of its
/// three Project-URL headers, with Homepage and Bug Tracker).
pub fn parseMetadata(text: []const u8, missing: *[]const u8) Error!Metadata {
    return .{
        .version = try need(text, "Version", "", missing),
        .license = try need(text, "License-Expression", "", missing),
        .source_code = try need(text, "Project-URL", "Source Code,", missing),
    };
}

/// The wheel's tag from its file name (`ziglang-0.16.0-<tag>.whl`, the tag
/// `<python>-<abi>-<platform>`), for SOURCES' `build:` line.
pub fn tag(file_name: []const u8) Error![]const u8 {
    if (!mem.endsWith(u8, file_name, ".whl")) return error.BadWheelName;
    const stem = file_name[0 .. file_name.len - ".whl".len];
    var i = stem.len;
    for (0..3) |_| i = mem.lastIndexOfScalar(u8, stem[0..i], '-') orelse return error.BadWheelName;
    if (i == 0) return error.BadWheelName;
    return stem[i + 1 ..];
}

/// RECORD's entries for the files zig/ installs: `ziglang/<exe_name>` (zig,
/// zig.exe) and `ziglang/lib/...`, each `to` its path in zig/. Every other
/// line is left out: ziglang/'s Python files, README.md and LICENSE (the
/// licences are in LICENSES/, B4) and the dist-info's. RECORD is CSV,
/// `<path>,sha256=<urlsafe base64, no padding>,<size>`; its hash is
/// written as hex, as conda's paths_data has it. `arena` owns the result.
pub fn parseRecord(arena: mem.Allocator, text: []const u8, exe_name: []const u8) (Error || mem.Allocator.Error)![]const Entry {
    var out: std.ArrayList(Entry) = .empty;
    var binary = false;
    var lines = mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const l = mem.trimEnd(u8, raw, "\r");
        if (l.len == 0) continue;
        if (l[0] == '"') return error.BadRecordLine;
        var fields = mem.splitScalar(u8, l, ',');
        const path = fields.first();
        const hash = fields.next() orelse return error.BadRecordLine;
        _ = fields.next() orelse return error.BadRecordLine;
        if (fields.next() != null) return error.BadRecordLine;
        const rel = if (mem.startsWith(u8, path, "ziglang/")) path["ziglang/".len..] else continue;
        const is_binary = mem.eql(u8, rel, exe_name);
        if (!is_binary and !mem.startsWith(u8, rel, "lib/")) continue;
        if (!mem.startsWith(u8, hash, "sha256=")) return error.NoSha256;
        const b64 = hash["sha256=".len..];
        const dec = std.base64.url_safe_no_pad.Decoder;
        const n = dec.calcSizeForSlice(b64) catch return error.BadHash;
        if (n != 32) return error.BadHash;
        var digest: [32]u8 = undefined;
        dec.decode(&digest, b64) catch return error.BadHash;
        const hex = std.fmt.bytesToHex(digest, .lower);
        try out.append(arena, .{ .from = path, .to = rel, .sha256 = try arena.dupe(u8, &hex) });
        binary = binary or is_binary;
    }
    if (!binary) return error.NoBinary;
    return out.items;
}

// --- tests: fixture text, as the 0.16.0 wheels have it (trimmed) -------

const marker_text =
    "url: https://files.pythonhosted.org/packages/3e/ed/7b79/ziglang-0.16.0-py3-none-manylinux_2_12_x86_64.manylinux2010_x86_64.musllinux_1_1_x86_64.whl\n" ++
    "sha256: 9fcda73f62b851dd72a54b710ad40a209896db14cfb13649e62191243556342b\n" ++
    "source: https://ziglang.org/download/0.16.0/zig-0.16.0.tar.xz sha256:43186959edc87d5c7a1be7b7d2a25efffd22ce5807c7af99067f86f99641bfdf\n";

test "marker: the wheel's URL and sha256, the source as SOURCES writes it" {
    var missing: []const u8 = "";
    const m = try parseMarker(marker_text, &missing);
    try std.testing.expect(mem.endsWith(u8, m.url, "/7b79/ziglang-0.16.0-py3-none-manylinux_2_12_x86_64.manylinux2010_x86_64.musllinux_1_1_x86_64.whl"));
    try std.testing.expectEqualStrings("9fcda73f62b851dd72a54b710ad40a209896db14cfb13649e62191243556342b", m.sha256);
    try std.testing.expectEqualStrings("https://ziglang.org/download/0.16.0/zig-0.16.0.tar.xz", m.source.url);
    try std.testing.expectEqualStrings("43186959edc87d5c7a1be7b7d2a25efffd22ce5807c7af99067f86f99641bfdf", m.source.sha256);

    // written back by SOURCES' one writer as it was read
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    const r: conda.Record = .{ .name = "ziglang", .version = "0.16.0", .build = "t", .upstream = .{ .sources = &.{m.source}, .feedstock = "https://github.com/ziglang/zig-pypi" } };
    try conda.writeSources(std.testing.allocator, &aw.writer, &.{.{ .record = &r, .from = "ziglang/zig", .to = "zig", .sha256 = "ab" }});
    try std.testing.expect(mem.indexOf(u8, aw.written(), marker_text[mem.indexOf(u8, marker_text, "source: ").?..]) != null);
    try std.testing.expect(mem.indexOf(u8, aw.written(), "feedstock: https://github.com/ziglang/zig-pypi\n") != null);
}

test "marker: CRLF line ends, and each missing line named" {
    var missing: []const u8 = "";
    const crlf = try std.mem.replaceOwned(u8, std.testing.allocator, marker_text, "\n", "\r\n");
    defer std.testing.allocator.free(crlf);
    const m = try parseMarker(crlf, &missing);
    try std.testing.expectEqualStrings("9fcda73f62b851dd72a54b710ad40a209896db14cfb13649e62191243556342b", m.sha256);
    try std.testing.expectEqualStrings("43186959edc87d5c7a1be7b7d2a25efffd22ce5807c7af99067f86f99641bfdf", m.source.sha256);
    // the old fetch-zig's marker, empty
    try std.testing.expectError(error.MissingField, parseMarker("", &missing));
    try std.testing.expectEqualStrings("url", missing);
    try std.testing.expectError(error.MissingField, parseMarker("url: u\nsource: s sha256:1\n", &missing));
    try std.testing.expectEqualStrings("sha256", missing);
    try std.testing.expectError(error.MissingField, parseMarker("url: u\nsha256: 1\n", &missing));
    try std.testing.expectEqualStrings("source", missing);
    try std.testing.expectError(error.BadSource, parseMarker("url: u\nsha256: 1\nsource: \n", &missing));
}

const metadata_text =
    \\Metadata-Version: 2.4
    \\Name: ziglang
    \\Version: 0.16.0
    \\Summary: Zig is a general-purpose programming language and toolchain for maintaining robust, optimal, and reusable software.
    \\License-Expression: MIT
    \\License-File: ziglang/LICENSE
    \\Project-URL: Homepage, https://ziglang.org
    \\Project-URL: Source Code, https://github.com/ziglang/zig-pypi
    \\Project-URL: Bug Tracker, https://github.com/ziglang/zig-pypi/issues
    \\Requires-Python: ~=3.5
    \\
    \\Zig PyPI distribution
    \\Version: 9.9
    \\License-Expression: none
    \\
;

test "METADATA: the headers only, the Source Code URL among three" {
    var missing: []const u8 = "";
    const m = try parseMetadata(metadata_text, &missing);
    try std.testing.expectEqualStrings("0.16.0", m.version);
    try std.testing.expectEqualStrings("MIT", m.license);
    try std.testing.expectEqualStrings("https://github.com/ziglang/zig-pypi", m.source_code);
    // CRLF
    const crlf = try std.mem.replaceOwned(u8, std.testing.allocator, metadata_text, "\n", "\r\n");
    defer std.testing.allocator.free(crlf);
    try std.testing.expectEqualStrings("MIT", (try parseMetadata(crlf, &missing)).license);
    // a field only in the body is missing
    try std.testing.expectError(error.MissingField, parseMetadata("Name: ziglang\nVersion: 0.16.0\n\nLicense-Expression: MIT\n", &missing));
    try std.testing.expectEqualStrings("License-Expression", missing);
    try std.testing.expectError(error.MissingField, parseMetadata("Version: 1\nLicense-Expression: MIT\nProject-URL: Homepage, https://ziglang.org\n", &missing));
    try std.testing.expectEqualStrings("Project-URL", missing);
}

test "tag: the five pinned wheels' file names" {
    const names = [_][2][]const u8{
        .{ "ziglang-0.16.0-py3-none-manylinux_2_12_x86_64.manylinux2010_x86_64.musllinux_1_1_x86_64.whl", "py3-none-manylinux_2_12_x86_64.manylinux2010_x86_64.musllinux_1_1_x86_64" },
        .{ "ziglang-0.16.0-py3-none-manylinux_2_17_aarch64.manylinux2014_aarch64.musllinux_1_1_aarch64.whl", "py3-none-manylinux_2_17_aarch64.manylinux2014_aarch64.musllinux_1_1_aarch64" },
        .{ "ziglang-0.16.0-py3-none-macosx_12_0_arm64.whl", "py3-none-macosx_12_0_arm64" },
        .{ "ziglang-0.16.0-py3-none-macosx_12_0_x86_64.whl", "py3-none-macosx_12_0_x86_64" },
        .{ "ziglang-0.16.0-py3-none-win_amd64.whl", "py3-none-win_amd64" },
    };
    for (names) |n| try std.testing.expectEqualStrings(n[1], try tag(n[0]));
    try std.testing.expectError(error.BadWheelName, tag("ziglang-0.16.0.tar.gz"));
    try std.testing.expectError(error.BadWheelName, tag("py3-none-any.whl"));
}

const record_text =
    \\ziglang/__init__.py,sha256=47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU,0
    \\ziglang/LICENSE,sha256=XFN9aFPgBSmKKF1QjP-axxks6iNXbIQNSFsrWGp_8Xc,1080
    \\ziglang/README.md,sha256=c21wxTen2l4QYLl_6asJ4n8iHvuuPvs9-p8AoAGejFw,31422
    \\ziglang/lib/build-web/fuzz.zig,sha256=qaR2E8eWJYIb9PcOe7d2VGhEN4S_P_nDefFdw07wq-U,15947
    \\ziglang/lib/build-web/index.html,sha256=GX_nNqQivFjnIQZRpSAe8FNMQSbzv4iumrIoyDIT0KY,12166
    \\ziglang/zig,sha256=Ixe7uReYVW2dDziqvawj24Pwl5sl92clmuR0VGckCHw,172641672
    \\ziglang/__main__.py,sha256=EQUYRKxWS_BtcerhIN0g9_i4h6nxAJyCpkPWhJi7Lig,300
    \\ziglang-0.16.0.dist-info/licenses/ziglang/LICENSE,sha256=XFN9aFPgBSmKKF1QjP-axxks6iNXbIQNSFsrWGp_8Xc,1080
    \\ziglang-0.16.0.dist-info/METADATA,sha256=UkYALfYkLe554_OgobLuikirli48AFBA5VbovoTzfJE,3185
    \\ziglang-0.16.0.dist-info/WHEEL,sha256=f7Tpa5AgExgUxvCyJhqz3YdqQ-R_Adz_rkcE37BdLyg,183
    \\ziglang-0.16.0.dist-info/RECORD,,
    \\
;

test "RECORD: zig and lib/, the hashes in hex, the rest left out" {
    var a = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer a.deinit();
    const es = try parseRecord(a.allocator(), record_text, "zig");
    try std.testing.expectEqual(@as(usize, 3), es.len);
    try std.testing.expectEqualStrings("ziglang/lib/build-web/fuzz.zig", es[0].from);
    try std.testing.expectEqualStrings("lib/build-web/fuzz.zig", es[0].to);
    try std.testing.expectEqualStrings("ziglang/zig", es[2].from);
    try std.testing.expectEqualStrings("zig", es[2].to);
    try std.testing.expectEqual(@as(usize, 64), es[2].sha256.len);
    // the empty file's (ziglang/__init__.py's line), decoded
    const empty = try parseRecord(a.allocator(), "ziglang/zig,sha256=47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU,0\n", "zig");
    try std.testing.expectEqualStrings("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", empty[0].sha256);
    // CRLF
    const crlf = try std.mem.replaceOwned(u8, a.allocator(), record_text, "\n", "\r\n");
    try std.testing.expectEqual(@as(usize, 3), (try parseRecord(a.allocator(), crlf, "zig")).len);
}

test "RECORD: Windows' zig.exe; a quoted line, a missing hash, a short one, no binary" {
    var a = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const win =
        \\ziglang/zig.exe,sha256=47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU,0
        \\ziglang/lib/std/std.zig,sha256=47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU,0
    ;
    const es = try parseRecord(arena, win, "zig.exe");
    try std.testing.expectEqual(@as(usize, 2), es.len);
    try std.testing.expectEqualStrings("zig.exe", es[0].to);
    try std.testing.expectError(error.NoBinary, parseRecord(arena, win, "zig"));
    try std.testing.expectError(error.BadRecordLine, parseRecord(arena, "\"ziglang/lib/a,b.h\",sha256=47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU,0\n", "zig"));
    try std.testing.expectError(error.BadRecordLine, parseRecord(arena, "ziglang/lib/a.h,sha256=47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU\n", "zig"));
    try std.testing.expectError(error.NoSha256, parseRecord(arena, "ziglang/zig,,0\n", "zig"));
    try std.testing.expectError(error.NoSha256, parseRecord(arena, "ziglang/zig,md5=1B2M2Y8AsgTpgAmY7PhCfg,0\n", "zig"));
    try std.testing.expectError(error.BadHash, parseRecord(arena, "ziglang/zig,sha256=1B2M2Y8AsgTpgAmY7PhCfg,0\n", "zig"));
    try std.testing.expectError(error.BadHash, parseRecord(arena, "ziglang/zig,sha256=47DEQpj8HBSa+/TImW-5JCeuQeRkm5NMpJWZG3hSuFU,0\n", "zig"));
}

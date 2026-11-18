# zig 0.17: `zig fetch` caches a copy that later builds reject

A known zig defect, found 2026-11-12 while adding the extras group
(feat-extras-group PLAN.md). The user decided on 2026-11-14 not to report
it upstream; this record tracks it, so it can be checked on each zig
update.

## The symptom

A toolchain build stops in the configure step with:

```
./build.zig.zon:13:21: error: hash mismatch: manifest declares N-V-__8AABi0WAs7k2I5pQzTK1Z_y5a872JVILowbBEZfEX0 but the fetched package has N-V-__8AABi0WAsUoRNVu-vukTaO5BZeCot7LCPzkiHI5F4S
```

The declared hash is correct. Kitware's sha256 matches, and a build that
downloads the archive itself computes the declared hash. The zig global
cache holds a bad copy of the archive.

## The cause

- `zig fetch <url>`, run on the command line outside a build, prints
  the correct hash. It also stores the archive at `p/<hash>.tar.gz` in
  zig's global cache. That stored copy keeps the archive's top directory
  (`cmake-4.4.4-linux-x86_64/...`). A build's own fetch strips that
  directory.
- When a later build finds `p/<hash>.tar.gz`, it unpacks that copy
  instead of downloading. The unpacked tree has one more directory
  level, so its hash differs and the build stops.
- A build unpacks every lazy dependency already in the global cache, not
  only the one it asks for. So one bad copy fails every build of that
  `build.zig.zon`:
  - a linux-x86_64 copy stops a linux-aarch64 build too;
  - it also stops the conda build's run (recipe/build.sh), which asks
    for no cmake at all.
- `zig fetch` also prints
  `warning(fetch): failed to delete temporary directory .../global/tmp/.tmp-...: DirNotEmpty`
  for each archive.

It affects every lazy dependency in `zigbuild/toolchain/build.zig.zon`:
the five cmake archives and Windows' pkgconf. The cairo entry in the
root `build.zig.zon` uses the same mechanism.

## The workaround

- Never run `zig fetch <url>` with the project's global cache. To get
  the hash of a new URL, use a scratch cache:
  `ZIG_GLOBAL_CACHE_DIR=$(mktemp -d) zig fetch <url>`.
- When the error appears, delete `p/<hash>.tar.gz` (the declared hash,
  not the "fetched" one) from zig's global cache
  (`zig env | grep global_cache_dir`). The next build downloads it again.
- CI is not affected: every job starts with an empty cache, and only
  build-driven fetches fill it.

## The repro (zig 0.17.0, linux-64)

Evidence: T/rel11/scratchc-extras/zig-fetch.log, lazy-unpack-probe.log
and review/probe/ (T = /data/gamma/luciorq/workspaces/temp/r-zig-pixi).

```sh
export ZIG_GLOBAL_CACHE_DIR=$(mktemp -d)
mkdir probe && cd probe
cat > build.zig <<'EOF'
const std = @import("std");
pub fn build(b: *std.Build) !void {
    _ = try b.dependencyLazy("c", .{});
}
EOF
cat > build.zig.zon <<'EOF'
.{
    .name = .probe,
    .version = "0.0.0",
    .fingerprint = 0xd75e6f2abe79b454,
    .dependencies = .{
        .c = .{
            .url = "https://github.com/Kitware/CMake/releases/download/v4.4.4/cmake-4.4.4-linux-aarch64.tar.gz",
            .hash = "N-V-__8AADO3OQcfVug-MBmDJ_Q0Btalp5RRalgl7R2t_ynt",
            .lazy = true,
        },
        .d = .{
            .url = "https://github.com/Kitware/CMake/releases/download/v4.4.4/cmake-4.4.4-linux-x86_64.tar.gz",
            .hash = "N-V-__8AABi0WAs7k2I5pQzTK1Z_y5a872JVILowbBEZfEX0",
            .lazy = true,
        },
    },
    .paths = .{""},
}
EOF
zig build            # exit 0: downloads only "c", the one asked for
rm -rf zig-pkg .zig-cache
zig fetch https://github.com/Kitware/CMake/releases/download/v4.4.4/cmake-4.4.4-linux-x86_64.tar.gz
                     # prints N-V-__8AABi0WAs7k2I5pQzTK1Z_y5a872JVILowbBEZfEX0 (correct)
zig build            # error: hash mismatch on "d", which the build never asks for
```

## Checking a new zig

Do this on each zig bump (conda-forge's zig and PyPI's ziglang;
memory "both zigs"):

1. Run the repro above with the new zig. The bug is fixed when the last
   `zig build` exits 0.
2. Also check whether a build still unpacks lazy dependencies it does
   not ask for: the first `zig build` with both entries already cached
   lists both under `zig-pkg/`.
3. If the bug is fixed, remove the workaround notes from
   feat-extras-group PLAN.md ("zig 0.17 notes") and set this record's
   status to fixed, naming the zig version.
4. Search zig's issue tracker (codeberg.org/ziglang/zig) for "zig fetch
   hash mismatch" or "global cache p/ tar.gz", and note any matching
   issue here.

## Status

| Date | zig | Result |
| --- | --- | --- |
| 2026-11-12 | 0.17.0 (conda-forge) | reproduced (above) |
| 2026-11-14 | 0.17.0 (conda-forge) | the repro above run as written: same error; deleting `p/<hash>.tar.gz` fixes the next build |
| 2026-11-15 | 0.17.1 (conda-forge, zig-0.17.1-89c0722_0) | the repro above run as written, with an empty scratch cache: the last `zig build` stops with the same hash mismatch (T/rel11-fix/zigfetch-probe/repro.log). The hashes of pkgconf 3.0.11 and cmake 4.5.0 (chore-release-11 finding 27) came from `zig fetch` with a scratch cache only. |

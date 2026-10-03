# Zig after 0.16: where `std.Io` is going, and what it means here

**Checked 2026-09-25**, comparing the 0.16.0 std this repo pins with
master `0.17.0-dev.2294+71403f299` (2026-09-24,
[codeberg.org/ziglang/zig](https://codeberg.org/ziglang/zig)).

**0.17.0 is not released.** Its milestone has 7 open and 311 closed
items; the 2026-05-26 devlog expected it "within a couple weeks". The
0.18.0 milestone is already open (LLVM 23, a distinct Zig libc ABI,
dropping wasi-libc). Master's `zig cc` is LLVM 22
(`CMakeLists.txt:136`); 0.16's is clang 21.1.8.

## The rework already shipped in 0.16

0.16.0 introduced `std.Io`: one interface (a vtable) passed explicitly
to everything that does I/O — files (`Io.Dir`, `Io.File`), processes
(`std.process.spawn(io, …)`), networking, timers, synchronization —
with interchangeable implementations. `pub fn main(init:
std.process.Init)` receives `init.io` along with `gpa`, `arena`,
`environ_map` and `preopens`. Master changes this incrementally.

## 0.16 → master

- **Network I/O becomes batchable operations.** 0.16 has vtable
  functions like `netRead: *const fn (?*anyopaque, src:
  net.Socket.Handle, data: [][]u8) net.Stream.Reader.Error!usize`;
  master turns them into `Io.Operation` variants (`net_send`,
  `net_read`, `net_write`) run through `operate`/`Batch`, as file
  streaming already was. The vtable went from 109 to 106 functions;
  open PR #36277 continues in the same direction.
- **File open options moved to `Dir`:** 0.16's
  `File.OpenFlags`/`File.CreateFlags` are master's
  `Dir.OpenFileOptions`/`Dir.CreateFileOptions`.
- **Smaller changes:** `file.reader(&buf)` → `file.reader(io, &buf)`;
  `process.getUserInfo(name)` → `getUserInfo(io, name)`;
  `SpawnOptions.disable_aslr` removed (PR #36838);
  `Condition.waitTimeout` and `futexWaitTimeout` added.
- **Std-wide renames:** `std.builtin` is an alias of `std.lang`; 0.16's
  `OptimizeMode = enum { Debug, ReleaseSafe, ReleaseFast, ReleaseSmall }`
  is master's `std.lang.Optimize = enum { debug, safe, fast, small }`;
  std's own code uses `@backingInt`/`@fromBackingInt` instead of
  `@intFromEnum`/`@enumFromInt`; `dupeZ` → `dupeSentinel`.
- **Unchanged:** the backends; the concurrency primitives (`async`,
  `concurrent`, `await`, `cancel`, `Group`, `Batch`); process spawning
  (`spawn`, `run`, `replace`, `SpawnOptions`); `Environ`, `Args`,
  `Preopens`; archives (tar extract and `Writer`, flate in both
  directions, zip extract-only).

## Backends

| Backend | What it is | State |
|---|---|---|
| `Threaded` | blocking system calls on a thread pool (`async_limit` = CPUs − 1) | default: what `main(init)` receives |
| `Evented` | fibers over io_uring (Linux), Grand Central Dispatch (macOS), kqueue (BSDs) | experimental: open bugs #36801, #36676, #36190 |
| `Threaded.global_single_threaded` | a global instance | "library code should accept an Io parameter rather than accessing this declaration"; no concurrency, and its allocator fails, so it cannot spawn |

**Process spawning forks in every backend:** `Threaded.zig:15245`
(`posix.system.fork()`), `Uring.zig:4413` (`linux.fork()`),
`Dispatch.zig:4257` (`c.fork()`). No `posix_spawn`, `vfork` or `clone`;
all allocation happens before the fork. Windows uses `CreateProcessW`
with command-line quoting and PATHEXT.

**Getting an `Io` from code that C calls** (libR, for example):
`var threaded: std.Io.Threaded = .init(gpa, .{ … }); defer
threaded.deinit(); const io = threaded.io();`. `init` installs
process-wide SIGIO and SIGPIPE handlers, restored only at `deinit`, and
starts worker threads. Both collide with a host that owns its signal
handling, as R does.

## Direction

- `Io` stays the universal interface. More operations become batchable,
  io_uring-shaped `Operation`s; the evented backends are being hardened;
  `Threaded` stays the default.
- zig's libc may later route C `read`/`write` through `std.Io` (devlog
  2026-01-31, described there as "vaporware").
- **The build system is split** (devlog 2026-05-26): `build.zig` runs in
  a "configurer" process that serializes a configuration, and a cached
  "maker" process executes it. Side effects at configure time poison the
  configuration cache (`findProgram` does); files read at configure time
  must be declared with `b.dependOnFileContents(lazy_path)`;
  `if (b.args) |a| run.addArgs(a)` becomes `run.addPassthruArgs()`.

## What it means for this repo

- **Phase B (Zig multi-call binary):** what it needs (spawn, `Io.Dir`,
  tar, flate) is the same in 0.16 and master; a later move to 0.17 is
  the small renames above. There is still no zip writer: build one on
  `flate.Compress`. Forking is fine for a small binary.
- **Phase S (libR's spawn primitive):** C with `posix_spawnp()` is
  confirmed. Every Zig backend forks, a `Threaded` `Io` takes over
  process-wide signal handlers, and the global instance cannot spawn.
- **The 0.16 pin:** stay on 0.16 until 0.17.0 is tagged, then port on
  one branch. What breaks:
  - `build.zig:2116`, `:2177`: `.ReleaseSafe`/`.ReleaseFast` become
    `.safe`/`.fast`.
  - `b.pathFromRoot` is gone on master: `build.zig:229`, `:824`,
    `:1710`, `:2521`, `:2526`, `:2568`, `:2591`, `:2592`.
  - The configure-time reads of `subst.txt`, `config.h` and
    `Makeconf.win` (`std.Io.Dir.cwd().readFileAlloc(io, …)` with `io =
    b.graph.io`, `build.zig:204`) still compile, but must be declared
    with `b.dependOnFileContents(b.path(…))` or the cached configuration
    goes stale (compare closed issue #36255).
  - Unchanged, so no work: `addWriteFiles`, `addCopyFile`,
    `addSystemCommand`, `addInstallFileWithDir`,
    `addInstallDirectory`, the module link/include/rpath APIs, Run's
    `setEnvironmentVariable`/`addArg`/`addFileArg`/`addOutputFileArg`/`setCwd`,
    `getEmittedBin`.
  - Version pins: `pixi.toml:85` and `:282`, `recipe/recipe.yaml:120`
    (build) and `:375` (run dependency for package compilation), and
    `ZIGLANG_REQUIREMENT` in `scripts/make-wheel.py:47`.
  - LLVM 21 → 22 changes `zig cc` for package compilation, so the
    contract suite gates the move.

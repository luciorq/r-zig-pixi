//! What `R CMD INSTALL` would run for one source package's `src/`, without
//! make: the tier the package falls in, and for tier 1 the plan the
//! zig build root (zigbuild/rpkg/build_t1.zig) executes. The plan is the
//! strings make would have put on each compile and link line, derived as
//! install.R's .shlib_internal derives them (its makefile order and its
//! command-line overrides), expanded by makefile.zig and word-split by
//! shellwords.zig. `rzig build --plan-only` prints it. The oracle is make
//! itself: scripts/pkg-parity.sh (pixi run pkg-parity) installs the same
//! packages through make and through this plan and asserts identical
//! compiler command lines and exports.
//!
//! Tiers: 0 no `src/` (R only); 2 `src/build.zig` and no src/Makefile*
//! (install.R runs a Makefile itself); 1 Makevars with assignments only;
//! 3 everything else (configure, src/Makefile, Objective C, rules,
//! conditionals, $(shell), a compiler that is not R's toolchain, a shell
//! metacharacter in a flag): error.NeedsMake with `reason`.
const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Io = std.Io;
const Ctx = @import("Ctx.zig");
const makefile = @import("makefile.zig");
const shellwords = @import("shellwords.zig");
const floors = @import("floors.zig");
const compiler = @import("compiler.zig");
const darwin = @import("darwin.zig");

pub const Tier = enum { r_only, makevars, zig, make };

pub const Classification = struct {
    tier: Tier,
    /// For `.make`: what sends the package there.
    reason: []const u8 = "",
    /// The Makevars file install.R would read (a file name in src/), if any.
    makevars: ?[]const u8 = null,
};

pub const Lang = enum { c, cxx, f, f9x };

pub const Source = struct {
    lang: []const u8,
    path: []const u8,
    obj: []const u8,
};

/// The plan as plan.zon carries it to the root. Field names and defaults
/// are the root's (zigbuild/rpkg/build_t1.zig, `Plan`): keep both in step.
pub const Plan = struct {
    name: []const u8,
    srcdir: []const u8,
    output: []const u8,
    libs_dir: []const u8 = "libs",
    toolchain: []const u8,
    rzig: []const u8 = "",
    link_driver: []const u8,
    cc_tool: []const u8 = "zig-cc",
    cxx_tool: []const u8 = "zig-cxx",
    fc_tool: []const u8 = "zig-fc",
    sources: []const Source,
    cc: []const []const u8 = &.{},
    cxx: []const []const u8 = &.{},
    fc: []const []const u8 = &.{},
    f9x: []const []const u8 = &.{},
    link: []const []const u8 = &.{},
    libs: []const []const u8 = &.{},
    env: []const []const u8 = &.{},
    target: []const u8 = "",
    r_include: []const u8 = "",
    def: bool = false,
    win_def: []const u8 = "",
};

pub const Options = struct {
    /// R_HOME, `/` separators.
    r_home: []const u8,
    /// The unpacked package (where DESCRIPTION is), absolute.
    pkg_dir: []const u8,
    /// Its src/ (install.R's multi-arch copies are src-<arch>); default
    /// <pkg_dir>/src.
    src_dir: ?[]const u8 = null,
    name: []const u8,
    /// Installed LinkingTo packages' directories: `-I'<dir>/include'` each,
    /// as install.R's CLINK_CPPFLAGS. null keeps the environment's value.
    linkingto: ?[]const []const u8 = null,
    /// SystemRequirements' C++ standard ("17"): install.R's R_PKG_CXX_STD.
    cxx_std: ?[]const u8 = null,
    /// SystemRequirements' C standard ("17", "23", "90", "99"): --use-Cnn.
    c_std: ?[]const u8 = null,
    /// DESCRIPTION's UseLTO or --use-LTO/--no-use-LTO; null = not given.
    use_lto: ?bool = null,
    /// Windows --debug.
    debug: bool = false,
    /// The site and user Makevars install.R would add, when they exist.
    makevars_site: ?[]const u8 = null,
    makevars_user: ?[]const u8 = null,
    /// The rzig binary the root runs for `rzig def` (Windows).
    rzig: []const u8 = "",
};

pub const Error = error{ NeedsMake, OutOfMemory };

pub const Planner = struct {
    ctx: *Ctx,
    /// Why the package needs make (error.NeedsMake).
    reason: []const u8 = "",

    fn needsMake(p: *Planner, comptime f: []const u8, args: anytype) Error {
        p.reason = p.ctx.fmt(f, args) catch "out of memory";
        return error.NeedsMake;
    }

    /// The source files install.R lists (`dir(pattern = ...)` of src/, dot
    /// files included), in byte order.
    pub fn listSources(p: *Planner, src_dir: []const u8) Error![]const []const u8 {
        const a = p.ctx.arena;
        var out: std.ArrayList([]const u8) = .empty;
        var d = Io.Dir.cwd().openDir(p.ctx.io, src_dir, .{ .iterate = true }) catch |err| return p.needsMake("cannot list {s}: {t}", .{ src_dir, err });
        defer d.close(p.ctx.io);
        var it = d.iterate();
        while (it.next(p.ctx.io) catch null) |entry| {
            if (entry.kind == .directory) continue;
            if (langOf(entry.name) != null or isObjC(entry.name)) try out.append(a, try a.dupe(u8, entry.name));
        }
        mem.sort([]const u8, out.items, {}, byteOrder);
        return out.items;
    }

    pub fn classify(p: *Planner, pkg_dir: []const u8, src_dir: []const u8) Error!Classification {
        const ctx = p.ctx;
        if (!ctx.isDir(src_dir)) return .{ .tier = .r_only };
        const windows = ctx.os == .windows;
        // install.R runs a src/Makefile (Windows: Makefile.ucrt, else
        // Makefile.win) with make itself, never run_shlib and its rzig
        // build hook, so a Makefile wins over src/build.zig [code-2].
        // build.zig wins over configure and the Makevars: install.R runs
        // configure, then run_shlib. A configure script stays the reason
        // given first, as before.
        const makefiles: []const []const u8 = if (windows) &.{ "Makefile.ucrt", "Makefile.win" } else &.{"Makefile"};
        const src_makefile: ?[]const u8 = for (makefiles) |m| {
            if (ctx.isFile(try ctx.fmt("{s}/{s}", .{ src_dir, m }))) break m;
        } else null;
        if (src_makefile == null and ctx.isFile(try ctx.fmt("{s}/build.zig", .{src_dir}))) return .{ .tier = .zig };
        const configures: []const []const u8 = if (windows) &.{ "configure.ucrt", "configure.win" } else &.{"configure"};
        for (configures) |c| if (ctx.isFile(try ctx.fmt("{s}/{s}", .{ pkg_dir, c }))) return .{ .tier = .make, .reason = try ctx.fmt("a {s} script", .{c}) };
        if (src_makefile) |m| return .{ .tier = .make, .reason = try ctx.fmt("src/{s}", .{m}) };
        for (try p.listSources(src_dir)) |s| if (isObjC(s)) return .{ .tier = .make, .reason = try ctx.fmt("an Objective-C source, src/{s}", .{s}) };
        const candidates: []const []const u8 = if (windows) &.{ "Makevars.ucrt", "Makevars.win", "Makevars" } else &.{"Makevars"};
        var makevars: ?[]const u8 = null;
        for (candidates) |m| if (ctx.isFile(try ctx.fmt("{s}/{s}", .{ src_dir, m }))) {
            makevars = m;
            break;
        };
        return .{ .tier = .makevars, .makevars = makevars };
    }

    /// The tier-1 plan, or error.NeedsMake with `reason`. `class` from
    /// `classify` (tier makevars or zig; for zig the compile flags and the
    /// link are what a package's C sources and library get).
    pub fn plan(p: *Planner, opts: Options, class: Classification) Error!Plan {
        const ctx = p.ctx;
        const a = ctx.arena;
        const windows = ctx.os == .windows;
        const src_dir = opts.src_dir orelse try ctx.fmt("{s}/src", .{opts.pkg_dir});
        const r_arch = ctx.getenv("R_ARCH") orelse if (windows) "/x64" else "";
        const etc = try ctx.fmt("{s}/etc{s}", .{ opts.r_home, r_arch });
        const makeconf_path = try ctx.fmt("{s}/Makeconf", .{etc});
        const makeconf_text = Io.Dir.cwd().readFileAlloc(ctx.io, makeconf_path, a, .limited(4 * 1024 * 1024)) catch |err|
            return p.needsMake("cannot read {s}: {t}", .{ makeconf_path, err });

        // install.R: SHLIB_EXT and SHLIB_LIBADD from the raw Makeconf (unix)
        const shlib_ext: []const u8 = if (windows) ".dll" else rawValue(makeconf_text, "SHLIB_EXT") orelse ".so";
        var shlib_libadd: std.ArrayList([]const u8) = .empty;
        if (!windows) if (rawValue(makeconf_text, "SHLIB_LIBADD")) |v| if (v.len > 0) try shlib_libadd.append(a, v);

        // the sources and the languages present (every source in src/, whether
        // or not OBJECTS names it: install.R looks at the files)
        const srcs = try p.listSources(src_dir);
        var with = std.EnumSet(Lang).initEmpty();
        for (srcs) |s| if (langOf(s)) |l| with.insert(l);

        // a variable set in MAKEFLAGS (`make LTO_OPT=-flto`, or MAKEFLAGS=
        // 'CFLAGS=-O0' in the environment) changes make's build and not
        // this plan: make it (install.packages' `k -j2 --jobserver-auth=`
        // are options, not assignments). Tier 1 only: a tier-2 package has
        // no make build to differ from, make cannot build build.zig
        // [preflight-PF-1]
        if (class.tier != .zig) if (ctx.getenv("MAKEFLAGS")) |mf| if (makeflagsAssignment(mf)) |v| return p.needsMake("MAKEFLAGS sets {s}", .{v});
        var e = makefile.Evaluator.init(a, ctx.io, src_dir);
        try e.importEnvironment(ctx.env);
        try e.setEnvironment("R_HOME", opts.r_home);
        try e.setEnvironment("R_ARCH", r_arch);
        try e.setEnvironment("R_INCLUDE_DIR", ctx.getenv("R_INCLUDE_DIR") orelse try ctx.fmt("{s}/include", .{opts.r_home}));
        try e.setEnvironment("R_SHARE_DIR", ctx.getenv("R_SHARE_DIR") orelse try ctx.fmt("{s}/share", .{opts.r_home}));
        try e.setEnvironment("R_DOC_DIR", ctx.getenv("R_DOC_DIR") orelse try ctx.fmt("{s}/doc", .{opts.r_home}));
        try e.setEnvironment("R_PACKAGE_NAME", opts.name);
        const clink: []const u8 = if (opts.linkingto) |dirs| blk: {
            var parts: std.ArrayList([]const u8) = .empty;
            for (dirs) |d| try parts.append(a, try ctx.fmt("-I'{s}/include'", .{d}));
            break :blk try mem.join(a, " ", parts.items);
        } else ctx.getenv("CLINK_CPPFLAGS") orelse "";
        try e.setEnvironment("CLINK_CPPFLAGS", clink);

        // the package's Makevars: read first, assignments only
        var makevars_text: []const u8 = "";
        if (class.makevars) |mv| {
            const mv_path = try ctx.fmt("{s}/{s}", .{ src_dir, mv });
            makevars_text = Io.Dir.cwd().readFileAlloc(ctx.io, mv_path, a, .limited(4 * 1024 * 1024)) catch |err|
                return p.needsMake("cannot read src/{s}: {t}", .{ mv, err });
        }
        const makevars_objects = class.makevars != null and lineStarting(makevars_text, "OBJECTS") != null;

        // install.R's command-line overrides, before the files (the
        // command line wins)
        const output = try ctx.fmt("{s}{s}", .{ opts.name, shlib_ext });
        try e.setCommandLine("SHLIB", output);
        if (!makevars_objects) {
            var objs: std.ArrayList([]const u8) = .empty;
            for (srcs) |s| try objs.append(a, try ctx.fmt("{s}.o", .{stem(s)}));
            try e.setCommandLine("OBJECTS", try mem.join(a, " ", objs.items));
        }
        // the C++ standard: Makevars' CXX_STD, else USE_CXXnn in the
        // environment, else SystemRequirements (R_PKG_CXX_STD)
        var use_cxxstd: ?[]const u8 = null;
        if (class.makevars != null) {
            if (cxxStdLine(makevars_text)) |val| {
                if (isCxxStandard(val)) {
                    use_cxxstd = val;
                    with.insert(.cxx);
                } else ctx.warn("src/{s}: Unknown C++ standard '{s}' was ignored", .{ class.makevars.?, val });
            }
        }
        const use_fc_link = class.makevars != null and lineStarting(makevars_text, "USE_FC_TO_LINK") != null;
        if (use_cxxstd == null) {
            for (cxx_standards) |s| if ((ctx.getenv(try ctx.fmt("USE_CXX{s}", .{s}))) != null) {
                use_cxxstd = s;
                break;
            };
        }
        if (use_cxxstd == null) {
            if (opts.cxx_std orelse ctx.getenv("R_PKG_CXX_STD")) |v| if (isCxxStandard(v)) {
                use_cxxstd = v;
            };
        }
        if (with.contains(.cxx)) {
            if (use_cxxstd) |s| {
                if (mem.eql(u8, s, "98")) return p.needsMake("C++98 standard requested but unsupported", .{});
                if (mem.eql(u8, s, "11") or mem.eql(u8, s, "14")) use_cxxstd = null;
            }
        }
        if (with.contains(.cxx)) {
            if (use_cxxstd) |s| {
                try e.setCommandLine("CXX", try ctx.fmt("$(CXX{s}) $(CXX{s}STD)", .{ s, s }));
                try e.setCommandLine("CXXFLAGS", try ctx.fmt("$(CXX{s}FLAGS)", .{s}));
                try e.setCommandLine("CXXPICFLAGS", try ctx.fmt("$(CXX{s}PICFLAGS)", .{s}));
                try e.setCommandLine("SHLIB_LDFLAGS", try ctx.fmt("$(SHLIB_CXX{s}LDFLAGS)", .{s}));
                try e.setCommandLine("SHLIB_LD", try ctx.fmt("$(SHLIB_CXX{s}LD)", .{s}));
            } else {
                try e.setCommandLine("SHLIB_LDFLAGS", "$(SHLIB_CXXLDFLAGS)");
                try e.setCommandLine("SHLIB_LD", "$(SHLIB_CXXLD)");
            }
        } else if (use_fc_link and (with.contains(.f) or with.contains(.f9x))) {
            try e.setCommandLine("SHLIB_LDFLAGS", "$(SHLIB_FCLDFLAGS)");
            try e.setCommandLine("SHLIB_LD", "$(SHLIB_FCLD)");
            try e.setCommandLine("ALL_LIBS", "$(PKG_LIBS) $(SHLIB_LIBADD) $(SAN_LIBS)");
        }
        if (with.contains(.f) or with.contains(.f9x)) {
            try shlib_libadd.append(a, if (use_fc_link) "$(FCLIBS_XTRA)" else "$(FLIBS) $(FCLIBS_XTRA)");
        }
        if (opts.c_std) |s| {
            try e.setCommandLine("CC", try ctx.fmt("$(CC{s})", .{s}));
            try e.setCommandLine("CFLAGS", try ctx.fmt("$(C{s}FLAGS)", .{s}));
        }
        if (shlib_libadd.items.len > 0) try e.setCommandLine("SHLIB_LIBADD", try mem.join(a, " ", shlib_libadd.items));
        if (with.contains(.f9x) and class.makevars != null and lineStarting(makevars_text, "PKG_FCFLAGS") != null)
            try e.setCommandLine("P_FCFLAGS", "$(PKG_FCFLAGS)");
        if (windows and opts.debug) try e.setCommandLine("DEBUG", "T");
        if (windows and mem.eql(u8, r_arch, "/x64")) {
            try e.setCommandLine("WIN", "64");
            try e.setCommandLine("TCLBIN", "");
        }
        if (opts.use_lto) |lto| {
            try e.setCommandLine("LTO", if (lto) "$(LTO_OPT)" else "");
            try e.setCommandLine("LTO_FC", if (lto) "$(LTO_FC_OPT)" else "");
        }

        // the makefiles, in install.R's order
        if (class.makevars) |mv| e.load(makevars_text, .makevars, src_dir) catch |err| switch (err) {
            error.Unsupported => return p.needsMake("src/{s} has {s}", .{ mv, e.reason }),
            error.OutOfMemory => return error.OutOfMemory,
        };
        e.load(makeconf_text, .makeconf, etc) catch |err| switch (err) {
            error.Unsupported => return p.needsMake("{s}: {s}", .{ makeconf_path, e.reason }),
            error.OutOfMemory => return error.OutOfMemory,
        };
        if (opts.makevars_site) |f| try p.loadLenient(&e, f);
        const shlib_mk = try ctx.fmt("{s}/share/make/{s}", .{ opts.r_home, if (windows) "winshlib.mk" else "shlib.mk" });
        try p.loadLenient(&e, shlib_mk);
        if (opts.makevars_user) |f| try p.loadLenient(&e, f);

        // the standard's compiler must exist (install.R's checkCXX / checkC)
        if (with.contains(.cxx)) if (use_cxxstd) |s| {
            const v = e.raw(try ctx.fmt("CXX{s}", .{s}));
            if (v == null or v.?.value.len == 0) return p.needsMake("C++{s} standard requested but CXX{s} is not defined", .{ s, s });
        };
        if (opts.c_std) |s| {
            const v = e.raw(try ctx.fmt("CC{s}", .{s}));
            if (v == null or v.?.value.len == 0) return p.needsMake("C{s} standard requested but CC{s} is not defined", .{ s, s });
        }

        // OBJECTS to sources. Tier 2 compiles what its build.zig names
        // (rpkg's c_sources and cxx_sources), never these: its sources are
        // src/'s files a suffix rule would compile, for the compiler lines
        // reportCompilers prints, and a file none would (an Objective-C
        // source its build.zig compiles itself) is no reason for make
        // [code-3].
        const objects = try p.wordsOf(&e, "$(OBJECTS)");
        var sources: std.ArrayList(Source) = .empty;
        for (objects) |o| {
            if (!mem.endsWith(u8, o, ".o")) return p.needsMake("OBJECTS names {s}, which no suffix rule makes", .{o});
            const base = o[0 .. o.len - 2];
            const found: ?Source = for (source_exts) |ext| {
                const candidate = try ctx.fmt("{s}{s}", .{ base, ext });
                if (ctx.isFile(try ctx.fmt("{s}/{s}", .{ src_dir, candidate }))) break .{ .lang = @tagName(langOf(candidate).?), .path = candidate, .obj = o };
            } else null;
            if (found) |s| try sources.append(a, s) else if (class.tier != .zig) return p.needsMake("no source for {s} in src/ (a Makevars rule would have to make it)", .{o});
        }

        // the command lines, as Makeconf's suffix rules and shlib.mk's link
        // compose them; the driver (first word) must be R's toolchain
        const toolchain = try ctx.fmt("{s}/bin/toolchain", .{opts.r_home});
        var out: Plan = .{
            .name = opts.name,
            .srcdir = src_dir,
            .output = output,
            .libs_dir = try ctx.fmt("libs{s}", .{r_arch}),
            .toolchain = toolchain,
            .rzig = opts.rzig,
            .link_driver = "",
            .sources = sources.items,
            .env = try a.dupe([]const u8, &.{ try ctx.fmt("R_PACKAGE_NAME={s}", .{opts.name}), try ctx.fmt("CLINK_CPPFLAGS={s}", .{clink}) }),
            .target = packageTarget(ctx),
            .r_include = e.value("R_INCLUDE_DIR") catch "",
        };
        // a language that is present must compile with R's toolchain; the
        // flags of one that is not are kept when they evaluate (the root
        // never runs them)
        const need_c = with.contains(.c) or class.tier == .zig;
        const need_f = with.contains(.f) or with.contains(.f9x);
        const cc_line = try p.toolLine(&e, toolchain, "$(CC) $(ALL_CPPFLAGS) $(ALL_CFLAGS)", "CC", need_c);
        const cxx_line = try p.toolLine(&e, toolchain, "$(CXX) $(ALL_CPPFLAGS) $(ALL_CXXFLAGS)", "CXX", with.contains(.cxx));
        const fc_line = try p.toolLine(&e, toolchain, "$(FC) $(ALL_FFLAGS)", "FC", need_f);
        const f9x_line = try p.toolLine(&e, toolchain, "$(FC) $(ALL_FCFLAGS)", "FC", need_f);
        if (cc_line.tool) |t| out.cc_tool = t;
        if (cxx_line.tool) |t| out.cxx_tool = t;
        if (fc_line.tool) |t| out.fc_tool = t;
        out.cc = cc_line.flags;
        out.cxx = cxx_line.flags;
        out.fc = fc_line.flags;
        out.f9x = f9x_line.flags;
        const link = try p.wordsOf(&e, if (windows) "$(SHLIB_LD) $(SHLIB_LDFLAGS) $(LDFLAGS) $(DLLFLAGS)" else "$(SHLIB_LINK)");
        out.link_driver = try p.toolName(toolchain, link, "SHLIB_LD");
        var link_args: std.ArrayList([]const u8) = .empty;
        try link_args.appendSlice(a, link[1..]);
        // macOS: make's link names the output by its relative path, so the
        // dylib's install name is `<pkg>.so`; zig build links at an absolute
        // path and would record that (step 4 of the design record)
        if (ctx.os == .macos) try link_args.append(a, try ctx.fmt("-Wl,-install_name,{s}", .{output}));
        out.link = link_args.items;
        out.libs = try p.wordsOf(&e, "$(ALL_LIBS)");
        if (windows) {
            const win_def = try ctx.fmt("{s}-win.def", .{opts.name});
            if (ctx.isFile(try ctx.fmt("{s}/{s}", .{ src_dir, win_def }))) out.win_def = win_def else out.def = true;
        }
        return out;
    }

    fn loadLenient(p: *Planner, e: *makefile.Evaluator, path: []const u8) Error!void {
        e.loadFile(path, .makeconf) catch |err| switch (err) {
            error.Unsupported => return p.needsMake("{s}: {s}", .{ path, e.reason }),
            error.OutOfMemory => return error.OutOfMemory,
        };
    }

    /// `text` expanded and split into the words a shell would pass.
    fn wordsOf(p: *Planner, e: *makefile.Evaluator, text: []const u8) Error![]const []const u8 {
        const expanded = e.expand(text) catch |err| switch (err) {
            error.Unsupported => return p.needsMake("{s}", .{e.reason}),
            error.OutOfMemory => return error.OutOfMemory,
        };
        var reason: []const u8 = "";
        return shellwords.split(p.ctx.arena, expanded, &reason) catch |err| switch (err) {
            error.Unsupported => return p.needsMake("{s}", .{reason}),
            error.OutOfMemory => return error.OutOfMemory,
        };
    }

    const ToolLine = struct { tool: ?[]const u8, flags: []const []const u8 };

    /// A compile line: the toolchain tool its first word names, and the
    /// rest. When `required`, the line must evaluate and the tool must be
    /// R's; otherwise whatever evaluates is kept for the record.
    fn toolLine(p: *Planner, e: *makefile.Evaluator, toolchain: []const u8, text: []const u8, what: []const u8, required: bool) Error!ToolLine {
        if (required) {
            const w = try p.wordsOf(e, text);
            return .{ .tool = try p.toolName(toolchain, w, what), .flags = w[1..] };
        }
        const w = p.wordsOf(e, text) catch |err| switch (err) {
            error.NeedsMake => return .{ .tool = null, .flags = &.{} },
            error.OutOfMemory => return error.OutOfMemory,
        };
        if (w.len == 0) return .{ .tool = null, .flags = &.{} };
        return .{ .tool = p.toolName(toolchain, w, what) catch |err| switch (err) {
            error.NeedsMake => null,
            error.OutOfMemory => return error.OutOfMemory,
        }, .flags = w[1..] };
    }

    /// The tool file under `toolchain` that the command's first word names
    /// (Makeconf's `$(R_HOME)/bin/toolchain/zig-cc`; Windows gcc.exe,
    /// zig-fc without its .exe), or error.NeedsMake for any other program.
    fn toolName(p: *Planner, toolchain: []const u8, words: []const []const u8, what: []const u8) Error![]const u8 {
        if (words.len == 0) return p.needsMake("{s} is empty", .{what});
        const driver = try mem.replaceOwned(u8, p.ctx.arena, words[0], "\\", "/");
        const prefix = try p.ctx.fmt("{s}/", .{toolchain});
        const windows = p.ctx.os == .windows;
        const in_toolchain = if (windows) std.ascii.startsWithIgnoreCase(driver, prefix) else mem.startsWith(u8, driver, prefix);
        if (!in_toolchain or mem.findScalar(u8, driver[prefix.len..], '/') != null)
            return p.needsMake("{s} = {s} is not a compiler of R's toolchain ({s})", .{ what, words[0], toolchain });
        const name = driver[prefix.len..];
        if (windows and !std.ascii.endsWithIgnoreCase(name, ".exe")) return p.ctx.fmt("{s}.exe", .{name});
        return name;
    }
};

/// zig's target for a package's own zig code (tier 2): what rzig compiles
/// C for, with `-mcpu=baseline` added by the root.
/// The name of the first variable MAKEFLAGS assigns, or null: a word
/// after GNU make's ` -- ` (where it puts command-line assignments), or
/// a NAME=value word anywhere (make takes those as assignments too).
/// Options (`k`, `-j2`, `--jobserver-auth=fifo:...`) are not assignments.
pub fn makeflagsAssignment(makeflags: []const u8) ?[]const u8 {
    var after_dashes = false;
    var it = mem.tokenizeAny(u8, makeflags, " \t");
    while (it.next()) |w| {
        if (!after_dashes and mem.eql(u8, w, "--")) {
            after_dashes = true;
            continue;
        }
        const eq = mem.indexOfScalar(u8, w, '=') orelse {
            if (after_dashes) return w;
            continue;
        };
        const name = w[0..eq];
        if (after_dashes) return name;
        if (name.len == 0 or !(std.ascii.isAlphabetic(name[0]) or name[0] == '_')) continue;
        var ident = true;
        for (name) |ch| if (!(std.ascii.isAlphanumeric(ch) or ch == '_')) {
            ident = false;
        };
        if (ident) return name;
    }
    return null;
}

test makeflagsAssignment {
    try testing.expect(makeflagsAssignment("") == null);
    try testing.expect(makeflagsAssignment("k -j2 --jobserver-auth=fifo:/tmp/x") == null);
    try testing.expect(makeflagsAssignment(" -j4 -k") == null);
    try testing.expectEqualStrings("LTO_OPT", makeflagsAssignment("k -j2 --jobserver-auth=fifo:/tmp/x -- LTO_OPT=-flto").?);
    try testing.expectEqualStrings("LTO_OPT", makeflagsAssignment("LTO_OPT=-flto").?);
    try testing.expectEqualStrings("CFLAGS", makeflagsAssignment("-j2 CFLAGS=-O0\\ -g").?);
    try testing.expectEqualStrings("X", makeflagsAssignment("-- X=1 Y=2").?);
}

pub fn packageTarget(ctx: *const Ctx) []const u8 {
    return switch (ctx.os) {
        .linux => compiler.linux_target,
        .macos => darwin.triple,
        .windows, .other => "native",
    };
}

/// plan.zon's text.
pub fn writeZon(p: *const Plan, w: *Io.Writer) Io.Writer.Error!void {
    try std.zon.stringify.serialize(p.*, .{}, w);
    try w.writeByte('\n');
}

const cxx_standards = [_][]const u8{ "26", "23", "20", "17", "14", "11", "98" };

fn isCxxStandard(v: []const u8) bool {
    for (cxx_standards) |s| if (mem.eql(u8, s, v)) return true;
    return false;
}

/// Makeconf's `.SUFFIXES` order for sources: the first that exists makes
/// the object.
const source_exts = [_][]const u8{ ".c", ".cc", ".cpp", ".f", ".f90", ".f95" };

fn langOf(name: []const u8) ?Lang {
    if (mem.endsWith(u8, name, ".c")) return .c;
    if (mem.endsWith(u8, name, ".cc") or mem.endsWith(u8, name, ".cpp")) return .cxx;
    if (mem.endsWith(u8, name, ".f")) return .f;
    if (mem.endsWith(u8, name, ".f90") or mem.endsWith(u8, name, ".f95")) return .f9x;
    return null;
}

fn isObjC(name: []const u8) bool {
    return mem.endsWith(u8, name, ".m") or mem.endsWith(u8, name, ".mm") or mem.endsWith(u8, name, ".M");
}

fn stem(name: []const u8) []const u8 {
    const dot = mem.findScalarLast(u8, name, '.') orelse return name;
    return name[0..dot];
}

fn byteOrder(_: void, x: []const u8, y: []const u8) bool {
    return mem.order(u8, x, y) == .lt;
}

/// The value after the last "= " on the first line starting with `name`
/// (install.R's `sub(".*= ", "", grep("^NAME", mconf))`), or null.
fn rawValue(text: []const u8, name: []const u8) ?[]const u8 {
    const line = lineStarting(text, name) orelse return null;
    const eq = mem.findLast(u8, line, "= ") orelse {
        const e2 = mem.findScalarLast(u8, line, '=') orelse return null;
        return mem.trim(u8, line[e2 + 1 ..], " \t\r");
    };
    return mem.trim(u8, line[eq + 2 ..], " \t\r");
}

/// The first line of `text` that starts with `name` followed by spaces
/// and `=` (install.R's `^NAME *=`), or `name` at the start for
/// USE_FC_TO_LINK-style greps (`^NAME`) when followed by anything.
fn lineStarting(text: []const u8, name: []const u8) ?[]const u8 {
    var it = mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| {
        if (!mem.startsWith(u8, line, name)) continue;
        const rest = line[name.len..];
        // `^NAME *=`: for OBJECTS, CXX_STD, PKG_FCFLAGS; USE_FC_TO_LINK is
        // grepped as a bare prefix by install.R, and is always followed by
        // `=` in practice
        const after = mem.trimStart(u8, rest, " ");
        if (after.len > 0 and after[0] == '=') return line;
        if (rest.len == 0 or rest[0] == ' ' or rest[0] == '\t' or rest[0] == '=') return line;
    }
    return null;
}

/// `CXX_STD = CXX17`'s "17" (install.R's gsub chain), when exactly one such
/// line exists.
fn cxxStdLine(text: []const u8) ?[]const u8 {
    var found: ?[]const u8 = null;
    var count: usize = 0;
    var it = mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| {
        if (!mem.startsWith(u8, line, "CXX_STD")) continue;
        const after = mem.trimStart(u8, line["CXX_STD".len..], " ");
        if (after.len == 0 or after[0] != '=') continue;
        count += 1;
        var val = mem.trimStart(u8, after[1..], " ");
        if (mem.startsWith(u8, val, "CXX")) val = val[3..];
        if (mem.findScalar(u8, val, '#')) |h| val = val[0..h];
        found = mem.trimEnd(u8, val, " \t\r");
    }
    return if (count == 1) found else null;
}

// ----------------------------------------------------------------------
// Tests: a small R_HOME modelled on the dev tree's Makeconf and shlib.mk
// ----------------------------------------------------------------------

const testing = std.testing;
const testutil = @import("testutil.zig");

const test_makeconf =
    \\include $(R_SHARE_DIR)/make/vars.mk
    \\CC = $(R_HOME)/bin/toolchain/zig-cc -std=gnu23
    \\CFLAGS = -O2 $(LTO)
    \\CC17 = $(R_HOME)/bin/toolchain/zig-cc -std=gnu17
    \\C17FLAGS = -O2 $(LTO)
    \\CPICFLAGS = -fpic
    \\CPPFLAGS =
    \\C_VISIBILITY =
    \\CXX = $(R_HOME)/bin/toolchain/zig-cxx -std=gnu++20
    \\CXXFLAGS = -O2 $(LTO)
    \\CXXPICFLAGS = -fpic
    \\CXX17 = $(R_HOME)/bin/toolchain/zig-cxx
    \\CXX17FLAGS = -O2 $(LTO)
    \\CXX17PICFLAGS = -fpic
    \\CXX17STD = -std=gnu++17
    \\FC = $(R_HOME)/bin/toolchain/zig-fc
    \\FCFLAGS = -O2 $(LTO_FC)
    \\FCLIBS_XTRA =
    \\FFLAGS = -O2 $(LTO_FC)
    \\FLIBS = -lflang_rt.runtime -lm
    \\FPICFLAGS = -fpic
    \\F_VISIBILITY =
    \\BLAS_LIBS = -L"$(R_HOME)/lib$(R_ARCH)" -lRblas
    \\LDFLAGS =
    \\LIBR0 = -L"$(R_HOME)/lib$(R_ARCH)"
    \\LIBR = -L"$(R_HOME)/lib$(R_ARCH)" -lR
    \\LTO =
    \\LTO_FC =
    \\LTO_OPT = -flto
    \\LTO_FC_OPT = -flto
    \\R_ARCH =
    \\SAFE_FFLAGS = -O2
    \\SAN_LIBS =
    \\SHLIB_CFLAGS =
    \\SHLIB_CXXFLAGS =
    \\SHLIB_CXXLD = $(CXX)
    \\SHLIB_CXXLDFLAGS = -shared# $(CXXFLAGS) $(CXXPICFLAGS) $(LTO_LD)
    \\SHLIB_CXX17LD = $(CXX17) $(CXX17STD)
    \\SHLIB_CXX17LDFLAGS = -shared# $(CXX17FLAGS)
    \\SHLIB_EXT = .so
    \\SHLIB_FCLD = $(FC)
    \\SHLIB_FCLDFLAGS = -shared# $(FCFLAGS) $(FPICFLAGS)
    \\SHLIB_FFLAGS =
    \\SHLIB_LD = $(CC)
    \\SHLIB_LDFLAGS = -shared# $(CFLAGS) $(CPICFLAGS) $(LTO_LD)
    \\SHLIB_LDFLAGS_R = -shared# $(CFLAGS) $(CPICFLAGS) $(LTO_LD)
    \\SHLIB_LIBADD =
    \\SHLIB_LINK = $(SHLIB_LD) $(SHLIB_LDFLAGS) $(LIBR0) $(LDFLAGS)
    \\SHLIB_OPENMP_CFLAGS = -fopenmp
    \\ALL_CFLAGS =  $(PKG_CFLAGS) $(CPICFLAGS) $(SHLIB_CFLAGS) $(CFLAGS)
    \\ALL_CPPFLAGS =  -I"$(R_INCLUDE_DIR)" -DNDEBUG $(PKG_CPPFLAGS) $(CLINK_CPPFLAGS) $(CPPFLAGS)  $(XDEFS)
    \\ALL_CXXFLAGS =  $(PKG_CXXFLAGS) $(CXXPICFLAGS) $(SHLIB_CXXFLAGS) $(CXXFLAGS) $(CXX_DEFS)
    \\ALL_FFLAGS =  $(PKG_FFLAGS) $(FPICFLAGS) $(SHLIB_FFLAGS) $(FFLAGS)
    \\P_FCFLAGS = $(PKG_FFLAGS)
    \\ALL_FCFLAGS =  $(P_FCFLAGS) $(FPICFLAGS) $(SHLIB_FFLAGS) $(FCFLAGS)
    \\ALL_LIBS = $(PKG_LIBS) $(SHLIB_LIBADD) $(SAN_LIBS) $(LIBR)# $(LIBINTL)
    \\.SUFFIXES:
    \\.SUFFIXES: .c .cc .cpp .d .f .f90 .f95 .m .mm .M .o
    \\.c.o:
    \\
++ "\t$(CC) $(ALL_CPPFLAGS) $(ALL_CFLAGS) -c $< -o $@\n";

const test_shlib_mk =
    "SHLIB_LDFLAGS = $(SHLIB_LDFLAGS_R)\n\n" ++
    "all: $(SHLIB)\n\n" ++
    "$(SHLIB): $(OBJECTS)\n" ++
    "\t@if test  \"z$(OBJECTS)\" != \"z\"; then \\\n" ++
    "\t  $(SHLIB_LINK) -o $@ $(OBJECTS) $(ALL_LIBS); \\\n" ++
    "\tfi\n\n" ++
    ".PHONY: all shlib-clean compilers\n";

/// The small R_HOME, at <root>/R (pkgbuild's and check's tests use it too).
pub fn rHome(f: *testutil.Fixture) ![]const u8 {
    try f.write("R/etc/Makeconf", test_makeconf, .default_file);
    try f.write("R/share/make/vars.mk", "R_PKGS_BASE = base tools\n", .default_file);
    try f.write("R/share/make/shlib.mk", test_shlib_mk, .default_file);
    try f.touchExe("R/bin/toolchain/zig-cc");
    return f.path("R");
}

fn expectWords(expected: []const []const u8, actual: []const []const u8) !void {
    try testutil.expectArgs(expected, actual);
}

test "tier 1 C package: cli's Makevars" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const r = try rHome(&f);
    try f.write("cli/DESCRIPTION", "Package: cli\n", .default_file);
    try f.write("cli/src/Makevars", "PKG_CPPFLAGS = -I../inst/include\nPKG_CFLAGS = $(C_VISIBILITY)\nPKG_LIBS = -lpthread\n", .default_file);
    for ([_][]const u8{ "ansi.c", "keypress-unix.c", "keypress.c", "utils.h" }) |s| try f.touch(f.fmt("cli/src/{s}", .{s}));
    var p: Planner = .{ .ctx = &f.ctx };
    const class = try p.classify(f.path("cli"), f.path("cli/src"));
    try testing.expectEqual(Tier.makevars, class.tier);
    try testing.expectEqualStrings("Makevars", class.makevars.?);
    const plan = try p.plan(.{ .r_home = r, .pkg_dir = f.path("cli"), .name = "cli", .linkingto = &.{} }, class);
    try testing.expectEqualStrings("cli.so", plan.output);
    try testing.expectEqualStrings("libs", plan.libs_dir);
    try testing.expectEqualStrings("zig-cc", plan.cc_tool);
    try testing.expectEqualStrings("zig-cc", plan.link_driver);
    try testing.expectEqual(3, plan.sources.len);
    // byte order: '-' sorts before '.'
    try testing.expectEqualStrings("ansi.c", plan.sources[0].path);
    try testing.expectEqualStrings("keypress-unix.c", plan.sources[1].path);
    try testing.expectEqualStrings("keypress.o", plan.sources[2].obj);
    try testing.expectEqualStrings("c", plan.sources[0].lang);
    try expectWords(&.{ "-std=gnu23", f.fmt("-I{s}/include", .{r}), "-DNDEBUG", "-I../inst/include", "-fpic", "-O2" }, plan.cc);
    try expectWords(&.{ "-std=gnu23", "-shared", f.fmt("-L{s}/lib", .{r}) }, plan.link);
    try expectWords(&.{ "-lpthread", f.fmt("-L{s}/lib", .{r}), "-lR" }, plan.libs);
    try testing.expectEqualStrings(f.fmt("{s}/include", .{r}), plan.r_include);
    try expectWords(&.{ "R_PACKAGE_NAME=cli", "CLINK_CPPFLAGS=" }, plan.env);
    try testing.expect(!plan.def);
    // a language not present leaves its flags, driver removed
    try expectWords(&.{ "-std=gnu++20", f.fmt("-I{s}/include", .{r}), "-DNDEBUG", "-I../inst/include", "-fpic", "-O2" }, plan.cxx);
    try expectWords(&.{ "-fpic", "-O2" }, plan.fc);
}

test "C++ link, CXX_STD, LinkingTo, LTO and OBJECTS from Makevars" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const r = try rHome(&f);
    try f.touchExe("R/bin/toolchain/zig-cxx");
    try f.write("p/src/Makevars", "CXX_STD = CXX17\nOBJECTS = a.o sub/b.o\nPKG_CPPFLAGS = -I.\n", .default_file);
    try f.touch("p/src/a.cpp");
    try f.touch("p/src/sub/b.cc");
    try f.touch("p/src/unused.c");
    var p: Planner = .{ .ctx = &f.ctx };
    const class = try p.classify(f.path("p"), f.path("p/src"));
    const plan = try p.plan(.{ .r_home = r, .pkg_dir = f.path("p"), .name = "p", .linkingto = &.{f.path("lib/Rcpp")}, .use_lto = true }, class);
    try testing.expectEqualStrings("zig-cxx", plan.link_driver);
    try testing.expectEqual(2, plan.sources.len);
    try testing.expectEqualStrings("sub/b.cc", plan.sources[1].path);
    try testing.expectEqualStrings("cxx", plan.sources[1].lang);
    try expectWords(&.{ "-std=gnu++17", f.fmt("-I{s}/include", .{r}), "-DNDEBUG", "-I.", f.fmt("-I{s}/lib/Rcpp/include", .{f.root}), "-fpic", "-O2", "-flto" }, plan.cxx);
    try expectWords(&.{ "-std=gnu++17", "-shared", f.fmt("-L{s}/lib", .{r}) }, plan.link);
    try expectWords(&.{ "R_PACKAGE_NAME=p", f.fmt("CLINK_CPPFLAGS=-I'{s}/lib/Rcpp/include'", .{f.root}) }, plan.env);
    // the default C++ standard: CXX and SHLIB_CXXLD
    try f.write("q/src/Makevars", "", .default_file);
    try f.touch("q/src/a.cpp");
    const plan_q = try p.plan(.{ .r_home = r, .pkg_dir = f.path("q"), .name = "q", .linkingto = &.{} }, try p.classify(f.path("q"), f.path("q/src")));
    try expectWords(&.{ "-std=gnu++20", "-shared", f.fmt("-L{s}/lib", .{r}) }, plan_q.link);
    try expectWords(&.{ "-std=gnu++20", f.fmt("-I{s}/include", .{r}), "-DNDEBUG", "-fpic", "-O2" }, plan_q.cxx);
}

test "Fortran: FLIBS in the link, PKG_FFLAGS, USE_FC_TO_LINK" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const r = try rHome(&f);
    try f.touchExe("R/bin/toolchain/zig-fc");
    try f.write("quadprog/src/Makevars", "PKG_LIBS = $(BLAS_LIBS) $(FLIBS)\nPKG_FFLAGS = $(F77_VISIBILITY) $(F_VISIBILITY) $(FPICFLAGS) $(SAFE_FFLAGS) $(SHLIB_FFLAGS) \n", .default_file);
    try f.touch("quadprog/src/solve.QP.f");
    try f.touch("quadprog/src/util.f");
    var p: Planner = .{ .ctx = &f.ctx };
    const plan = try p.plan(.{ .r_home = r, .pkg_dir = f.path("quadprog"), .name = "quadprog", .linkingto = &.{} }, try p.classify(f.path("quadprog"), f.path("quadprog/src")));
    try testing.expectEqualStrings("zig-fc", plan.fc_tool);
    try testing.expectEqualStrings("zig-cc", plan.link_driver);
    try testing.expectEqualStrings("f", plan.sources[0].lang);
    try testing.expectEqualStrings("solve.QP.o", plan.sources[0].obj);
    try expectWords(&.{ "-fpic", "-O2", "-fpic", "-O2" }, plan.fc);
    try expectWords(&.{ f.fmt("-L{s}/lib", .{r}), "-lRblas", "-lflang_rt.runtime", "-lm", "-lflang_rt.runtime", "-lm", f.fmt("-L{s}/lib", .{r}), "-lR" }, plan.libs);
    // USE_FC_TO_LINK: the Fortran driver links, LIBR left out
    try f.write("fl/src/Makevars", "USE_FC_TO_LINK = yes\nPKG_LIBS = $(LAPACK_LIBS) $(BLAS_LIBS) $(FLIBS)\n", .default_file);
    try f.touch("fl/src/a.f90");
    const plan_fl = try p.plan(.{ .r_home = r, .pkg_dir = f.path("fl"), .name = "fl", .linkingto = &.{} }, try p.classify(f.path("fl"), f.path("fl/src")));
    try testing.expectEqualStrings("zig-fc", plan_fl.link_driver);
    try testing.expectEqualStrings("f9x", plan_fl.sources[0].lang);
    try expectWords(&.{ "-shared", f.fmt("-L{s}/lib", .{r}) }, plan_fl.link);
    try expectWords(&.{ f.fmt("-L{s}/lib", .{r}), "-lRblas", "-lflang_rt.runtime", "-lm" }, plan_fl.libs);
}

test "tiers: R only, zig, configure, Makefile, Objective-C, rules, shell, foreign compiler" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const r = try rHome(&f);
    var p: Planner = .{ .ctx = &f.ctx };
    try f.write("r/DESCRIPTION", "Package: r\n", .default_file);
    try testing.expectEqual(Tier.r_only, (try p.classify(f.path("r"), f.path("r/src"))).tier);
    try f.touch("z/src/build.zig");
    try f.touch("z/configure");
    try testing.expectEqual(Tier.zig, (try p.classify(f.path("z"), f.path("z/src"))).tier);
    try f.touch("c/configure");
    try f.touch("c/src/a.c");
    const cc = try p.classify(f.path("c"), f.path("c/src"));
    try testing.expectEqual(Tier.make, cc.tier);
    try testing.expectEqualStrings("a configure script", cc.reason);
    try f.touch("m/src/Makefile");
    try testing.expectEqual(Tier.make, (try p.classify(f.path("m"), f.path("m/src"))).tier);
    // src/Makefile wins over src/build.zig: install.R runs the Makefile and
    // never reaches the hook [code-2]; a configure script is still the
    // reason given first
    try f.touch("zm/src/build.zig");
    try f.touch("zm/src/Makefile");
    const zmc = try p.classify(f.path("zm"), f.path("zm/src"));
    try testing.expectEqual(Tier.make, zmc.tier);
    try testing.expectEqualStrings("src/Makefile", zmc.reason);
    try f.touch("zm/configure");
    try testing.expectEqualStrings("a configure script", (try p.classify(f.path("zm"), f.path("zm/src"))).reason);
    try f.touch("o/src/a.m");
    try testing.expectEqual(Tier.make, (try p.classify(f.path("o"), f.path("o/src"))).tier);
    // a tier-2 package's stray Objective-C source: its build.zig compiles
    // what it names, so no source for x.o is no reason for make [code-3]
    try f.touch("zo/src/build.zig");
    try f.touch("zo/src/bridge.m");
    try f.touch("zo/src/a.c");
    const zoc = try p.classify(f.path("zo"), f.path("zo/src"));
    try testing.expectEqual(Tier.zig, zoc.tier);
    const zop = try p.plan(.{ .r_home = r, .pkg_dir = f.path("zo"), .name = "zo", .linkingto = &.{} }, zoc);
    try testing.expectEqual(1, zop.sources.len);
    try testing.expectEqualStrings("a.c", zop.sources[0].path);
    // cleanup does not make a package tier 3
    try f.touch("d/cleanup");
    try f.touch("d/src/a.c");
    try testing.expectEqual(Tier.makevars, (try p.classify(f.path("d"), f.path("d/src"))).tier);
    // what the Makevars may not hold
    const bad = [_]struct { text: []const u8, reason: []const u8 }{
        .{ .text = "all: $(SHLIB)\n", .reason = "src/Makevars has a rule or target line: 'all: $(SHLIB)'" },
        .{ .text = "PKG_LIBS = $(shell pkg-config --libs x)\n", .reason = "$(shell ...) is not supported" },
        .{ .text = "PKG_LIBS = `pkg-config --libs x`\n", .reason = "a shell metacharacter '`' in" },
        .{ .text = "ifeq ($(R_ARCH),/x64)\nendif\n", .reason = "src/Makevars has a conditional (ifeq)" },
        .{ .text = "OBJECTS = a.o lib/thing.o\n", .reason = "no source for lib/thing.o" },
    };
    for (bad, 0..) |b, i| {
        const dir = f.fmt("b{d}", .{i});
        try f.write(f.fmt("{s}/src/Makevars", .{dir}), b.text, .default_file);
        try f.touch(f.fmt("{s}/src/a.c", .{dir}));
        const class = try p.classify(f.path(dir), f.path(f.fmt("{s}/src", .{dir})));
        try testing.expectEqual(Tier.makevars, class.tier);
        try testing.expectError(error.NeedsMake, p.plan(.{ .r_home = r, .pkg_dir = f.path(dir), .name = dir, .linkingto = &.{} }, class));
        try testing.expect(mem.startsWith(u8, p.reason, b.reason));
    }
    // MAKEFLAGS: make's options plan; an assignment needs make
    try f.touch("mf/src/a.c");
    const mfc = try p.classify(f.path("mf"), f.path("mf/src"));
    try f.env.put("MAKEFLAGS", "k -j2 --jobserver-auth=fifo:/tmp/x");
    _ = try p.plan(.{ .r_home = r, .pkg_dir = f.path("mf"), .name = "mf", .linkingto = &.{} }, mfc);
    try f.env.put("MAKEFLAGS", "k -j2 --jobserver-auth=fifo:/tmp/x -- LTO_OPT=-flto");
    try testing.expectError(error.NeedsMake, p.plan(.{ .r_home = r, .pkg_dir = f.path("mf"), .name = "mf", .linkingto = &.{} }, mfc));
    try testing.expectEqualStrings("MAKEFLAGS sets LTO_OPT", p.reason);
    try f.env.put("MAKEFLAGS", "CFLAGS=-O0");
    try testing.expectError(error.NeedsMake, p.plan(.{ .r_home = r, .pkg_dir = f.path("mf"), .name = "mf", .linkingto = &.{} }, mfc));
    try testing.expectEqualStrings("MAKEFLAGS sets CFLAGS", p.reason);
    // tier 2 plans whatever MAKEFLAGS sets: no make build to differ from
    // [preflight-PF-1]
    try f.touch("mz/src/build.zig");
    const mzc = try p.classify(f.path("mz"), f.path("mz/src"));
    try testing.expectEqual(Tier.zig, mzc.tier);
    try f.env.put("MAKEFLAGS", "k -j2 -- X=1");
    _ = try p.plan(.{ .r_home = r, .pkg_dir = f.path("mz"), .name = "mz", .linkingto = &.{} }, mzc);
    _ = f.env.swapRemove("MAKEFLAGS");
    // the package's Makevars cannot change CC (Makeconf comes after it);
    // the user's ~/.R/Makevars, read last, can, and then make must build
    try f.write("u/src/Makevars", "CC = gcc\n", .default_file);
    try f.touch("u/src/a.c");
    try f.write("dotR/Makevars", "CC = ccache gcc\n", .default_file);
    const uc = try p.classify(f.path("u"), f.path("u/src"));
    _ = try p.plan(.{ .r_home = r, .pkg_dir = f.path("u"), .name = "u", .linkingto = &.{} }, uc);
    try testing.expectError(error.NeedsMake, p.plan(.{ .r_home = r, .pkg_dir = f.path("u"), .name = "u", .linkingto = &.{}, .makevars_user = f.path("dotR/Makevars") }, uc));
    try testing.expect(mem.startsWith(u8, p.reason, "CC = ccache is not a compiler of R's toolchain"));
}

test "Windows: Makevars.win, .def, libs/x64, gcc.exe" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    try f.write("R/etc/x64/Makeconf",
        \\DLLFLAGS=-s
        \\DLLFLAGS += -static-libgcc
        \\BINPREF = $(R_HOME)/bin/toolchain/
        \\IMPDIR = bin/x64
        \\CC = $(BINPREF)gcc.exe $(M_ARCH)
        \\CFLAGS = -O2 -Wall -std=gnu2x
        \\CXX = $(BINPREF)g++.exe -std=gnu++20 $(M_ARCH)
        \\CXXFLAGS = -O2 -Wall
        \\CPICFLAGS =
        \\CXXPICFLAGS =
        \\FC = $(R_HOME)/bin/toolchain/zig-fc
        \\LDFLAGS =
        \\LIBR = -L"$(R_HOME)/$(IMPDIR)" -lR
        \\SHLIB_LD = $(CC)
        \\SHLIB_LDFLAGS = -shared
        \\SHLIB_CXXLD = $(CXX)
        \\SHLIB_CXXLDFLAGS = -shared
        \\SHLIB_LIBADD =
        \\SHLIB_LINK = $(SHLIB_LD) -Wl,--export-all-symbols $(SHLIB_LDFLAGS) $(LDFLAGS)
        \\R_XTRA_CPPFLAGS ?= -I"$(R_HOME)/include" -DNDEBUG
        \\ifneq "$(LTO_OPT)" ""
        \\SHLIB_LDFLAGS += $(CFLAGS)
        \\endif
        \\ALL_CFLAGS = $(R_XTRA_CFLAGS) $(PKG_CFLAGS) $(CPICFLAGS) $(SHLIB_CFLAGS) $(CFLAGS)
        \\ALL_CPPFLAGS = $(R_XTRA_CPPFLAGS) $(PKG_CPPFLAGS) $(CLINK_CPPFLAGS) $(CPPFLAGS) $($*-CPPFLAGS) $(LOCAL_CPPFLAGS) $(XDEFS)
        \\ALL_CXXFLAGS = $(R_XTRA_CXXFLAGS) $(PKG_CXXFLAGS) $(CXXPICFLAGS) $(SHLIB_CXXFLAGS) $(CXXFLAGS) $(CXX_DEFS)
        \\ALL_LIBS = $(PKG_LIBS) $(LOCAL_LIBS) $(SHLIB_LIBADD) $(LIBR) $(LIBINTL)
        \\%.dll:
        \\
    ++ "\t@echo EXPORTS > $*.def\n", .default_file);
    try f.write("R/share/make/winshlib.mk", "all: $(SHLIB)\n\nBASE = $(shell basename $(SHLIB) .dll)\n\n$(SHLIB): $(OBJECTS)\n\t@if test \"z$(OBJECTS)\" != \"z\"; then echo; fi\n", .default_file);
    const r = f.path("R");
    try f.write("cli/src/Makevars", "PKG_LIBS = -lunix\n", .default_file);
    try f.write("cli/src/Makevars.win", "PKG_CPPFLAGS = -I../inst/include\nPKG_LIBS = -lpthread\n", .default_file);
    try f.touch("cli/src/ansi.c");
    var p: Planner = .{ .ctx = &f.ctx };
    const class = try p.classify(f.path("cli"), f.path("cli/src"));
    try testing.expectEqualStrings("Makevars.win", class.makevars.?);
    const plan = try p.plan(.{ .r_home = r, .pkg_dir = f.path("cli"), .name = "cli", .linkingto = &.{} }, class);
    try testing.expectEqualStrings("cli.dll", plan.output);
    try testing.expectEqualStrings("libs/x64", plan.libs_dir);
    try testing.expectEqualStrings("gcc.exe", plan.cc_tool);
    try testing.expectEqualStrings("gcc.exe", plan.link_driver);
    try testing.expectEqualStrings("zig-fc.exe", plan.fc_tool);
    try expectWords(&.{ f.fmt("-I{s}/include", .{r}), "-DNDEBUG", "-I../inst/include", "-O2", "-Wall", "-std=gnu2x" }, plan.cc);
    try expectWords(&.{ "-shared", "-s", "-static-libgcc" }, plan.link);
    try expectWords(&.{ "-lpthread", f.fmt("-L{s}/bin/x64", .{r}), "-lR" }, plan.libs);
    try testing.expect(plan.def);
    try testing.expectEqualStrings("", plan.win_def);
    try testing.expectEqualStrings("native", plan.target);
    // a package's own .def
    try f.touch("cli/src/cli-win.def");
    const plan2 = try p.plan(.{ .r_home = r, .pkg_dir = f.path("cli"), .name = "cli", .linkingto = &.{} }, class);
    try testing.expect(!plan2.def);
    try testing.expectEqualStrings("cli-win.def", plan2.win_def);
    // Makefile.ucrt, then Makefile.win, win over src/build.zig: install.R
    // runs it with make [code-2]
    try f.touch("zm/src/build.zig");
    try f.touch("zm/src/Makefile.win");
    try testing.expectEqualStrings("src/Makefile.win", (try p.classify(f.path("zm"), f.path("zm/src"))).reason);
    try f.touch("zm/src/Makefile.ucrt");
    const zmc = try p.classify(f.path("zm"), f.path("zm/src"));
    try testing.expectEqual(Tier.make, zmc.tier);
    try testing.expectEqualStrings("src/Makefile.ucrt", zmc.reason);
    // a plain Makefile is not R's on Windows
    try f.touch("zu/src/build.zig");
    try f.touch("zu/src/Makefile");
    try testing.expectEqual(Tier.zig, (try p.classify(f.path("zu"), f.path("zu/src"))).tier);
}

test "macOS adds the install name" {
    var f: testutil.Fixture = undefined;
    try f.init(.macos);
    defer f.deinit();
    const r = try rHome(&f);
    try f.touch("p/src/a.c");
    var p: Planner = .{ .ctx = &f.ctx };
    const plan = try p.plan(.{ .r_home = r, .pkg_dir = f.path("p"), .name = "p", .linkingto = &.{} }, try p.classify(f.path("p"), f.path("p/src")));
    try expectWords(&.{ "-std=gnu23", "-shared", f.fmt("-L{s}/lib", .{r}), "-Wl,-install_name,p.so" }, plan.link);
    try testing.expect(mem.endsWith(u8, plan.target, "-native.13.0"));
}

test "plan.zon round trip" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const plan: Plan = .{
        .name = "cli",
        .srcdir = "/tmp/cli/src",
        .output = "cli.so",
        .toolchain = "/R/bin/toolchain",
        .link_driver = "zig-cc",
        .sources = &.{.{ .lang = "c", .path = "a.c", .obj = "a.o" }},
        .cc = &.{ "-std=gnu23", "-I/R/include", "-DX=\"q\"" },
        .link = &.{"-shared"},
        .libs = &.{"-lR"},
        .env = &.{"R_PACKAGE_NAME=cli"},
    };
    var w: Io.Writer.Allocating = .init(a);
    try writeZon(&plan, &w.writer);
    const text = try a.dupeZ(u8, w.written());
    @setEvalBranchQuota(20_000);
    const back = try std.zon.parse.fromSliceAlloc(Plan, a, text, null, .{});
    try testing.expectEqualStrings("cli", back.name);
    try testing.expectEqualStrings("a.o", back.sources[0].obj);
    try testing.expectEqualStrings("-DX=\"q\"", back.cc[2]);
    try testing.expectEqualStrings("libs", back.libs_dir);
    try testing.expect(!back.def);
}

test cxxStdLine {
    try testing.expectEqualStrings("17", cxxStdLine("PKG_LIBS = x\nCXX_STD = CXX17\n").?);
    try testing.expectEqualStrings("20", cxxStdLine("CXX_STD=CXX20 # yes\n").?);
    try testing.expectEqualStrings("17", cxxStdLine("CXX_STD = 17\n").?);
    try testing.expect(cxxStdLine("CXX_STD = CXX17\nCXX_STD = CXX20\n") == null);
    try testing.expect(cxxStdLine("# CXX_STD = CXX17\n") == null);
}

test rawValue {
    try testing.expectEqualStrings(".so", rawValue("X = 1\nSHLIB_EXT = .so\n", "SHLIB_EXT").?);
    try testing.expectEqualStrings("", rawValue("SHLIB_LIBADD = \n", "SHLIB_LIBADD").?);
    try testing.expect(rawValue("SHLIB_EXTRA = x\n", "SHLIB_EXT") == null);
}

//! The part of GNU make that R's package build reads without running a
//! recipe: variable assignments, `$(...)` expansion, conditionals, include,
//! and the text functions, as `R CMD INSTALL`'s make invocation sees them
//! (install.R .shlib_internal: the package's Makevars, etc/Makeconf, the
//! site Makevars, shlib.mk, the user Makevars, then the command line's
//! overrides). pkgplan.zig evaluates with it the strings make would have
//! put on each compile and link line, so `rzig build` needs no make.
//!
//! Two modes. `makeconf` takes what R's own files use (rules and recipes
//! are skipped, conditionals and include evaluated). `makevars`, for the
//! package's file, accepts assignments, comments and blank lines only:
//! a rule, a recipe, a conditional, an include or a `define` makes the
//! package one that needs make (tier 3, pkgplan.zig), as does `$(shell)`
//! or any other function this file does not implement, when expanded.
const std = @import("std");
const mem = std.mem;
const Io = std.Io;
const Allocator = mem.Allocator;

pub const Mode = enum { makeconf, makevars };

pub const Origin = enum { environment, file, command_line, override };
pub const Flavor = enum { recursive, simple };

pub const Var = struct {
    value: []const u8,
    flavor: Flavor,
    origin: Origin,
};

pub const Error = error{ Unsupported, OutOfMemory };

pub const Evaluator = struct {
    arena: Allocator,
    io: Io,
    /// make's working directory: the package's src/, for include and wildcard.
    cwd: []const u8,
    vars: std.StringHashMapUnmanaged(Var) = .empty,
    /// Why the last error.Unsupported happened, for the message.
    reason: []const u8 = "",
    depth: u32 = 0,

    pub fn init(arena: Allocator, io: Io, cwd: []const u8) Evaluator {
        return .{ .arena = arena, .io = io, .cwd = cwd };
    }

    /// Every variable of the environment, as make imports them (recursive
    /// flavor: make expands `$` in them when used).
    pub fn importEnvironment(e: *Evaluator, env: *const std.process.Environ.Map) Allocator.Error!void {
        var it = env.iterator();
        while (it.next()) |kv| {
            if (kv.key_ptr.len == 0 or mem.findAny(u8, kv.key_ptr.*, " \t#:=") != null) continue;
            try e.vars.put(e.arena, kv.key_ptr.*, .{ .value = kv.value_ptr.*, .flavor = .recursive, .origin = .environment });
        }
    }

    pub fn setEnvironment(e: *Evaluator, name: []const u8, val: []const u8) Allocator.Error!void {
        try e.vars.put(e.arena, name, .{ .value = val, .flavor = .recursive, .origin = .environment });
    }

    /// `make NAME=value`: recursive, and beats every assignment a file
    /// makes to it (unless `override`).
    pub fn setCommandLine(e: *Evaluator, name: []const u8, val: []const u8) Allocator.Error!void {
        try e.vars.put(e.arena, name, .{ .value = val, .flavor = .recursive, .origin = .command_line });
    }

    pub fn isDefined(e: *const Evaluator, name: []const u8) bool {
        return e.vars.contains(name);
    }

    pub fn raw(e: *const Evaluator, name: []const u8) ?Var {
        return e.vars.get(name);
    }

    /// The variable's expanded value; "" when unset.
    pub fn value(e: *Evaluator, name: []const u8) Error![]const u8 {
        const v = e.vars.get(name) orelse return "";
        return switch (v.flavor) {
            .simple => v.value,
            .recursive => e.expand(v.value),
        };
    }

    fn fail(e: *Evaluator, comptime f: []const u8, args: anytype) Error {
        e.reason = std.fmt.allocPrint(e.arena, f, args) catch "out of memory";
        return error.Unsupported;
    }

    // ------------------------------------------------------------------
    // Files
    // ------------------------------------------------------------------

    pub fn loadFile(e: *Evaluator, path: []const u8, mode: Mode) Error!void {
        const text = Io.Dir.cwd().readFileAlloc(e.io, path, e.arena, .limited(16 * 1024 * 1024)) catch |err|
            return e.fail("cannot read {s}: {t}", .{ path, err });
        return e.load(text, mode, std.fs.path.dirname(path) orelse ".");
    }

    const Cond = struct {
        /// This branch's lines are evaluated.
        active: bool,
        /// Some branch so far was taken (else branches then stay off).
        taken: bool,
        /// The enclosing branch was active (else, when not, every branch is off).
        parent: bool,
    };

    /// `text` as a makefile; `dir` is the file's directory, where a
    /// relative include is looked up after the working directory.
    pub fn load(e: *Evaluator, text: []const u8, mode: Mode, dir: []const u8) Error!void {
        var conds: std.ArrayList(Cond) = .empty;
        var in_rule = false;
        var lines = LogicalLines{ .text = text, .arena = e.arena };
        while (lines.next()) |line| {
            // a recipe line: belongs to the rule before it
            if (line.len > 0 and line[0] == '\t') {
                if (in_rule) continue;
                if (mem.trim(u8, line, " \t").len == 0) continue;
                if (mode == .makevars) return e.fail("a recipe line (starts with a tab)", .{});
                continue;
            }
            const stripped = mem.trim(u8, try stripComment(e.arena, line), " \t");
            if (stripped.len == 0) continue;

            const active = conds.items.len == 0 or conds.items[conds.items.len - 1].active;
            const word = firstWord(stripped);

            // conditionals, whatever branch is active (they nest)
            if (mem.eql(u8, word, "ifdef") or mem.eql(u8, word, "ifndef") or mem.eql(u8, word, "ifeq") or mem.eql(u8, word, "ifneq")) {
                if (mode == .makevars) return e.fail("a conditional ({s})", .{word});
                const result = if (active) try e.condition(word, stripped[word.len..]) else false;
                try conds.append(e.arena, .{ .active = active and result, .taken = result, .parent = active });
                in_rule = false;
                continue;
            }
            if (mem.eql(u8, word, "else")) {
                if (mode == .makevars) return e.fail("a conditional (else)", .{});
                if (conds.items.len == 0) return e.fail("else without if", .{});
                const c = &conds.items[conds.items.len - 1];
                const rest = mem.trim(u8, stripped[word.len..], " \t");
                if (rest.len == 0) {
                    c.active = c.parent and !c.taken;
                    c.taken = true;
                } else {
                    const w2 = firstWord(rest);
                    if (!(mem.eql(u8, w2, "ifdef") or mem.eql(u8, w2, "ifndef") or mem.eql(u8, w2, "ifeq") or mem.eql(u8, w2, "ifneq")))
                        return e.fail("else followed by '{s}'", .{w2});
                    const result = if (c.parent and !c.taken) try e.condition(w2, rest[w2.len..]) else false;
                    c.active = c.parent and !c.taken and result;
                    if (result) c.taken = true;
                }
                in_rule = false;
                continue;
            }
            if (mem.eql(u8, word, "endif")) {
                if (mode == .makevars) return e.fail("a conditional (endif)", .{});
                if (conds.items.len == 0) return e.fail("endif without if", .{});
                _ = conds.pop();
                in_rule = false;
                continue;
            }
            if (!active) continue;

            // directives
            if (mem.eql(u8, word, "include") or mem.eql(u8, word, "-include") or mem.eql(u8, word, "sinclude")) {
                if (mode == .makevars) return e.fail("an include", .{});
                const optional = word[0] == '-' or word[0] == 's';
                const names = try e.expand(stripped[word.len..]);
                var it = mem.tokenizeAny(u8, names, " \t");
                while (it.next()) |n| try e.include(n, dir, optional);
                in_rule = false;
                continue;
            }
            if (mem.eql(u8, word, "define")) return e.fail("a define", .{});
            if (mem.eql(u8, word, "undefine") or mem.eql(u8, word, "vpath") or mem.eql(u8, word, "unexport") or mem.eql(u8, word, "load") or mem.eql(u8, word, "private"))
                return e.fail("a {s} directive", .{word});

            var rest = stripped;
            var origin: Origin = .file;
            while (true) {
                const w = firstWord(rest);
                if (mem.eql(u8, w, "override")) {
                    origin = .override;
                    rest = mem.trimStart(u8, rest[w.len..], " \t");
                } else if (mem.eql(u8, w, "export")) {
                    rest = mem.trimStart(u8, rest[w.len..], " \t");
                    if (rest.len == 0) break; // `export` alone: every variable; nothing to do
                } else break;
            }
            if (rest.len == 0) continue;

            const asg = findAssignment(rest) orelse {
                // a rule (`target: deps`) or something else
                if (mem.eql(u8, firstWord(rest), "export")) continue; // `export NAME`
                if (mode == .makevars) return e.fail("a rule or target line: '{s}'", .{rest});
                in_rule = true;
                continue;
            };
            in_rule = false;
            try e.assign(asg, origin);
        }
        if (conds.items.len != 0) return e.fail("missing endif", .{});
    }

    fn include(e: *Evaluator, name: []const u8, dir: []const u8, optional: bool) Error!void {
        const candidates: [2][]const u8 = if (std.fs.path.isAbsolute(name))
            .{ name, name }
        else
            .{ try std.fs.path.join(e.arena, &.{ e.cwd, name }), try std.fs.path.join(e.arena, &.{ dir, name }) };
        for (candidates) |p| {
            const text = Io.Dir.cwd().readFileAlloc(e.io, p, e.arena, .limited(16 * 1024 * 1024)) catch continue;
            return e.load(text, .makeconf, std.fs.path.dirname(p) orelse ".");
        }
        if (!optional) return e.fail("cannot include {s}", .{name});
    }

    const Assignment = struct {
        name: []const u8,
        op: enum { recursive, simple, append, conditional, shell },
        value: []const u8,
    };

    /// `NAME op value`, or null for a line without an assignment operator
    /// outside `$(...)` and before any `:` that starts a rule.
    fn findAssignment(line: []const u8) ?Assignment {
        var i: usize = 0;
        var depth: u32 = 0;
        while (i < line.len) : (i += 1) {
            const c = line[i];
            if (c == '$' and i + 1 < line.len and (line[i + 1] == '(' or line[i + 1] == '{')) {
                depth += 1;
                i += 1;
                continue;
            }
            if (depth > 0) {
                if (c == ')' or c == '}') depth -= 1;
                continue;
            }
            switch (c) {
                '=' => {
                    var name_end = i;
                    var op: @FieldType(Assignment, "op") = .recursive;
                    if (i >= 1) switch (line[i - 1]) {
                        ':' => {
                            op = .simple;
                            name_end = i - 1;
                            if (i >= 2 and line[i - 2] == ':') name_end = i - 2;
                        },
                        '+' => {
                            op = .append;
                            name_end = i - 1;
                        },
                        '?' => {
                            op = .conditional;
                            name_end = i - 1;
                        },
                        '!' => {
                            op = .shell;
                            name_end = i - 1;
                        },
                        else => {},
                    };
                    const name = mem.trim(u8, line[0..name_end], " \t");
                    if (name.len == 0) return null;
                    return .{ .name = name, .op = op, .value = mem.trimStart(u8, line[i + 1 ..], " \t") };
                },
                ':' => {
                    // `:=` and `::=` are assignments; a bare colon starts a rule
                    var j = i + 1;
                    while (j < line.len and line[j] == ':') j += 1;
                    if (j < line.len and line[j] == '=') {
                        i = j - 1;
                        continue;
                    }
                    return null;
                },
                else => {},
            }
        }
        return null;
    }

    fn assign(e: *Evaluator, a: Assignment, origin: Origin) Error!void {
        if (a.op == .shell) return e.fail("a shell assignment (!=) of {s}", .{a.name});
        const name = try e.expand(a.name);
        if (name.len == 0 or mem.findAny(u8, name, " \t") != null) return e.fail("bad variable name '{s}'", .{name});
        const old = e.vars.get(name);
        // the command line wins over every file assignment but `override`
        if (old) |o| if (o.origin == .command_line and origin != .override) return;
        switch (a.op) {
            .recursive => try e.vars.put(e.arena, name, .{ .value = a.value, .flavor = .recursive, .origin = origin }),
            .simple => try e.vars.put(e.arena, name, .{ .value = try e.expand(a.value), .flavor = .simple, .origin = origin }),
            .conditional => {
                if (old == null) try e.vars.put(e.arena, name, .{ .value = a.value, .flavor = .recursive, .origin = origin });
            },
            .append => {
                if (old) |o| {
                    const add = if (o.flavor == .simple) try e.expand(a.value) else a.value;
                    const joined = if (o.value.len == 0) add else try std.fmt.allocPrint(e.arena, "{s} {s}", .{ o.value, add });
                    try e.vars.put(e.arena, name, .{ .value = joined, .flavor = o.flavor, .origin = origin });
                } else try e.vars.put(e.arena, name, .{ .value = a.value, .flavor = .recursive, .origin = origin });
            },
            .shell => unreachable,
        }
    }

    /// `ifdef NAME`, `ifeq (a,b)`, `ifeq "a" "b"`, `ifeq 'a' 'b'`.
    fn condition(e: *Evaluator, word: []const u8, rest_in: []const u8) Error!bool {
        const rest = mem.trim(u8, rest_in, " \t");
        if (mem.eql(u8, word, "ifdef") or mem.eql(u8, word, "ifndef")) {
            const name = mem.trim(u8, try e.expand(rest), " \t");
            // defined with a non-empty (unexpanded) value
            const defined = if (e.vars.get(name)) |v| v.value.len > 0 else false;
            return if (word[2] == 'n') !defined else defined;
        }
        var a: []const u8 = undefined;
        var b: []const u8 = undefined;
        if (rest.len > 0 and rest[0] == '(') {
            const close = matchingParen(rest, 0) orelse return e.fail("unbalanced {s}", .{word});
            const inner = rest[1..close];
            const comma = topLevelComma(inner) orelse return e.fail("{s} without a comma", .{word});
            a = mem.trim(u8, inner[0..comma], " \t");
            b = mem.trim(u8, inner[comma + 1 ..], " \t");
        } else {
            const qa = quoted(rest) orelse return e.fail("{s} needs (a,b) or \"a\" \"b\"", .{word});
            a = qa.text;
            const qb = quoted(mem.trimStart(u8, rest[qa.end..], " \t")) orelse return e.fail("{s} needs two quoted words", .{word});
            b = qb.text;
        }
        const eq = mem.eql(u8, try e.expand(a), try e.expand(b));
        return if (mem.eql(u8, word, "ifeq")) eq else !eq;
    }

    fn quoted(s: []const u8) ?struct { text: []const u8, end: usize } {
        if (s.len == 0 or (s[0] != '"' and s[0] != '\'')) return null;
        const close = mem.findScalarPos(u8, s, 1, s[0]) orelse return null;
        return .{ .text = s[1..close], .end = close + 1 };
    }

    // ------------------------------------------------------------------
    // Expansion
    // ------------------------------------------------------------------

    /// `text` with every `$(...)`, `${...}`, `$x` and `$$` expanded.
    pub fn expand(e: *Evaluator, text: []const u8) Error![]const u8 {
        if (mem.findScalar(u8, text, '$') == null) return text;
        if (e.depth > 64) return e.fail("variable references nest too deep (a loop?)", .{});
        e.depth += 1;
        defer e.depth -= 1;
        var out: std.ArrayList(u8) = .empty;
        var i: usize = 0;
        while (i < text.len) {
            const c = text[i];
            if (c != '$') {
                try out.append(e.arena, c);
                i += 1;
                continue;
            }
            if (i + 1 >= text.len) return e.fail("a lone $ at the end of '{s}'", .{text});
            const n = text[i + 1];
            if (n == '$') {
                try out.append(e.arena, '$');
                i += 2;
                continue;
            }
            if (n == '(' or n == '{') {
                const close = matchingParen(text, i + 1) orelse return e.fail("unbalanced $( in '{s}'", .{text});
                try out.appendSlice(e.arena, try e.reference(text[i + 2 .. close]));
                i = close + 1;
                continue;
            }
            // $x: a one-letter variable; the automatic ones are empty here
            try out.appendSlice(e.arena, switch (n) {
                '@', '<', '^', '*', '?', '+', '|', '%' => "",
                else => try e.value(text[i + 1 .. i + 2]),
            });
            i += 2;
        }
        return out.items;
    }

    /// The inside of one `$(...)`: a function call, a substitution
    /// reference `NAME:a=b`, or a variable.
    fn reference(e: *Evaluator, inner: []const u8) Error![]const u8 {
        // a function: a known name followed by whitespace
        if (mem.findAny(u8, inner, " \t")) |sp| {
            const fname = inner[0..sp];
            if (mem.findAny(u8, fname, "$:") == null) {
                if (Function.byName(fname)) |f| return e.call(f, fname, mem.trimStart(u8, inner[sp + 1 ..], " \t"));
                if (isMakeFunction(fname)) return e.fail("$({s} ...) is not supported", .{fname});
            }
        }
        // a substitution reference: $(VAR:a=b) or $(VAR:%.a=%.b)
        if (colonOutsideRefs(inner)) |colon| {
            if (mem.findScalarPos(u8, inner, colon, '=')) |eq| {
                const name = try e.expand(inner[0..colon]);
                const from = try e.expand(inner[colon + 1 .. eq]);
                const to = try e.expand(inner[eq + 1 ..]);
                const pattern_from = if (mem.findScalar(u8, from, '%') != null) from else try std.fmt.allocPrint(e.arena, "%{s}", .{from});
                const pattern_to = if (mem.findScalar(u8, to, '%') != null) to else try std.fmt.allocPrint(e.arena, "%{s}", .{to});
                return patsubst(e.arena, pattern_from, pattern_to, try e.value(name));
            }
        }
        const name = try e.expand(inner);
        return e.value(name);
    }

    const Function = enum {
        subst,
        patsubst,
        strip,
        findstring,
        filter,
        @"filter-out",
        sort,
        word,
        wordlist,
        words,
        firstword,
        lastword,
        dir,
        notdir,
        suffix,
        basename,
        addsuffix,
        addprefix,
        join,
        wildcard,
        @"if",
        @"or",
        @"and",
        value,
        origin,
        flavor,

        fn byName(name: []const u8) ?Function {
            return std.meta.stringToEnum(Function, name);
        }
    };

    /// The other GNU make functions: known, so the message names them.
    fn isMakeFunction(name: []const u8) bool {
        const others = [_][]const u8{ "shell", "foreach", "call", "eval", "file", "error", "warning", "info", "abspath", "realpath", "let", "intcmp", "guile" };
        for (others) |o| if (mem.eql(u8, name, o)) return true;
        return false;
    }

    fn call(e: *Evaluator, f: Function, fname: []const u8, args_text: []const u8) Error![]const u8 {
        const a = e.arena;
        const args = try splitArgs(a, args_text, switch (f) {
            .subst, .patsubst, .wordlist => 3,
            .findstring, .filter, .@"filter-out", .word, .addsuffix, .addprefix, .join => 2,
            .@"if" => 3,
            .@"or", .@"and" => 0, // any number
            else => 1,
        });
        switch (f) {
            .@"if" => {
                if (args.len < 2) return e.fail("$(if) needs a condition and a value", .{});
                const cond = mem.trim(u8, try e.expand(args[0]), " \t");
                if (cond.len > 0) return e.expand(args[1]);
                return if (args.len > 2) e.expand(args[2]) else "";
            },
            .@"or" => {
                for (args) |x| {
                    const v = try e.expand(x);
                    if (mem.trim(u8, v, " \t").len > 0) return v;
                }
                return "";
            },
            .@"and" => {
                var last: []const u8 = "";
                for (args) |x| {
                    last = try e.expand(x);
                    if (mem.trim(u8, last, " \t").len == 0) return "";
                }
                return last;
            },
            .value => {
                const name = try e.expand(args[0]);
                return if (e.vars.get(name)) |v| v.value else "";
            },
            .origin => {
                const name = try e.expand(args[0]);
                const v = e.vars.get(name) orelse return "undefined";
                return switch (v.origin) {
                    .environment => "environment",
                    .file => "file",
                    .command_line => "command line",
                    .override => "override",
                };
            },
            .flavor => {
                const name = try e.expand(args[0]);
                const v = e.vars.get(name) orelse return "undefined";
                return @tagName(v.flavor);
            },
            else => {},
        }
        // the rest expand every argument first
        var x = try a.alloc([]const u8, args.len);
        for (args, 0..) |arg, i| x[i] = try e.expand(arg);
        const need: usize = switch (f) {
            .subst, .patsubst, .wordlist => 3,
            .findstring, .filter, .@"filter-out", .word, .addsuffix, .addprefix, .join => 2,
            else => 1,
        };
        if (x.len < need) return e.fail("$({s}) needs {d} arguments", .{ fname, need });
        switch (f) {
            .subst => return if (x[0].len == 0) x[2] else mem.replaceOwned(u8, a, x[2], x[0], x[1]),
            .patsubst => return patsubst(a, x[0], x[1], x[2]),
            .strip => return joinWords(a, try words(a, x[0])),
            .findstring => return if (mem.find(u8, x[1], x[0]) != null) x[0] else "",
            .filter, .@"filter-out" => {
                const pats = try words(a, x[0]);
                var out: std.ArrayList([]const u8) = .empty;
                for (try words(a, x[1])) |w| {
                    var matched = false;
                    for (pats) |p| if (patternMatch(p, w) != null) {
                        matched = true;
                        break;
                    };
                    if (matched == (f == .filter)) try out.append(a, w);
                }
                return joinWords(a, out.items);
            },
            .sort => {
                const ws = try words(a, x[0]);
                mem.sort([]const u8, ws, {}, lessThan);
                var out: std.ArrayList([]const u8) = .empty;
                for (ws) |w| if (out.items.len == 0 or !mem.eql(u8, out.items[out.items.len - 1], w)) try out.append(a, w);
                return joinWords(a, out.items);
            },
            .word => {
                const n = std.fmt.parseInt(usize, mem.trim(u8, x[0], " \t"), 10) catch return e.fail("$(word) needs a number, not '{s}'", .{x[0]});
                if (n == 0) return e.fail("$(word 0 ...)", .{});
                const ws = try words(a, x[1]);
                return if (n <= ws.len) ws[n - 1] else "";
            },
            .wordlist => {
                const s = std.fmt.parseInt(usize, mem.trim(u8, x[0], " \t"), 10) catch return e.fail("$(wordlist) needs numbers", .{});
                const t = std.fmt.parseInt(usize, mem.trim(u8, x[1], " \t"), 10) catch return e.fail("$(wordlist) needs numbers", .{});
                if (s == 0) return e.fail("$(wordlist 0 ...)", .{});
                const ws = try words(a, x[2]);
                if (s > ws.len or t < s) return "";
                return joinWords(a, ws[s - 1 .. @min(t, ws.len)]);
            },
            .words => return std.fmt.allocPrint(a, "{d}", .{(try words(a, x[0])).len}),
            .firstword => {
                const ws = try words(a, x[0]);
                return if (ws.len > 0) ws[0] else "";
            },
            .lastword => {
                const ws = try words(a, x[0]);
                return if (ws.len > 0) ws[ws.len - 1] else "";
            },
            .dir, .notdir, .suffix, .basename => {
                var out: std.ArrayList([]const u8) = .empty;
                for (try words(a, x[0])) |w| {
                    const slash = mem.findScalarLast(u8, w, '/');
                    const base = if (slash) |s| w[s + 1 ..] else w;
                    const dot = mem.findScalarLast(u8, base, '.');
                    const piece: ?[]const u8 = switch (f) {
                        .dir => if (slash) |s| w[0 .. s + 1] else "./",
                        .notdir => base,
                        .suffix => if (dot) |d| base[d..] else null,
                        .basename => if (dot) |d| w[0 .. w.len - (base.len - d)] else w,
                        else => unreachable,
                    };
                    if (piece) |p| try out.append(a, p);
                }
                return joinWords(a, out.items);
            },
            .addsuffix, .addprefix => {
                var out: std.ArrayList([]const u8) = .empty;
                for (try words(a, x[1])) |w| try out.append(a, if (f == .addsuffix)
                    try std.fmt.allocPrint(a, "{s}{s}", .{ w, x[0] })
                else
                    try std.fmt.allocPrint(a, "{s}{s}", .{ x[0], w }));
                return joinWords(a, out.items);
            },
            .join => {
                const l1 = try words(a, x[0]);
                const l2 = try words(a, x[1]);
                var out: std.ArrayList([]const u8) = .empty;
                for (0..@max(l1.len, l2.len)) |i| try out.append(a, try std.fmt.allocPrint(a, "{s}{s}", .{ if (i < l1.len) l1[i] else "", if (i < l2.len) l2[i] else "" }));
                return joinWords(a, out.items);
            },
            .wildcard => {
                var out: std.ArrayList([]const u8) = .empty;
                for (try words(a, x[0])) |p| try e.glob(p, &out);
                return joinWords(a, out.items);
            },
            else => unreachable,
        }
    }

    /// `$(wildcard pattern)`: `*`, `?` and `[...]` in the last path
    /// component; a pattern without them names a file that must exist.
    /// Results in byte order (GNU make 4.3+ sorts too).
    fn glob(e: *Evaluator, pattern: []const u8, out: *std.ArrayList([]const u8)) Error!void {
        const a = e.arena;
        const slash = mem.findScalarLast(u8, pattern, '/');
        const dir_part: []const u8 = if (slash) |s| pattern[0 .. s + 1] else "";
        const base = if (slash) |s| pattern[s + 1 ..] else pattern;
        if (mem.findAny(u8, dir_part, "*?[") != null) return e.fail("$(wildcard) with a pattern in a directory name: {s}", .{pattern});
        const dir_path = if (dir_part.len == 0) e.cwd else if (std.fs.path.isAbsolute(dir_part)) dir_part else try std.fs.path.join(a, &.{ e.cwd, dir_part });
        if (mem.findAny(u8, base, "*?[") == null) {
            const p = try std.fs.path.join(a, &.{ dir_path, base });
            _ = Io.Dir.cwd().statFile(e.io, p, .{}) catch return;
            try out.append(a, pattern);
            return;
        }
        var d = Io.Dir.cwd().openDir(e.io, dir_path, .{ .iterate = true }) catch return;
        defer d.close(e.io);
        var found: std.ArrayList([]const u8) = .empty;
        var it = d.iterate();
        while (it.next(e.io) catch null) |entry| {
            if (entry.name[0] == '.' and base[0] != '.') continue;
            if (fnmatch(base, entry.name)) try found.append(a, try std.fmt.allocPrint(a, "{s}{s}", .{ dir_part, try a.dupe(u8, entry.name) }));
        }
        mem.sort([]const u8, found.items, {}, lessThan);
        try out.appendSlice(a, found.items);
    }
};

// ----------------------------------------------------------------------
// Pieces
// ----------------------------------------------------------------------

/// Lines with backslash-newline continuations joined: the backslash, the
/// newline and the next line's leading whitespace become one space.
const LogicalLines = struct {
    text: []const u8,
    arena: Allocator,
    pos: usize = 0,

    fn next(it: *LogicalLines) ?[]const u8 {
        if (it.pos >= it.text.len) return null;
        var out: ?std.ArrayList(u8) = null;
        while (true) {
            const end = mem.findScalarPos(u8, it.text, it.pos, '\n') orelse it.text.len;
            var line = it.text[it.pos..end];
            it.pos = @min(end + 1, it.text.len);
            if (line.len > 0 and line[line.len - 1] == '\r') line = line[0 .. line.len - 1];
            const continued = line.len > 0 and line[line.len - 1] == '\\' and !(line.len > 1 and line[line.len - 2] == '\\');
            if (out == null and !continued) return line;
            if (out == null) out = .empty;
            const piece = if (out.?.items.len == 0) line else mem.trimStart(u8, line, " \t");
            if (continued) {
                out.?.appendSlice(it.arena, mem.trimEnd(u8, piece[0 .. piece.len - 1], " \t")) catch return null;
                out.?.append(it.arena, ' ') catch return null;
                if (it.pos >= it.text.len) return out.?.items;
            } else {
                out.?.appendSlice(it.arena, piece) catch return null;
                return out.?.items;
            }
        }
    }
};

/// `line` up to its first unescaped `#`, with `\#` unescaped.
fn stripComment(a: Allocator, line: []const u8) Allocator.Error![]const u8 {
    if (mem.findScalar(u8, line, '#') == null) return line;
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        if (line[i] == '\\' and i + 1 < line.len and line[i + 1] == '#') {
            try out.append(a, '#');
            i += 1;
            continue;
        }
        if (line[i] == '#') break;
        try out.append(a, line[i]);
    }
    return out.items;
}

fn firstWord(s: []const u8) []const u8 {
    const end = mem.findAny(u8, s, " \t") orelse s.len;
    return s[0..end];
}

/// The index of the `)` or `}` closing the paren at `open`, by nesting of
/// the same kind, or null.
fn matchingParen(text: []const u8, open: usize) ?usize {
    const o = text[open];
    const c: u8 = if (o == '(') ')' else '}';
    var depth: u32 = 0;
    var i = open;
    while (i < text.len) : (i += 1) {
        if (text[i] == o) depth += 1 else if (text[i] == c) {
            depth -= 1;
            if (depth == 0) return i;
        }
    }
    return null;
}

/// The first comma outside `$(...)`/`${...}` nesting.
fn topLevelComma(s: []const u8) ?usize {
    var depth: u32 = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        switch (s[i]) {
            '(', '{' => depth += 1,
            ')', '}' => depth -|= 1,
            ',' => if (depth == 0) return i,
            else => {},
        }
    }
    return null;
}

/// The first `:` outside `$(...)` nesting (a substitution reference).
fn colonOutsideRefs(s: []const u8) ?usize {
    var depth: u32 = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        switch (s[i]) {
            '(', '{' => depth += 1,
            ')', '}' => depth -|= 1,
            ':' => if (depth == 0) return i,
            else => {},
        }
    }
    return null;
}

/// A function's arguments: split at top-level commas, at most `max` of
/// them (the last takes the rest, as make does); 0 = any number.
fn splitArgs(a: Allocator, text: []const u8, max: usize) Allocator.Error![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var rest = text;
    while (true) {
        if (max != 0 and out.items.len + 1 == max) {
            try out.append(a, rest);
            break;
        }
        const comma = topLevelComma(rest) orelse {
            try out.append(a, rest);
            break;
        };
        try out.append(a, rest[0..comma]);
        rest = rest[comma + 1 ..];
    }
    return out.items;
}

fn words(a: Allocator, s: []const u8) Allocator.Error![][]const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var it = mem.tokenizeAny(u8, s, " \t\n");
    while (it.next()) |w| try out.append(a, w);
    return out.items;
}

fn joinWords(a: Allocator, ws: []const []const u8) Allocator.Error![]const u8 {
    return mem.join(a, " ", ws);
}

fn lessThan(_: void, x: []const u8, y: []const u8) bool {
    return mem.order(u8, x, y) == .lt;
}

/// make's `%` pattern against one word: the stem it matched, or null.
fn patternMatch(pattern: []const u8, word: []const u8) ?[]const u8 {
    const pct = mem.findScalar(u8, pattern, '%') orelse return if (mem.eql(u8, pattern, word)) "" else null;
    const prefix = pattern[0..pct];
    const suffix = pattern[pct + 1 ..];
    if (word.len < prefix.len + suffix.len) return null;
    if (!mem.startsWith(u8, word, prefix) or !mem.endsWith(u8, word, suffix)) return null;
    return word[prefix.len .. word.len - suffix.len];
}

/// `$(patsubst from,to,text)`: every word matching `from` becomes `to`
/// with its `%` replaced by the stem.
fn patsubst(a: Allocator, from: []const u8, to: []const u8, text: []const u8) Allocator.Error![]const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (try words(a, text)) |w| {
        if (patternMatch(from, w)) |stem| {
            try out.append(a, if (mem.findScalar(u8, to, '%')) |p| try std.fmt.allocPrint(a, "{s}{s}{s}", .{ to[0..p], stem, to[p + 1 ..] }) else to);
        } else try out.append(a, w);
    }
    return joinWords(a, out.items);
}

/// Shell-style file name matching: `*`, `?`, `[abc]`, `[a-z]`, `[!x]`.
fn fnmatch(pattern: []const u8, name: []const u8) bool {
    var p: usize = 0;
    var n: usize = 0;
    var star_p: ?usize = null;
    var star_n: usize = 0;
    while (n < name.len) {
        if (p < pattern.len) {
            switch (pattern[p]) {
                '*' => {
                    star_p = p;
                    star_n = n;
                    p += 1;
                    continue;
                },
                '?' => {
                    p += 1;
                    n += 1;
                    continue;
                },
                '[' => {
                    if (matchClass(pattern[p..], name[n])) |consumed| {
                        p += consumed;
                        n += 1;
                        continue;
                    }
                },
                else => if (pattern[p] == name[n]) {
                    p += 1;
                    n += 1;
                    continue;
                },
            }
        }
        if (star_p) |sp| {
            p = sp + 1;
            star_n += 1;
            n = star_n;
            continue;
        }
        return false;
    }
    while (p < pattern.len and pattern[p] == '*') p += 1;
    return p == pattern.len;
}

/// `[...]` at the start of `pattern` against `c`: the class's length when
/// it matches, else null.
fn matchClass(pattern: []const u8, c: u8) ?usize {
    var i: usize = 1;
    const negate = i < pattern.len and (pattern[i] == '!' or pattern[i] == '^');
    if (negate) i += 1;
    var matched = false;
    var first = true;
    while (i < pattern.len and (first or pattern[i] != ']')) : (first = false) {
        if (i + 2 < pattern.len and pattern[i + 1] == '-' and pattern[i + 2] != ']') {
            if (c >= pattern[i] and c <= pattern[i + 2]) matched = true;
            i += 3;
        } else {
            if (pattern[i] == c) matched = true;
            i += 1;
        }
    }
    if (i >= pattern.len) return null; // no closing bracket: a literal '['
    return if (matched != negate) i + 1 else null;
}

// ----------------------------------------------------------------------
// Tests
// ----------------------------------------------------------------------

const testing = std.testing;

fn testEvaluator(arena: Allocator) Evaluator {
    return Evaluator.init(arena, testing.io, ".");
}

test "assignments, flavors, comments, continuations" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var e = testEvaluator(arena.allocator());
    try e.load(
        \\# a comment
        \\CC = $(R_HOME)/bin/toolchain/zig-cc -std=gnu23
        \\R_HOME = /opt/R
        \\CFLAGS = -O2 $(LTO)
        \\LTO =
        \\SHLIB_LDFLAGS = -shared# $(CFLAGS) $(CPICFLAGS)
        \\SIMPLE := $(CC)
        \\R_HOME = /usr/lib/R
        \\PKG_LIBS = -la \
        \\    -lb
        \\PKG_LIBS += -lc
        \\HASH = a\#b
        \\
    , .makeconf, ".");
    try testing.expectEqualStrings("/usr/lib/R/bin/toolchain/zig-cc -std=gnu23", try e.value("CC"));
    try testing.expectEqualStrings("/opt/R/bin/toolchain/zig-cc -std=gnu23", try e.value("SIMPLE"));
    try testing.expectEqualStrings("-O2 ", try e.value("CFLAGS"));
    try testing.expectEqualStrings("-shared", try e.value("SHLIB_LDFLAGS"));
    try testing.expectEqualStrings("-la -lb -lc", try e.value("PKG_LIBS"));
    try testing.expectEqualStrings("a#b", try e.value("HASH"));
    try testing.expectEqualStrings("", try e.value("UNSET"));
}

test "command line beats files; ?= and environment; override" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var e = testEvaluator(arena.allocator());
    try e.setEnvironment("R_ARCH", "");
    try e.setEnvironment("CLINK_CPPFLAGS", "-I'/lib/Rcpp/include'");
    try e.setCommandLine("SHLIB_LD", "$(SHLIB_CXXLD)");
    try e.setCommandLine("OBJECTS", "a.o b.o");
    try e.load(
        \\SHLIB_LD = $(CC)
        \\SHLIB_CXXLD = $(CXX)
        \\CC = cc
        \\CXX = c++
        \\R_ARCH ?= /x64
        \\LOCAL ?= yes
        \\OBJECTS = x.o
        \\override OBJECTS = y.o
        \\ALL_CPPFLAGS = -I"$(R_INCLUDE_DIR)" $(CLINK_CPPFLAGS)
        \\R_INCLUDE_DIR = /lib/R/include
        \\
    , .makeconf, ".");
    try testing.expectEqualStrings("c++", try e.value("SHLIB_LD"));
    try testing.expectEqualStrings("", try e.value("R_ARCH")); // the environment counts as defined
    try testing.expectEqualStrings("yes", try e.value("LOCAL"));
    try testing.expectEqualStrings("y.o", try e.value("OBJECTS"));
    try testing.expectEqualStrings("-I\"/lib/R/include\" -I'/lib/Rcpp/include'", try e.value("ALL_CPPFLAGS"));
}

test "conditionals" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var e = testEvaluator(arena.allocator());
    try e.load(
        \\USE_LLVM =
        \\ifdef DEBUG
        \\  DLLFLAGS=
        \\else
        \\  DLLFLAGS=-s
        \\endif
        \\DLLFLAGS += -static-libgcc
        \\CCBASE = $(if $(USE_LLVM),clang,gcc)
        \\ifneq "$(LTO_OPT)" ""
        \\LTO = $(LTO_OPT)
        \\ifndef USE_LLVM
        \\  AR = gcc-ar
        \\endif
        \\endif
        \\ifeq ($(R_INSTALLER_BUILD), yes)
        \\  X = installer
        \\else ifeq (a,a)
        \\  X = second
        \\else
        \\  X = third
        \\endif
        \\ifdef USE_LLVM
        \\  Y = llvm
        \\endif
        \\
    , .makeconf, ".");
    try testing.expectEqualStrings("-s -static-libgcc", try e.value("DLLFLAGS"));
    try testing.expectEqualStrings("gcc", try e.value("CCBASE"));
    try testing.expectEqualStrings("", try e.value("LTO"));
    try testing.expect(!e.isDefined("AR"));
    try testing.expectEqualStrings("second", try e.value("X"));
    try testing.expect(!e.isDefined("Y")); // defined but empty is not "defined" to ifdef
}

test "functions and substitution references" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var e = testEvaluator(arena.allocator());
    try e.load(
        \\SRCS = a.c sub/b.c c.cpp
        \\OBJECTS = $(SRCS:.c=.o)
        \\OBJ2 = $(patsubst %.cpp,%.o,$(patsubst %.c,%.o,$(SRCS)))
        \\S = $(subst .c,.o,$(SRCS))
        \\ST = $(strip   a   b  )
        \\F = $(filter %.c,$(SRCS))
        \\FO = $(filter-out %.c,$(SRCS))
        \\LW = $(lastword $(SRCS))
        \\FW = $(firstword $(SRCS))
        \\W = $(words $(SRCS))
        \\ND = $(notdir $(SRCS))
        \\D = $(dir $(SRCS))
        \\B = $(basename $(SRCS))
        \\SX = $(suffix $(SRCS))
        \\AS = $(addsuffix .o,a b)
        \\AP = $(addprefix -I,inc src)
        \\SO = $(sort c a b a)
        \\FS = $(findstring gnu,$(CC))
        \\CC = zig-cc -std=gnu23
        \\J = $(join a b,.c .o)
        \\WD = $(word 2,$(SRCS))
        \\WL = $(wordlist 2,3,$(SRCS))
        \\OR = $(or $(EMPTY),x,y)
        \\AND = $(and x,y)
        \\IF = $(if $(EMPTY),yes,no)
        \\V = $(value CC)
        \\O = $(origin CC) $(origin NOPE)
        \\FL = $(flavor CC)
        \\DOLLAR = $$x
        \\AUTO = [$@$<$*]
        \\NESTED = $(CXX$(STD))
        \\STD = 17
        \\CXX17 = g++17
        \\
    , .makeconf, ".");
    try testing.expectEqualStrings("a.o sub/b.o c.cpp", try e.value("OBJECTS"));
    try testing.expectEqualStrings("a.o sub/b.o c.o", try e.value("OBJ2"));
    try testing.expectEqualStrings("a.o sub/b.o c.opp", try e.value("S"));
    try testing.expectEqualStrings("a b", try e.value("ST"));
    try testing.expectEqualStrings("a.c sub/b.c", try e.value("F"));
    try testing.expectEqualStrings("c.cpp", try e.value("FO"));
    try testing.expectEqualStrings("c.cpp", try e.value("LW"));
    try testing.expectEqualStrings("a.c", try e.value("FW"));
    try testing.expectEqualStrings("3", try e.value("W"));
    try testing.expectEqualStrings("a.c b.c c.cpp", try e.value("ND"));
    try testing.expectEqualStrings("./ sub/ ./", try e.value("D"));
    try testing.expectEqualStrings("a sub/b c", try e.value("B"));
    try testing.expectEqualStrings(".c .c .cpp", try e.value("SX"));
    try testing.expectEqualStrings("a.o b.o", try e.value("AS"));
    try testing.expectEqualStrings("-Iinc -Isrc", try e.value("AP"));
    try testing.expectEqualStrings("a b c", try e.value("SO"));
    try testing.expectEqualStrings("gnu", try e.value("FS"));
    try testing.expectEqualStrings("a.c b.o", try e.value("J"));
    try testing.expectEqualStrings("sub/b.c", try e.value("WD"));
    try testing.expectEqualStrings("sub/b.c c.cpp", try e.value("WL"));
    try testing.expectEqualStrings("x", try e.value("OR"));
    try testing.expectEqualStrings("y", try e.value("AND"));
    try testing.expectEqualStrings("no", try e.value("IF"));
    try testing.expectEqualStrings("zig-cc -std=gnu23", try e.value("V"));
    try testing.expectEqualStrings("file undefined", try e.value("O"));
    try testing.expectEqualStrings("recursive", try e.value("FL"));
    try testing.expectEqualStrings("$x", try e.value("DOLLAR"));
    try testing.expectEqualStrings("[]", try e.value("AUTO"));
    try testing.expectEqualStrings("g++17", try e.value("NESTED"));
}

test "unsupported: shell, foreach, loops, define, != and the makevars mode" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var e = testEvaluator(arena.allocator());
    try e.load("X = $(shell uname)\nY = $(foreach v,a b,$(v))\nLOOP = $(LOOP)\n", .makeconf, ".");
    try testing.expectError(error.Unsupported, e.value("X"));
    try testing.expectEqualStrings("$(shell ...) is not supported", e.reason);
    try testing.expectError(error.Unsupported, e.value("Y"));
    try testing.expectError(error.Unsupported, e.value("LOOP"));
    try testing.expectError(error.Unsupported, e.load("define X\nendef\n", .makeconf, "."));
    try testing.expectError(error.Unsupported, e.load("X != uname\n", .makeconf, "."));

    // the package's Makevars: assignments only
    const bad = [_][]const u8{
        "all: $(SHLIB)\n",
        "\t@echo hi\n",
        "ifeq (a,b)\nendif\n",
        "include other.mk\n",
        "$(SHLIB): sub/libx.a\n",
        ".PHONY: all\n",
    };
    for (bad) |text| {
        var f = testEvaluator(arena.allocator());
        try testing.expectError(error.Unsupported, f.load(text, .makevars, "."));
    }
    var ok = testEvaluator(arena.allocator());
    try ok.load("## comment\n\nPKG_CPPFLAGS = -I../inst/include\nPKG_CFLAGS = $(C_VISIBILITY)\nPKG_LIBS = -lpthread\nOBJECTS = a.o \\\n  b.o\nCXX_STD = CXX17\n", .makevars, ".");
    try testing.expectEqualStrings("a.o b.o", try ok.value("OBJECTS"));
    // a rule in a lenient file is skipped with its recipe
    var r = testEvaluator(arena.allocator());
    try r.load(".SUFFIXES: .c .o\n.c.o:\n\t$(CC) -c $< -o $@\nX = after\n", .makeconf, ".");
    try testing.expectEqualStrings("after", try r.value("X"));
}

test "include and wildcard against the file system" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "vars.mk", .data = "FROM_INCLUDE = yes\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "a.c", .data = "" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "b.c", .data = "" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "c.cpp", .data = "" });
    try tmp.dir.createDirPath(testing.io, "sub");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "sub/d.c", .data = "" });
    var e = Evaluator.init(a, testing.io, root);
    try e.setEnvironment("R_SHARE_DIR", root);
    try e.load(
        \\include $(R_SHARE_DIR)/vars.mk
        \\-include missing.mk
        \\C = $(wildcard *.c)
        \\ALL = $(wildcard *.c sub/*.c *.f)
        \\ONE = $(wildcard a.c nope.c)
        \\
    , .makeconf, root);
    try testing.expectEqualStrings("yes", try e.value("FROM_INCLUDE"));
    try testing.expectEqualStrings("a.c b.c", try e.value("C"));
    try testing.expectEqualStrings("a.c b.c sub/d.c", try e.value("ALL"));
    try testing.expectEqualStrings("a.c", try e.value("ONE"));
    try testing.expectError(error.Unsupported, e.load("include nope.mk\n", .makeconf, root));
}

test fnmatch {
    try testing.expect(fnmatch("*.c", "a.c"));
    try testing.expect(!fnmatch("*.c", "a.cpp"));
    try testing.expect(fnmatch("a?.c", "ab.c"));
    try testing.expect(fnmatch("[a-c]x", "bx"));
    try testing.expect(!fnmatch("[!a-c]x", "bx"));
    try testing.expect(fnmatch("*", "anything"));
    try testing.expect(fnmatch("a*b*c", "aXXbYYc"));
    try testing.expect(!fnmatch("a*b*c", "aXXbYY"));
}

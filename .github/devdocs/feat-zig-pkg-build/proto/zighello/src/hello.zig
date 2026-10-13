const R = @import("R");

fn hello(x: R.SEXP) callconv(.c) R.SEXP {
    const n = R.Rf_asInteger(x);
    return R.Rf_ScalarInteger(n * 2);
}

const entries = [_]R.R_CallMethodDef{
    .{ .name = "hello", .fun = @ptrCast(&hello), .numArgs = 1 },
    .{ .name = null, .fun = null, .numArgs = 0 },
};

export fn R_init_zighello(dll: *R.DllInfo) void {
    _ = R.R_registerRoutines(dll, null, &entries, null, null);
    _ = R.R_useDynamicSymbols(dll, R.FALSE);
}

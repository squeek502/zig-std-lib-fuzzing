const std = @import("std");
const c = @cImport(@cInclude("math.h"));

// complementary tool for the glibc sin fuzzer to get
// the outputs when using musl libc

pub fn main() !void {
    // Read the data from stdin, only up to bytes needed for f64
    var buf align(@alignOf(f64)) = [_]u8{0} ** @sizeOf(f64);

    const stdin: std.fs.File = .stdin();
    _ = try stdin.read(buf[0..]);

    // f32
    const float32 = @as(*const f32, @ptrCast(buf[0..@sizeOf(f32)])).*;
    const c32 = c.sinf(float32);
    std.debug.print("in : {b:0>32}\n", .{@as(u32, @bitCast(float32))});
    std.debug.print("{}\n", .{c32});
    std.debug.print("c  : {b:0>32}\n", .{@as(u32, @bitCast(c32))});

    // f64
    const float64 = @as(*const f64, @ptrCast(buf[0..])).*;
    const c64 = c.sin(float64);
    std.debug.print("in : {b:0>64}\n", .{@as(u64, @bitCast(float64))});
    std.debug.print("{}\n", .{c64});
    std.debug.print("c  : {b:0>64}\n", .{@as(u64, @bitCast(c64))});
}

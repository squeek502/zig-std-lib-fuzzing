const std = @import("std");
const c = @cImport(@cInclude("math.h"));

// complementary tool for the glibc sin fuzzer to get
// the outputs when using musl libc

pub fn main() !void {
    // Read the data from stdin, only up to bytes needed for f64
    var buf align(@alignOf(f64)) = [_]u8{0} ** @sizeOf(f64);
    const stdin = std.io.getStdIn();
    _ = try stdin.read(buf[0..]);

    // f32
    const float32 = @ptrCast(*const f32, buf[0..@sizeOf(f32)]).*;
    const c32 = c.sinf(float32);
    std.debug.print("in : {b:0>32}\n", .{@bitCast(u32, float32)});
    std.debug.print("{}\n", .{c32});
    std.debug.print("c  : {b:0>32}\n", .{@bitCast(u32, c32)});

    // f64
    var float64 = @ptrCast(*const f64, buf[0..]).*;
    const c64 = c.sin(float64);
    std.debug.print("in : {b:0>64}\n", .{@bitCast(u64, float64)});
    std.debug.print("{}\n", .{c64});
    std.debug.print("c  : {b:0>64}\n", .{@bitCast(u64, c64)});
}

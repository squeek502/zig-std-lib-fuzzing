const std = @import("std");
const c = @cImport(@cInclude("math.h"));

pub export fn main() void {
    zigMain() catch unreachable;
}

pub fn zigMain() !void {
    // Read the data from stdin, only up to bytes needed for f64
    var buf align(@alignOf(f64)) = [_]u8{0} ** @sizeOf(f64);
    const stdin = std.io.getStdIn();
    _ = try stdin.read(buf[0..]);

    // f32
    const float32 = @ptrCast(*const f32, buf[0..@sizeOf(f32)]).*;
    const zig32 = std.math.sin(float32);
    const c32 = c.sinf(float32);
    try std.testing.expectEqual(c32, zig32);

    // f64
    var float64 = @ptrCast(*const f64, buf[0..]).*;
    const zig64 = std.math.sin(float64);
    const c64 = c.sin(float64);
    try std.testing.expectEqual(c64, zig64);
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @cImport(@cInclude("puff.h"));

pub export fn main() void {
    zigMain() catch unreachable;
}

fn puffAlloc(allocator: *Allocator, input: []const u8) ![]u8 {
    // call once to get the uncompressed length
    var decoded_len: c_ulong = undefined;
    var source_len: c_ulong = input.len;
    const result = c.puff(c.NIL, &decoded_len, input.ptr, &source_len);

    if (result != 0) {
        return translatePuffError(result);
    }

    var dest = try allocator.alloc(u8, decoded_len);
    errdefer allocator.free(dest);

    // call again to actually get the output
    _ = c.puff(dest.ptr, &decoded_len, input.ptr, &source_len);
    return dest;
}

fn translatePuffError(code: c_int) anyerror {
    return switch (code) {
        2 => error.EndOfStream,
        1 => error.OutOfMemory,
        0 => unreachable,
        -1 => error.InvalidBlockType,
        -2 => error.InvalidStoredSize,
        -3 => error.InvalidDistance,
        -4 => error.InvalidLength,
        -5 => error.InvalidLength,
        -6 => error.InvalidLength,
        -7 => error.InvalidLength,
        -8 => error.InvalidDistance,
        -9 => error.MissingEOBCode,
        -10 => error.InvalidFixedCode,
        -11 => error.Unknown,
        else => unreachable,
    };
}

pub fn zigMain() !void {
    // Setup an allocator that will detect leaks/use-after-free/etc
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // this will check for leaks and crash the program if it finds any
    defer std.debug.assert(gpa.deinit() == false);
    const allocator = &gpa.allocator;

    // Read the data from stdin
    const stdin = std.io.getStdIn();
    const data = try stdin.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(data);

    // Try to parse the data with puff
    const inflated_puff: ?[]u8 = puffAlloc(allocator, data) catch null;
    defer if (inflated_puff != null) {
        allocator.free(inflated_puff.?);
    };

    const reader = std.io.fixedBufferStream(data).reader();
    var window: [0x8000]u8 = undefined;
    var inflate = std.compress.deflate.inflateStream(reader, &window);

    var inflated: ?[]u8 = inflate.reader().readAllAlloc(allocator, std.math.maxInt(usize)) catch null;
    defer if (inflated != null) {
        allocator.free(inflated.?);
    };

    if (inflated_puff == null or inflated == null) {
        std.debug.assert(inflated_puff == null); // inflated is null but inflated_puff isnt
        std.debug.assert(inflated == null); // inflated_puff is null but inflated isnt
    } else {
        try std.testing.expectEqualSlices(u8, inflated_puff.?, inflated.?);
    }
}

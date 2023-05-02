const std = @import("std");
const c = @cImport(@cInclude("xxhash.h"));

pub export fn main() void {
    zigMain() catch unreachable;
}

pub fn zigMain() !void {
    // Setup an allocator that will detect leaks/use-after-free/etc
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // this will check for leaks and crash the program if it finds any
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    // Read the data from stdin
    const stdin = std.io.getStdIn();
    const data = try stdin.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(data);

    const expected_hash_32 = c.XXH32(data.ptr, data.len, 0);
    const expected_hash_64 = c.XXH64(data.ptr, data.len, 0);

    const actual_hash_32 = std.hash.XxHash32.hash(data);
    const actual_hash_64 = std.hash.XxHash64.hash(data);

    try std.testing.expectEqual(expected_hash_32, actual_hash_32);
    try std.testing.expectEqual(expected_hash_64, actual_hash_64);
}

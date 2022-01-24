const std = @import("std");

export fn cMain() void {
    main() catch unreachable;
}

comptime {
    @export(cMain, .{ .name = "main", .linkage = .Strong });
}

pub fn main() !void {
    // Setup an allocator that will detect leaks/use-after-free/etc
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // this will check for leaks and crash the program if it finds any
    defer std.debug.assert(gpa.deinit() == false);
    const allocator = gpa.allocator();

    // Read the data from stdin
    const stdin = std.io.getStdIn();
    const data = try stdin.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(data);

    // Compress the data
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    // TODO: vary the level?
    var comp = try std.compress.deflate.compressor(allocator, buf.writer(), .{});
    _ = try comp.write(data);
    try comp.close();
    comp.deinit();

    // Now try to decompress it
    const reader = std.io.fixedBufferStream(buf.items).reader();
    var inflate = try std.compress.deflate.decompressor(allocator, reader, null);
    defer inflate.deinit();

    var inflated = inflate.reader().readAllAlloc(allocator, std.math.maxInt(usize)) catch {
        return;
    };
    defer allocator.free(inflated);

    try std.testing.expectEqualSlices(u8, data, inflated);
}

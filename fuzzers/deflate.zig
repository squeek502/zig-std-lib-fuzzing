const std = @import("std");

pub export fn main() void {
    zigMain() catch unreachable;
}

pub fn zigMain() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    // Read the data from stdin
    const stdin = std.fs.File.stdin();
    const data = try stdin.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(data);

    // Try to parse the data
    var fixed_reader: std.Io.Reader = .fixed(data);
    var decompress = std.compress.flate.Decompress.init(&fixed_reader, .raw, &.{});

    var aw: std.Io.Writer.Allocating = .init(allocator);
    try aw.ensureUnusedCapacity(std.compress.flate.max_window_len);
    defer aw.deinit();

    const decompressed_len = decompress.reader.streamRemaining(&aw.writer) catch {
        return;
    };
    _ = decompressed_len;
}

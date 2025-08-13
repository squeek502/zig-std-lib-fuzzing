const std = @import("std");

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
    const stdin = std.fs.File.stdin();
    const data = try stdin.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(data);

    var out: std.io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    try out.ensureUnusedCapacity(std.compress.zstd.default_window_len + std.compress.zstd.block_size_max);

    var in: std.io.Reader = .fixed(data);
    var zstd_stream: std.compress.zstd.Decompress = .init(&in, &.{}, .{
        .window_len = std.compress.zstd.default_window_len,
    });
    _ = zstd_stream.reader.streamRemaining(&out.writer) catch {
        if (zstd_stream.err) |zstd_err| switch (zstd_err) {
            error.DictionaryIdFlagUnsupported => return,
            else => {},
        };
    };
}

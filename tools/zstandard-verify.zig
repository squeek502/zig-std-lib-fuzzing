const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len < 3) {
        std.debug.print("Usage: {s} <compressed input> <original/uncompressed input>\n", .{args[0]});
        return error.MissingCommandLineArguments;
    }

    const input_filename = args[1];
    const input = std.fs.cwd().readFileAlloc(allocator, input_filename, std.math.maxInt(usize)) catch |err| {
        std.debug.print("unable to read compressed input file '{s}': {}\n", .{ input_filename, err });
        return err;
    };
    defer allocator.free(input);

    const uncompressed_filename = args[2];
    const uncompressed = std.fs.cwd().readFileAlloc(allocator, uncompressed_filename, std.math.maxInt(usize)) catch |err| {
        std.debug.print("unable to read original/uncompressed input file {s}: {}\n", .{ uncompressed_filename, err });
        return err;
    };
    defer allocator.free(uncompressed);

    // decode
    decode: {
        var out: std.ArrayListUnmanaged(u8) = .empty;
        defer out.deinit(allocator);
        try out.ensureUnusedCapacity(allocator, std.compress.zstd.default_window_len);

        var in: std.io.Reader = .fixed(input);
        var zstd_stream: std.compress.zstd.Decompress = .init(&in, &.{}, .{});
        zstd_stream.reader.appendRemaining(allocator, null, &out, .unlimited) catch |err| {
            if (zstd_stream.err) |zstd_err| switch (zstd_err) {
                error.DictionaryIdFlagUnsupported => break :decode,
                else => {},
            };
            return zstd_stream.err orelse err;
        };

        try std.testing.expectEqualSlices(u8, uncompressed, out.items);
    }
}

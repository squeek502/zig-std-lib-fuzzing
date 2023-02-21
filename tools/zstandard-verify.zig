const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == false);
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

    // decompressStream
    {
        var in_stream = std.io.fixedBufferStream(input);
        var stream = std.compress.zstandard.decompressStream(allocator, in_stream.reader());
        defer stream.deinit();
        const result = try stream.reader().readAllAlloc(allocator, std.math.maxInt(usize));
        defer allocator.free(result);

        try std.testing.expectEqualSlices(u8, uncompressed, result);
    }

    // decodeAlloc
    decodeAlloc: {
        const result = std.compress.zstandard.decompress.decodeAlloc(allocator, input, true, 8 * (1 << 20)) catch |err| switch (err) {
            error.DictionaryIdFlagUnsupported => break :decodeAlloc,
            else => return err,
        };
        defer allocator.free(result);

        try std.testing.expectEqualSlices(u8, uncompressed, result);
    }

    // decode
    decode: {
        var buf = try allocator.alloc(u8, uncompressed.len);
        defer allocator.free(buf);
        const result_len = std.compress.zstandard.decompress.decode(buf, input, true) catch |err| switch (err) {
            error.UnknownContentSizeUnsupported => break :decode,
            error.DictionaryIdFlagUnsupported => break :decode,
            else => return err,
        };

        try std.testing.expectEqualSlices(u8, uncompressed, buf[0..result_len]);
    }
}

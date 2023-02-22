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

    // decompressStream
    decompressStream: {
        var in_stream = std.io.fixedBufferStream(data);
        var stream = std.compress.zstd.decompressStream(allocator, in_stream.reader());
        defer stream.deinit();
        const result = stream.reader().readAllAlloc(allocator, std.math.maxInt(usize)) catch break :decompressStream;
        defer allocator.free(result);
    }

    // decodeAlloc
    decodeAlloc: {
        const result = std.compress.zstd.decompress.decodeAlloc(allocator, data, false, 1 << 23) catch break :decodeAlloc;
        defer allocator.free(result);
    }

    // decode
    decode: {
        // Assume the uncompressed size is less than or equal to the compressed size.
        // The uncompressed data might not always fit, but that's fine for the purposes of this fuzzer
        var buf = try allocator.alloc(u8, data.len);
        defer allocator.free(buf);
        _ = std.compress.zstd.decompress.decode(buf, data, false) catch break :decode;
    }
}

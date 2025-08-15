const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @cImport(@cInclude("zstd.h"));

pub export fn main() void {
    zigMain() catch unreachable;
}

// Based on examples/streaming_decompression.c
fn cZstdStreaming(allocator: Allocator, input: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    const buf_out_size = c.ZSTD_DStreamOutSize();
    var buf_out = try allocator.alloc(u8, buf_out_size);
    defer allocator.free(buf_out);

    const dctx = c.ZSTD_createDCtx();
    defer _ = c.ZSTD_freeDCtx(dctx);

    var in_buffer = c.ZSTD_inBuffer{ .src = input.ptr, .size = input.len, .pos = 0 };
    var last_ret: usize = 0;
    while (in_buffer.pos < in_buffer.size) {
        var out_buffer = c.ZSTD_outBuffer{ .dst = buf_out.ptr, .size = buf_out.len, .pos = 0 };
        const res = c.ZSTD_decompressStream(dctx, &out_buffer, &in_buffer);
        if (c.ZSTD_isError(res) != 0) {
            const err_name = std.mem.sliceTo(c.ZSTD_getErrorName(res), 0);
            std.debug.print("ZSTD ERROR: {s}\n", .{err_name});
            if (std.mem.eql(u8, err_name, "Restored data doesn't match checksum")) {
                return error.BadChecksum;
            }
            return error.DecompressError;
        }
        try result.appendSlice(allocator, buf_out[0..out_buffer.pos]);
        last_ret = res;
    }

    // From examples/streaming_decompression.c:
    // "Last return did not end on a frame, but we reached the end of the file"
    if (last_ret != 0) {
        return error.EofBeforeEndOfStream;
    }

    return result.toOwnedSlice(allocator);
}

fn zigZstdStreaming(allocator: Allocator, input: []const u8) ![]u8 {
    var out: std.io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    var in: std.io.Reader = .fixed(input);
    var zstd_stream: std.compress.zstd.Decompress = .init(&in, &.{}, .{});
    _ = zstd_stream.reader.streamRemaining(&out.writer) catch |err| {
        return zstd_stream.err orelse err;
    };

    return out.toOwnedSlice();
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

    var expected_error: anyerror = error.NoError;
    const expected_bytes: ?[]u8 = cZstdStreaming(allocator, data) catch |err| blk: {
        // The Zig implementation doesn't support checksum validation currently
        if (err == error.BadChecksum) return;

        expected_error = err;
        break :blk null;
    };
    defer if (expected_bytes != null) allocator.free(expected_bytes.?);

    var actual_error: anyerror = error.NoError;
    const actual_bytes: ?[]u8 = zigZstdStreaming(allocator, data) catch |err| blk: {
        std.debug.dumpStackTrace(@errorReturnTrace().?.*);
        switch (err) {
            // Ignore this error since it's an intentional difference from the zstd C implementation
            error.DictionaryIdFlagUnsupported => return,
            else => {},
        }

        actual_error = err;
        break :blk null;
    };
    defer if (actual_bytes != null) allocator.free(actual_bytes.?);

    std.debug.print("zstd error: {}, zig error: {}\n", .{ expected_error, actual_error });
    if (expected_bytes == null or actual_bytes == null) {
        if (expected_bytes != null or actual_bytes != null) {
            return error.MismatchedErrors;
        }
    } else {
        try std.testing.expectEqualSlices(u8, expected_bytes.?, actual_bytes.?);
    }
}

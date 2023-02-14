const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @cImport(@cInclude("zstd.h"));

pub export fn main() void {
    zigMain() catch unreachable;
}

// Based on examples/streaming_decompression.c
fn cZstdStreaming(allocator: Allocator, input: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    const buf_out_size = c.ZSTD_DStreamOutSize();
    var buf_out = try allocator.alloc(u8, buf_out_size);
    defer allocator.free(buf_out);

    var dctx = c.ZSTD_createDCtx();
    defer _ = c.ZSTD_freeDCtx(dctx);

    var in_buffer = c.ZSTD_inBuffer{ .src = input.ptr, .size = input.len, .pos = 0 };
    var last_ret: usize = 0;
    while (in_buffer.pos < in_buffer.size) {
        var out_buffer = c.ZSTD_outBuffer{ .dst = buf_out.ptr, .size = buf_out.len, .pos = 0 };
        const res = c.ZSTD_decompressStream(dctx, &out_buffer, &in_buffer);
        if (c.ZSTD_isError(res) != 0) {
            std.debug.print("ZSTD ERROR: {s}\n", .{c.ZSTD_getErrorName(res)});
            return error.DecompressError;
        }
        try result.appendSlice(buf_out[0..out_buffer.pos]);
        last_ret = res;
    }

    // From examples/streaming_decompression.c:
    // "Last return did not end on a frame, but we reached the end of the file"
    if (last_ret != 0) {
        return error.EofBeforeEndOfStream;
    }

    return result.toOwnedSlice();
}

fn zigZstdStreaming(allocator: Allocator, input: []const u8) ![]u8 {
    var in_stream = std.io.fixedBufferStream(input);
    var stream = std.compress.zstandard.zstandardStream(allocator, in_stream.reader(), 1 << 23);
    defer stream.deinit();
    const result = try stream.reader().readAllAlloc(allocator, std.math.maxInt(usize));
    errdefer allocator.free(result);

    return result;
}

pub fn zigMain() !void {
    // Setup an allocator that will detect leaks/use-after-free/etc
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // this will check for leaks and crash the program if it finds any
    defer std.debug.assert(gpa.deinit() == false);
    const allocator = gpa.allocator();

    // Read the data from stdin
    const stdin = std.io.getStdIn();
    const data = try stdin.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(data);

    var expected_error: anyerror = error.NoError;
    const expected_bytes: ?[]u8 = cZstdStreaming(allocator, data) catch |err| blk: {
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
            error.MalformedFrame, error.MalformedBlock, error.OutOfMemory, error.ChecksumFailure => {},
            // Only possible when max_size is exceeded during Reader.readAllAlloc, which we set as maxInt(usize)
            error.StreamTooLong => unreachable,
        }

        actual_error = err;
        break :blk null;
    };
    defer if (actual_bytes != null) allocator.free(actual_bytes.?);

    if (expected_bytes == null or actual_bytes == null) {
        if (expected_bytes != null or actual_bytes != null) {
            std.debug.print("zstd error: {}, zig error: {}\n", .{ expected_error, actual_error });
            return error.MismatchedErrors;
        }
    } else {
        try std.testing.expectEqualSlices(u8, expected_bytes.?, actual_bytes.?);
    }
}

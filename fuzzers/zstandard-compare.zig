const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @cImport(@cInclude("zstd.h"));

pub export fn main() void {
    zigMain() catch unreachable;
}

// cImported version overflows instead of wraps
const ZSTD_CONTENTSIZE_ERROR = @as(c_ulonglong, 0) -% @as(c_int, 2);
const ZSTD_CONTENTSIZE_UNKNOWN = @as(c_ulonglong, 0) -% @as(c_int, 1);

fn cZstdAlloc(allocator: Allocator, input: []const u8) ![]u8 {
    const content_size: c_ulonglong = c.ZSTD_getFrameContentSize(input.ptr, input.len);
    if (content_size == ZSTD_CONTENTSIZE_ERROR) return error.ErrorContentSize;
    if (content_size == ZSTD_CONTENTSIZE_UNKNOWN) return error.UnknownContentSize;

    var dest = try allocator.alloc(u8, content_size);
    errdefer allocator.free(dest);

    const res = c.ZSTD_decompress(dest.ptr, dest.len, input.ptr, input.len);
    if (c.ZSTD_isError(res) != 0) {
        std.debug.print("ZSTD ERROR: {s}\n", .{c.ZSTD_getErrorName(res)});
        return error.DecompressError;
    }
    return dest;
}

fn zigZstdAlloc(allocator: Allocator, input: []const u8) ![]u8 {
    const content_size = blk: {
        var fbs = std.io.fixedBufferStream(input);
        var reader = fbs.reader();
        const frame_type = std.compress.zstandard.decompress.decodeFrameType(reader) catch return error.ErrorContentSize;
        switch (frame_type) {
            .zstandard => {},
            .skippable => break :blk 0,
        }
        const header = std.compress.zstandard.decompress.decodeZstandardHeader(reader) catch return error.ErrorContentSize;
        break :blk header.content_size orelse return error.UnknownContentSize;
    };

    var dest = try allocator.alloc(u8, content_size);
    errdefer allocator.free(dest);

    _ = try std.compress.zstandard.decompress.decode(dest, input, true);
    return dest;
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
    const expected_bytes: ?[]u8 = cZstdAlloc(allocator, data) catch |err| blk: {
        expected_error = err;
        break :blk null;
    };
    defer if (expected_bytes != null) allocator.free(expected_bytes.?);

    var actual_error: anyerror = error.NoError;
    const actual_bytes: ?[]u8 = zigZstdAlloc(allocator, data) catch |err| blk: {
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

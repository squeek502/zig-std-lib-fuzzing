const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @cImport({
    // Necessary for ZSTD_decompressBound to be visible
    @cDefine("ZSTD_STATIC_LINKING_ONLY", "1");
    @cInclude("zstd.h");
});

pub export fn main() void {
    zigMain() catch unreachable;
}

// cImported version overflows instead of wraps
const ZSTD_CONTENTSIZE_ERROR = @as(c_ulonglong, 0) -% @as(c_int, 2);

fn cZstdAlloc(allocator: Allocator, input: []const u8) ![]u8 {
    // Note: It might make more sense to compare using the streaming API instead, but this should suffice as it claims
    // to guarantee a size that will fit the uncompressed data of all frames within `input`
    const content_size_upper_bound: c_ulonglong = c.ZSTD_decompressBound(input.ptr, input.len);
    if (content_size_upper_bound == ZSTD_CONTENTSIZE_ERROR) return error.ErrorContentSize;

    // If the content_size is zero, then Zig will return a slice with a ptr value that is maxInt(usize)
    // which the zstd C implementation chokes on (perhaps a bug in the zstd implementation, it can trip assertions
    // or cause UBSAN to trigger if e.g. 0xffffffffffffffff is the value of the dest ptr). So, instead
    // of allocating, we use a zero-length array to give ZSTD_decompress a 'real' pointer even though it's of
    // length zero so it shouldn't really matter what the ptr value is.
    //
    // Note: This is not the case in C because malloc will return a 'real' pointer even if the requested
    //       size is zero.
    //
    // We use a non-zero array size here to ensure that the ptr gets a real value (mostly just to avoid any
    // other weirdness, this part isn't to mitigate anything in particular but to avoid any potential
    // problems since in Debug mode &[_]u8{} will have an address of 0xaaaaaaaaaaaaaaaa).
    var dest_buf: [1]u8 = undefined;
    var dest: []u8 = if (content_size_upper_bound != 0) try allocator.alloc(u8, content_size_upper_bound) else dest_buf[0..0];
    errdefer allocator.free(dest);

    const res = c.ZSTD_decompress(dest.ptr, dest.len, input.ptr, input.len);
    if (c.ZSTD_isError(res) != 0) {
        std.debug.print("ZSTD ERROR: {s}\n", .{c.ZSTD_getErrorName(res)});
        return error.DecompressError;
    }
    return allocator.realloc(dest, res);
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
    const window_size_max = 8 * (1 << 20);
    const actual_bytes: ?[]u8 = std.compress.zstandard.decompress.decodeAlloc(allocator, data, true, window_size_max) catch |err| blk: {
        // Ignore this error since it's an intentional difference from the zstd C implementation
        if (err == error.DictionaryIdFlagUnsupported) {
            return;
        }
        // https://github.com/facebook/zstd/issues/3482
        if (err == error.BlockSizeOverMaximum) {
            return;
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

const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @cImport(@cInclude("puff.h"));

pub export fn main() void {
    zigMain() catch unreachable;
}

fn puffAlloc(allocator: Allocator, input: []const u8) ![]u8 {
    // call once to get the uncompressed length
    var decoded_len: c_ulong = undefined;
    var source_len: c_ulong = input.len;
    const result = c.puff(c.NIL, &decoded_len, input.ptr, &source_len);

    if (result != 0) {
        return translatePuffError(result);
    }

    const dest = try allocator.alloc(u8, decoded_len);
    errdefer allocator.free(dest);

    // call again to actually get the output
    _ = c.puff(dest.ptr, &decoded_len, input.ptr, &source_len);
    return dest;
}

fn translatePuffError(code: c_int) anyerror {
    return switch (code) {
        2 => error.EndOfStream,
        1 => error.OutputSpaceExhausted,
        0 => unreachable,
        -1 => error.InvalidBlockType,
        -2 => error.StoredBlockLengthNotOnesComplement,
        -3 => error.TooManyLengthOrDistanceCodes,
        -4 => error.CodeLengthsCodesIncomplete,
        -5 => error.RepeatLengthsWithNoFirstLengths,
        -6 => error.RepeatMoreThanSpecifiedLengths,
        -7 => error.InvalidLiteralOrLengthCodeLengths,
        -8 => error.InvalidDistanceCodeLengths,
        -9 => error.MissingEOBCode,
        -10 => error.InvalidLiteralOrLengthOrDistanceCodeInBlock,
        -11 => error.DistanceTooFarBackInBlock,
        else => unreachable,
    };
}

pub fn zigMain() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    // Read the data from stdin
    const stdin = std.fs.File.stdin();
    const data = try stdin.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(data);

    // Try to parse the data with puff
    var puff_error: anyerror = error.NoError;
    const inflated_puff: ?[]u8 = puffAlloc(allocator, data) catch |err| blk: {
        puff_error = err;
        break :blk null;
    };
    defer if (inflated_puff != null) {
        allocator.free(inflated_puff.?);
    };

    var zig_error: anyerror = error.NoError;

    var fixed_reader: std.Io.Reader = .fixed(data);
    var decompress = std.compress.flate.Decompress.init(&fixed_reader, .raw, &.{});

    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();

    const inflated: ?[]u8 = blk: {
        _ = decompress.reader.streamRemaining(&aw.writer) catch |err| {
            zig_error = err;
            break :blk null;
        };
        break :blk aw.written();
    };

    if (inflated_puff == null or inflated == null) {
        if (inflated_puff != null or inflated != null) {
            std.debug.print("puff error: {}, zig error: {}\n", .{ puff_error, zig_error });
            return error.MismatchedErrors;
        }
    } else {
        try std.testing.expectEqualSlices(u8, inflated_puff.?, inflated.?);
    }
}

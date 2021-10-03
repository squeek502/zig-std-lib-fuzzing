const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @cImport(@cInclude("puff.h"));

pub export fn main() void {
    zigMain() catch unreachable;
}

fn puffAlloc(allocator: *Allocator, input: []const u8) ![]u8 {
    // call once to get the uncompressed length
    var decoded_len: c_ulong = undefined;
    var source_len: c_ulong = input.len;
    const result = c.puff(c.NIL, &decoded_len, input.ptr, &source_len);

    if (result != 0) {
        return translatePuffError(result);
    }

    var dest = try allocator.alloc(u8, decoded_len);
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

fn compareErrors(puff: anyerror, zig: anyerror) !void {
    const expected_error = switch (puff) {
        error.EndOfStream => error.EndOfStream,
        error.OutputSpaceExhausted => error.OutOfMemory,
        error.NoError => error.NoError,
        error.InvalidBlockType => error.InvalidBlockType,
        error.StoredBlockLengthNotOnesComplement => error.InvalidStoredSize,
        error.TooManyLengthOrDistanceCodes => error.BadCounts,
        error.CodeLengthsCodesIncomplete => error.InvalidTree,
        error.RepeatLengthsWithNoFirstLengths => error.NoLastLength,
        error.RepeatMoreThanSpecifiedLengths => error.InvalidLength,
        error.InvalidLiteralOrLengthCodeLengths => error.InvalidTree,
        error.InvalidDistanceCodeLengths => error.InvalidTree,
        error.MissingEOBCode => error.MissingEOBCode,
        error.InvalidLiteralOrLengthOrDistanceCodeInBlock => error.OutOfCodes,
        error.DistanceTooFarBackInBlock => error.InvalidDistance,
        else => unreachable,
    };

    if (puff == error.InvalidLiteralOrLengthOrDistanceCodeInBlock) {
        // puff combines InvalidFixedCode and OutOfCodes into one, so check for either
        std.debug.assert(zig == error.InvalidFixedCode or zig == expected_error);
    } else if (puff == error.EndOfStream) {
        // Zig's implementation returns OutOfCodes early in instances where puff gives
        // EndOfStream, so check for either
        std.debug.assert(zig == error.OutOfCodes or zig == expected_error);
    } else {
        // otherwise we can check for exact matches
        try std.testing.expectEqual(@as(anyerror, expected_error), zig);
    }
}

pub fn zigMain() !void {
    // Setup an allocator that will detect leaks/use-after-free/etc
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // this will check for leaks and crash the program if it finds any
    defer std.debug.assert(gpa.deinit() == false);
    const allocator = &gpa.allocator;

    // Read the data from stdin
    const stdin = std.io.getStdIn();
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

    const reader = std.io.fixedBufferStream(data).reader();
    var window: [0x8000]u8 = undefined;
    var inflate = std.compress.deflate.inflateStream(reader, &window);

    var zig_error: anyerror = error.NoError;
    var inflated: ?[]u8 = inflate.reader().readAllAlloc(allocator, std.math.maxInt(usize)) catch |err| blk: {
        zig_error = err;
        break :blk null;
    };
    defer if (inflated != null) {
        allocator.free(inflated.?);
    };

    if (inflated_puff == null or inflated == null) {
        compareErrors(puff_error, zig_error) catch |err| {
            std.debug.print("puff error: {}, zig error: {}\n", .{ puff_error, zig_error });
            return err;
        };
    } else {
        try std.testing.expectEqualSlices(u8, inflated_puff.?, inflated.?);
    }
}

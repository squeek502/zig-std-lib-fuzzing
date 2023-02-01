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

    // The current zstandard decompression implementation cannot handle anything that doesn't start with the 'magic number'
    // so just reject any input that doesn't
    // Note: would probably be better to just prepend the magic number but oh well
    if (data.len < 4) return;
    const frame_type = std.compress.zstandard.decompress.frameType(data) catch return;
    // There is no decode API that can handle anything besides the zstandard magic number, so
    // only continue if that's true
    if (frame_type != .zstandard) return;

    const verify_checksum = false;
    // TODO: Vary this? What is a good size to use?
    const window_size_max = 256 * 1024 * 1024; // 256 MiB
    const decoded = std.compress.zstandard.decompress.decodeZStandardFrameAlloc(allocator, data, verify_checksum, window_size_max) catch return {
        return;
    };
    defer allocator.free(decoded);
}

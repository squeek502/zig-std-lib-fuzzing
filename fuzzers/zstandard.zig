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

    const verify_checksum = false;
    // TODO: Vary this? What is a good size to use?
    const window_size_max = 256 * 1024 * 1024; // 256 MiB
    const result = std.compress.zstandard.decompress.decodeAlloc(
        allocator,
        data,
        verify_checksum,
        window_size_max,
    ) catch return;
    defer allocator.free(result);
}

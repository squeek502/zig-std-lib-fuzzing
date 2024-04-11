const std = @import("std");
const git = @import("git");

export fn cMain() void {
    main() catch unreachable;
}

comptime {
    @export(cMain, .{ .name = "main", .linkage = .strong });
}

pub fn main() !void {
    // Setup an allocator that will detect leaks/use-after-free/etc
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // this will check for leaks and crash the program if it finds any
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    // Read the data from stdin
    const stdin = std.io.getStdIn();
    const data = try stdin.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(data);

    // Index the packfile data
    var pack_file = std.io.fixedBufferStream(data);
    var index_data = std.ArrayList(u8).init(allocator);
    defer index_data.deinit();
    git.indexPack(allocator, &pack_file, index_data.writer()) catch return;
}

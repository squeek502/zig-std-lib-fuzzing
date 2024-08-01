const std = @import("std");

fn cMain() callconv(.C) void {
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
    const data = try stdin.readToEndAllocOptions(allocator, std.math.maxInt(usize), null, @alignOf(u8), 0);
    defer allocator.free(data);

    // Try to parse the data
    var tree = try std.zig.Ast.parse(allocator, data, .zig);
    defer tree.deinit(allocator);

    if (tree.errors.len != 0) {
        return;
    }

    // And render it back out
    const formatted = try tree.render(allocator);
    defer allocator.free(formatted);
}

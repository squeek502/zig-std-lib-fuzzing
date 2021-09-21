const std = @import("std");

fn cMain() callconv(.C) void {
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
    const allocator = &gpa.allocator;

    // Read the data from stdin
    const stdin = std.io.getStdIn();
    const data = try stdin.readToEndAllocOptions(allocator, std.math.maxInt(usize), null, @alignOf(u8), 0);
    defer allocator.free(data);

    // Try to parse the data
    var tokenizer = std.zig.Tokenizer.init(data);

    while (true) {
        const token = tokenizer.next();
        if (token.tag == .eof) break;
    }
}

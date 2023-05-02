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
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    // Read the data from stdin
    const stdin = std.io.getStdIn();
    const data = try stdin.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(data);

    // Try to parse the data
    var fbs = std.io.fixedBufferStream(data);
    var reader = fbs.reader();

    const rand_int = std.crypto.random.int(u64);
    var tmp_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const tmp_dirpath = std.fmt.bufPrint(&tmp_buf, "/tmp/zig-tar-fuzzing/{x}", .{rand_int}) catch unreachable;

    const tmpdir = try std.fs.cwd().makeOpenPath(tmp_dirpath, .{});
    defer std.fs.cwd().deleteTree(tmp_dirpath) catch {};

    std.tar.pipeToFileSystem(allocator, tmpdir, reader, .{}) catch {};
}

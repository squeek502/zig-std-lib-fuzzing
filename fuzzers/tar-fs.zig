const std = @import("std");

export fn cMain() void {
    main() catch unreachable;
}

comptime {
    @export(cMain, .{ .name = "main", .linkage = .strong });
}

var tmp_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
var tmp_dirpath: ?[]const u8 = null;

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    if (tmp_dirpath) |tmp_path| {
        std.fs.cwd().deleteTree(tmp_path) catch |err| {
            std.debug.print("failed to deleteTree during panic: {}\n", .{err});
        };
    }
    std.builtin.default_panic(msg, error_return_trace, ret_addr);
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
    var fbs = std.io.fixedBufferStream(data);
    const reader = fbs.reader();

    // Run tar parser and write untar data to the file system
    const rand_int = std.crypto.random.int(u64);
    tmp_dirpath = std.fmt.bufPrint(&tmp_buf, "/tmp/zig-tar-fuzzing/{x}", .{rand_int}) catch unreachable;

    const tmpdir = try std.fs.cwd().makeOpenPath(tmp_dirpath.?, .{});
    defer std.fs.cwd().deleteTree(tmp_dirpath.?) catch |err| {
        std.debug.print("failed to deleteTree during defer: {}\n", .{err});
        @panic("failed to deleteTree in defer");
    };
    std.tar.pipeToFileSystem(tmpdir, reader, .{ .mode_mode = .ignore }) catch {};
}

const std = @import("std");

export fn cMain() void {
    main() catch unreachable;
}

comptime {
    @export(&cMain, .{ .name = "main", .linkage = .strong });
}

pub fn main() !void {
    // Setup an allocator that will detect leaks/use-after-free/etc
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // this will check for leaks and crash the program if it finds any
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    // Read the data from stdin
    const stdin: std.fs.File = .stdin();
    const data = try stdin.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(data);
    var fbs: std.io.Reader = .fixed(data);

    var file_name_buffer: [std.fs.max_path_bytes]u8 = undefined;
    var link_name_buffer: [std.fs.max_path_bytes]u8 = undefined;
    // Run tar parser
    var tar: std.tar.Iterator = .init(&fbs, .{
        .file_name_buffer = &file_name_buffer,
        .link_name_buffer = &link_name_buffer,
    });
    var null_writer_buf: [1]u8 = undefined;
    var null_writer: std.io.Writer.Discarding = .init(&null_writer_buf);
    while (tar.next() catch null) |file| {
        switch (file.kind) {
            .directory => {},
            .file => {
                tar.streamRemaining(file, &null_writer.writer) catch |err| {
                    if (err == error.EndOfStream) break;
                    return err;
                };
            },
            .sym_link => {},
        }
    }
}

const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    try addFuzzer(b, "json");
    try addFuzzer(b, "tokenizer");
    try addFuzzer(b, "parse");
}

fn addFuzzer(b: *std.build.Builder, comptime name: []const u8) !void {
    // The object file
    const fuzz_obj = b.addObject("fuzz-" ++ name ++ "-obj", "fuzzers/" ++ name ++ ".zig");
    fuzz_obj.setBuildMode(.Debug);
    fuzz_obj.want_lto = true;

    // Setup the output name
    const fuzz_executable_name = "fuzz-" ++ name;
    const fuzz_exe_path = try std.fs.path.join(b.allocator, &[_][]const u8{ b.cache_root, fuzz_executable_name });

    // We want `afl-clang-lto -o path/to/output path/to/object.o`
    const fuzz_compile = b.addSystemCommand(&[_][]const u8{ "afl-clang-lto", "-o" });
    // Add the output path to afl-clang-lto's args
    fuzz_compile.addArg(fuzz_exe_path);
    // Add the path to the object file to afl-clang-lto's args
    fuzz_compile.addArtifactArg(fuzz_obj);

    // Install the cached output to the install 'bin' path
    const fuzz_install = b.addInstallBinFile(.{ .path = fuzz_exe_path }, fuzz_executable_name);

    // Add a top-level step that compiles and installs the fuzz executable
    const fuzz_compile_run = b.step("fuzz-" ++ name, "Build executable for fuzz testing '" ++ name ++ "' using afl-clang-lto");
    fuzz_compile_run.dependOn(&fuzz_compile.step);
    fuzz_compile_run.dependOn(&fuzz_install.step);

    // Compile a companion exe for debugging crashes
    const fuzz_debug_exe = b.addExecutable("fuzz-" ++ name ++ "-debug", "fuzzers/fmt.zig");
    fuzz_debug_exe.setBuildMode(.Debug);

    // Only install fuzz-debug when the fuzz step is run
    const install_fuzz_debug_exe = b.addInstallArtifact(fuzz_debug_exe);
    fuzz_compile_run.dependOn(&install_fuzz_debug_exe.step);
}

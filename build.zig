const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    try addFuzzer(b, "json");
    try addFuzzer(b, "tokenizer");
    try addFuzzer(b, "parse");
    try addFuzzer(b, "deflate");
}

fn addFuzzer(b: *std.build.Builder, comptime name: []const u8) !void {
    // The library
    const fuzz_lib = b.addStaticLibrary("fuzz-" ++ name ++ "-lib", "fuzzers/" ++ name ++ ".zig");
    fuzz_lib.setBuildMode(.Debug);
    fuzz_lib.want_lto = true;
    fuzz_lib.bundle_compiler_rt = true;

    // Setup the output name
    const fuzz_executable_name = "fuzz-" ++ name;
    const fuzz_exe_path = try std.fs.path.join(b.allocator, &.{ b.cache_root, fuzz_executable_name });

    // We want `afl-clang-lto -o path/to/output path/to/library`
    const fuzz_compile = b.addSystemCommand(&.{ "afl-clang-lto", "-o", fuzz_exe_path });
    // Add the path to the library file to afl-clang-lto's args
    fuzz_compile.addArtifactArg(fuzz_lib);

    // Install the cached output to the install 'bin' path
    const fuzz_install = b.addInstallBinFile(.{ .path = fuzz_exe_path }, fuzz_executable_name);

    // Add a top-level step that compiles and installs the fuzz executable
    const fuzz_compile_run = b.step("fuzz-" ++ name, "Build executable for fuzz testing '" ++ name ++ "' using afl-clang-lto");
    fuzz_compile_run.dependOn(&fuzz_compile.step);
    fuzz_compile_run.dependOn(&fuzz_install.step);

    // Compile a companion exe for debugging crashes
    const fuzz_debug_exe = b.addExecutable("fuzz-" ++ name ++ "-debug", "fuzzers/" ++ name ++ ".zig");
    fuzz_debug_exe.setBuildMode(.Debug);

    // Only install fuzz-debug when the fuzz step is run
    const install_fuzz_debug_exe = b.addInstallArtifact(fuzz_debug_exe);
    fuzz_compile_run.dependOn(&install_fuzz_debug_exe.step);
}

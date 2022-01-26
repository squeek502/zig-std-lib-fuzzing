const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    _ = try addFuzzer(b, "json", &.{});
    _ = try addFuzzer(b, "tokenizer", &.{});
    _ = try addFuzzer(b, "parse", &.{});
    _ = try addFuzzer(b, "deflate", &.{});
    _ = try addFuzzer(b, "deflate-roundtrip", &.{});

    const deflate_puff = try addFuzzer(b, "deflate-puff", &.{});
    for (deflate_puff.libExes()) |lib_exe| {
        lib_exe.addIncludeDir("lib/puff");
        lib_exe.addCSourceFile("lib/puff/puff.c", &.{});
        lib_exe.linkLibC();
    }

    const sin = try addFuzzer(b, "sin", &.{"-lm"});
    for (sin.libExes()) |lib_exe| {
        lib_exe.linkLibC();
    }

    // tools
    const sin_musl = b.addExecutable("sin-musl", "tools/sin-musl.zig");
    sin_musl.setTarget(.{ .abi = .musl });
    sin_musl.linkLibC();
    const install_sin_musl = b.addInstallArtifact(sin_musl);

    const tools_step = b.step("tools", "Build and install tools");
    tools_step.dependOn(&install_sin_musl.step);
}

fn addFuzzer(b: *std.build.Builder, comptime name: []const u8, afl_clang_args: []const []const u8) !FuzzerSteps {
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
    // Custom args
    fuzz_compile.addArgs(afl_clang_args);

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

    return FuzzerSteps{
        .lib = fuzz_lib,
        .debug_exe = fuzz_debug_exe,
    };
}

const FuzzerSteps = struct {
    lib: *std.build.LibExeObjStep,
    debug_exe: *std.build.LibExeObjStep,

    pub fn libExes(self: *const FuzzerSteps) [2]*std.build.LibExeObjStep {
        return [_]*std.build.LibExeObjStep{ self.lib, self.debug_exe };
    }
};

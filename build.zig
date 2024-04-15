const std = @import("std");

pub fn build(b: *std.Build) !void {
    _ = try addFuzzer(b, "json", &.{});
    _ = try addFuzzer(b, "tokenizer", &.{});
    _ = try addFuzzer(b, "parse", &.{});
    _ = try addFuzzer(b, "deflate", &.{});
    _ = try addFuzzer(b, "deflate-roundtrip", &.{});
    _ = try addFuzzer(b, "xz", &.{});
    _ = try addFuzzer(b, "zstandard", &.{});
    _ = try addFuzzer(b, "tar", &.{});
    _ = try addFuzzer(b, "tar-fs", &.{});

    const deflate_puff = try addFuzzer(b, "deflate-puff", &.{});
    for (deflate_puff.libExes()) |lib_exe| {
        lib_exe.addIncludePath(.{ .path = "lib/puff" });
        lib_exe.addCSourceFile(.{ .file = .{ .path = "lib/puff/puff.c" }, .flags = &.{} });
        lib_exe.linkLibC();
    }

    const sin = try addFuzzer(b, "sin", &.{"-lm"});
    for (sin.libExes()) |lib_exe| {
        lib_exe.linkLibC();
    }

    const xxhash = try addFuzzer(b, "xxhash", &.{});
    for (xxhash.libExes()) |lib_exe| {
        lib_exe.addIncludePath(.{ .path = "lib/xxhash" });
        lib_exe.addCSourceFile(.{ .file = .{ .path = "lib/xxhash/xxhash.c" }, .flags = &.{"-DXXH_NO_XXH3"} });
        lib_exe.linkLibC();
    }

    const zstandard_compare = try addFuzzer(b, "zstandard-compare", &.{});
    addZstd(&zstandard_compare);
    const zstandard_compare_alloc = try addFuzzer(b, "zstandard-compare-alloc", &.{});
    addZstd(&zstandard_compare_alloc);
    const zstandard_compare_stream = try addFuzzer(b, "zstandard-compare-stream", &.{});
    addZstd(&zstandard_compare_stream);

    if (b.option([]const u8, "zig-src", "Zig source root")) |zig_src_dir| {
        const markdown = b.createModule(.{
            .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ zig_src_dir, "lib/docs/wasm/markdown.zig" }) },
        });
        const markdown_parse = try addFuzzer(b, "markdown", &.{});
        for (markdown_parse.libExes()) |lib_exe| {
            lib_exe.root_module.addImport("markdown", markdown);
        }

        const patch_git_zig = b.addSystemCommand(&.{ "patch", "-u" });
        patch_git_zig.addFileArg(.{
            .cwd_relative = b.pathJoin(&.{ zig_src_dir, "src/Package/Fetch/git.zig" }),
        });
        patch_git_zig.addFileArg(.{ .path = "fuzzers/git.patch" });
        patch_git_zig.addArg("-o");
        const patched_git_zig = patch_git_zig.addOutputFileArg("git.zig");
        const git = b.createModule(.{
            .root_source_file = patched_git_zig,
        });
        const git_unpack = try addFuzzer(b, "git", &.{});
        for (git_unpack.libExes()) |lib_exe| {
            lib_exe.root_module.addImport("git", git);
        }
    }

    // tools
    const sin_musl = b.addExecutable(.{
        .name = "sin-musl",
        .root_source_file = .{ .path = "tools/sin-musl.zig" },
        .target = b.resolveTargetQuery(.{ .abi = .musl }),
    });
    sin_musl.linkLibC();
    const install_sin_musl = b.addInstallArtifact(sin_musl, .{});

    const zstandard_verify = b.addExecutable(.{
        .name = "zstandard-verify",
        .root_source_file = .{ .path = "tools/zstandard-verify.zig" },
        .target = b.resolveTargetQuery(.{}),
    });
    const install_zstandard_verify = b.addInstallArtifact(zstandard_verify, .{});

    const tools_step = b.step("tools", "Build and install tools");
    tools_step.dependOn(&install_sin_musl.step);
    tools_step.dependOn(&install_zstandard_verify.step);
}

fn addFuzzer(b: *std.Build, comptime name: []const u8, afl_clang_args: []const []const u8) !FuzzerSteps {
    const target = b.resolveTargetQuery(.{});

    // The library
    const fuzz_lib = b.addStaticLibrary(.{
        .name = "fuzz-" ++ name ++ "-lib",
        .root_source_file = .{ .path = "fuzzers/" ++ name ++ ".zig" },
        .target = target,
        .optimize = .Debug,
    });
    fuzz_lib.want_lto = true;
    fuzz_lib.bundle_compiler_rt = true;
    // Seems to be necessary for LLVM >= 15
    fuzz_lib.root_module.pic = true;

    // Setup the output name
    const fuzz_executable_name = "fuzz-" ++ name;
    const fuzz_exe_path = try std.fs.path.join(b.allocator, &.{ b.cache_root.path.?, fuzz_executable_name });

    // We want `afl-clang-lto -o path/to/output path/to/library`
    const fuzz_compile = b.addSystemCommand(&.{ "afl-clang-lto", "-o", fuzz_exe_path });
    // Add the path to the library file to afl-clang-lto's args
    fuzz_compile.addArtifactArg(fuzz_lib);
    // Custom args
    fuzz_compile.addArgs(afl_clang_args);

    // Install the cached output to the install 'bin' path
    const fuzz_install = b.addInstallBinFile(.{ .path = fuzz_exe_path }, fuzz_executable_name);
    fuzz_install.step.dependOn(&fuzz_compile.step);

    // Add a top-level step that compiles and installs the fuzz executable
    const fuzz_compile_run = b.step("fuzz-" ++ name, "Build executable for fuzz testing '" ++ name ++ "' using afl-clang-lto");
    fuzz_compile_run.dependOn(&fuzz_compile.step);
    fuzz_compile_run.dependOn(&fuzz_install.step);

    // Compile a companion exe for debugging crashes
    const fuzz_debug_exe = b.addExecutable(.{
        .name = "fuzz-" ++ name ++ "-debug",
        .root_source_file = .{ .path = "fuzzers/" ++ name ++ ".zig" },
        .target = target,
        .optimize = .Debug,
    });

    // Only install fuzz-debug when the fuzz step is run
    const install_fuzz_debug_exe = b.addInstallArtifact(fuzz_debug_exe, .{});
    fuzz_compile_run.dependOn(&install_fuzz_debug_exe.step);

    return FuzzerSteps{
        .lib = fuzz_lib,
        .debug_exe = fuzz_debug_exe,
    };
}

const FuzzerSteps = struct {
    lib: *std.Build.Step.Compile,
    debug_exe: *std.Build.Step.Compile,

    pub fn libExes(self: *const FuzzerSteps) [2]*std.Build.Step.Compile {
        return [_]*std.Build.Step.Compile{ self.lib, self.debug_exe };
    }
};

fn addZstd(fuzzer_steps: *const FuzzerSteps) void {
    for (fuzzer_steps.libExes()) |lib_exe| {
        lib_exe.addIncludePath(.{ .path = "lib/zstd/lib" });
        lib_exe.addCSourceFiles(
            .{
                .files = &.{
                    "lib/zstd/lib/decompress/huf_decompress.c",
                    "lib/zstd/lib/decompress/zstd_ddict.c",
                    "lib/zstd/lib/decompress/zstd_decompress.c",
                    "lib/zstd/lib/decompress/zstd_decompress_block.c",
                    "lib/zstd/lib/common/entropy_common.c",
                    "lib/zstd/lib/common/error_private.c",
                    "lib/zstd/lib/common/fse_decompress.c",
                    "lib/zstd/lib/common/pool.c",
                    "lib/zstd/lib/common/xxhash.c",
                    "lib/zstd/lib/common/zstd_common.c",
                    "lib/zstd/lib/common/debug.c",
                },
                .flags = &.{
                    "-DZSTD_DISABLE_ASM=1",
                    "-DDEBUGLEVEL=10", // Enable debug logging for easier debugging
                    // Some inputs trigger UBSAN but I can't reproduce the UB outside of the zig-built .exe.
                    // TODO: Investigate this more, just shutting off UBSAN is a cop-out.
                    "-fno-sanitize=undefined",
                    //"-DNO_PREFETCH=1", // Attempt to avoid unknown instruction (didn't seem to work though)
                    //"-DZSTD_NO_INTRINSICS=1", // Attempt to avoid unknown instruction (didn't seem to work though)
                },
            },
        );
        lib_exe.linkLibC();
    }
}

Fuzzing the Zig standard library
================================

A set of fuzzers for fuzzing various parts of the [Zig](https://ziglang.org/) standard library. See ['Fuzzing Zig Code Using AFL++'](https://www.ryanliptak.com/blog/fuzzing-zig-code/) for more information about the particular fuzzing setup used.

Current fuzzers:
- `tokenizer` which calls `std.zig.Tokenizer.next` until it gets an `eof` token
- `parse` which calls `std.zig.Ast.parse` and then `std.zig.Ast.render`
- `deflate` which calls `std.compress.flate.decompressor().reader().readAllAlloc()`
- `deflate-puff` which compares the results of `puff.c` to Zig's `std.compress.flate.decompressor`
- `deflate-roundtrip` which sends the input through `compressor`, then through `decompressor`, and then checks that the output is the same as the input
- `json` which calls `std.json.parseFromSlice`
- `sin` which calls `std.math.sin` and compares the result to libc's `sin`/`sinf`
- `xz` which calls `std.compress.xz.decompress`
- `xxhash` which compares the results of `xxhash.c` to Zig's `std.hash.xxhash` implementation
- `zstandard` which calls the `std.compress.zstd` `decode`, `decodeAlloc`, and `decompressStream` APIs.
- `zstandard-compare` which compares the results of the `zstd` reference implementation to Zig's `std.compress.zstd.decompress.decode` implementation
- `zstandard-compare-alloc` which compares the results of the `zstd` reference implementation to Zig's `std.compress.zstd.decompress.decodeAlloc` implementation
- `zstandard-compare-stream` which compares the results of the `zstd` reference implementation to Zig's `std.compress.zstd.decompressStream` implementation
- `tar` which uses `std.tar.iterator` to simulate an untar operation (but does not write to the filesystem)
- `tar-fs` which calls `std.tar.pipeToFileSystem` (and actually writes to the filesystem)

Non-`std` fuzzers (requires `-Dzig-src=/path/to/zig/sources`):
- `markdown` which calls Autodoc's `markdown.Parser` to parse an input line by line
- `git` which calls `git.indexPack` on a Git packfile
  - Requires a patch (`fuzzers/git.patch`) to be applied to upstream `git.zig` so I/O can be avoided.
  - To verify the contents of the input packfile (`small.pack`):

    1. Create a new empty Git repository (`git init`)
    2. `git unpack-objects <path/to/small.pack`
    3. `git fsck` -> note the "dangling commit" ID (which matches the commit checked out below)
    4. `git checkout 0a9b7c28d992347b3e237bb143c052b177ad388f`

Requires [AFL++](https://github.com/AFLplusplus/AFLplusplus) with `afl-clang-lto` to be installed.

## Building a fuzzer

Run `zig build fuzz-<fuzzer name>`, e.g. `zig build fuzz-tokenizer`

## Running a fuzzer

The instrumented fuzzer will be installed to `zig-out/bin/fuzz-<fuzzer name>`. You'll probably also need to run `mkdir outputs` (if you're planning on using `outputs` as an output directory) before fuzzing. Here's a simple example of running the `tokenizer` fuzzer:

```
afl-fuzz -i inputs/tokenizer -o outputs/tokenizer -x dictionaries/zig.dict -- ./zig-out/bin/fuzz-tokenizer
```

(the `-x` option is not necessary but using a dictionary is recommended if possible)

See [AFL++'s 'fuzzing the target' section](https://github.com/AFLplusplus/AFLplusplus/blob/stable/docs/fuzzing_in_depth.md#3-fuzzing-the-target) for more recommendations to improve fuzzing effectiveness (using multiple cores, etc).

## Debugging crashes

If a crash is found during fuzzing, the companion `fuzz-<fuzzer name>-debug` executable can be used to debug the crash. For example, for the `tokenizer` fuzzer, a stack trace could be gotten with:

```sh
$ ./zig-out/bin/fuzz-tokenizer-debug < 'outputs/tokenizer/default/crashes/id:000000,sig:06,src:000908+000906,time:117053,op:splice,rep:16'
thread 2730086 panic: index out of bounds
/home/ryan/Programming/zig/zig/build/lib/zig/std/zig/tokenizer.zig:408:34: 0x215131 in std.zig.tokenizer.Tokenizer.next (fuzz-tokenizer-debug)
            const c = self.buffer[self.index];
                                 ^
/home/ryan/Programming/zig/zig/build/lib/zig/std/zig/parse.zig:24:37: 0x20af60 in std.zig.parse.parse (fuzz-tokenizer-debug)
        const token = tokenizer.next();
                                    ^
...
```

Alternatively, the crash can be debugged via gdb:

```
gdb -ex 'set args < outputs/tokenizer/default/crashes/id:000000,sig:06,src:000908+000906,time:117053,op:splice,rep:16' ./zig-out/bin/fuzz-tokenizer-debug
```

Or valgrind:

```
valgrind ./zig-out/bin/fuzz-tokenizer-debug < 'outputs/tokenizer/default/crashes/id:000000,sig:06,src:000908+000906,time:117053,op:splice,rep:16'
```

[`zigescape`](https://github.com/squeek502/zigescape) can also be used to convert inputs into string literals for the creation of test cases (preferrably after using `afl-tmin` to minimize the input).

## Bugs found / fixed

### `std.zig.Tokenizer`

- https://github.com/ziglang/zig/pull/9808
- https://github.com/ziglang/zig/pull/9809

### `std.compress.flate`

- [https://github.com/ianic/flate/issues](https://github.com/ianic/flate/issues?q=is%3Aissue+is%3Aclosed+author%3Asqueek502) (a bunch of stuff before it was [submitted as a PR](https://github.com/ziglang/zig/pull/18923))

<details>
<summary>obsoleted Deflate implementations</summary>

### `std.compress.deflate` (second version of Deflate)

- https://github.com/ziglang/zig/pull/10552#issuecomment-1019194395

### `std.compress.deflate` (first version of Deflate)

- https://github.com/ziglang/zig/pull/9849
- https://github.com/ziglang/zig/pull/9860
- https://github.com/ziglang/zig/pull/9880

</details>

### `std.math`

- `sin`: https://github.com/ziglang/zig/issues/9901

### `std.compress.xz`

- https://github.com/ziglang/zig/issues/14500

### `std.compress.zstandard`

- https://github.com/ziglang/zig/pull/14394 (a whole bunch of stuff during the PR process)

### `std.tar`

- https://github.com/ziglang/zig/pull/19038

### In upstream/third-party projects

#### [`facebook/zstd`](https://github.com/facebook/zstd)

- https://github.com/facebook/zstd/issues/3506
- https://github.com/facebook/zstd/issues/3507
- https://github.com/facebook/zstd/issues/3508
- https://github.com/facebook/zstd/issues/3482

---

## Other tools/fuzzers

### `zstandard-verify`

Requires the `decodecorpus` tool from [zstd](https://github.com/facebook/zstd/tree/dev/tests#decodecorpus---tool-to-generate-zstandard-frames-for-decoder-testing) and the `zstandard-verify` tool from this repo (can be built with `zig build tools`). Run the following command to use it to continuously test the `zstandard` Zig decompressor with generated compressed .zst files:

```
./tools/zstandard-decodecorpus.sh /path/to/decodecorpus ./zig-out/bin/zstandard-verify
```

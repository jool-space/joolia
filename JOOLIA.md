# joolia: native bootstrap, Core, and Base foundation

Launch the fork with `./usr/bin/joolia --startup-file=no`. The banner, REPL
prompt, command-line labels, and `versioninfo()` identify it as joolia. The
`julia` executable, ABI names, environment variables, package identities, and
`.jl` loading conventions remain available. `.jo` is the leading candidate for
a future source extension; existing Julia URLs are retained.

The default user depot is `~/.joolia`: packages, registries, compiled caches,
environments, `config/startup.jl`, and `logs/repl_history.jl` live there. The
default global project is `~/.joolia/environments/v1.14/Project.toml`.
`JULIA_DEPOT_PATH` still overrides the depot; bundled system depots retain
their existing paths. Existing `~/.julia` contents are not migrated.

After editing REPL sources, run `make -j8` before checking an interactive
launch. Interactive startup loads the bundled REPL cache without source
staleness checks; `using REPL` in a script can load a different, updated cache
and does not verify the interactive banner.


This worktree changes collection positions and dimension arguments to zero origin,
while retaining inclusive colon ranges and column-major storage. The native
runtime and Julia compiler bootstrap run, and a native compiler-only image
(`usr/lib/julia/basecompiler.so`) is available. The normal build now executes
Base and all default standard-library sources. The default `sys.so` and source
cache now build, and ordinary command-line execution starts without `-J`.
The normal interactive LineEditREPL starts with the default image and ordinary
compiled-module loading. Pkg can instantiate local projects and run package tests.
A printed "Sysimage built" summary alone is not artifact validation.

JuliaSyntax's existing Expr-conversion test file passes 541 assertions in each
of interpreted and compiled execution. This covers both direct tree conversion
and SyntaxNode conversion. Standard-library loading does not imply that their
full APIs have been ported. Dense LinearAlgebra products have focused coverage;
factorizations, sparse numerical operations, much of JuliaLowering, untested
REPL interactions, and ecosystem packages still need migration or verification. See [the port notes](JOOLIA_BASE_PORT.md) for precise checkpoints.

## Base foundation checkpoint

```sh
make -j8 test-base-foundation
```

This loads the actual `Base_compiler.jl` prefix before compiler inclusion and
runs 138 integration checks in both interpreted and native compiled modes,
with bounds checks and no Julia inference module. Coverage includes tuple and
SimpleVector positions, generated constructors, atomic macros, inclusive ranges,
zero-origin axes, dimensions and column-major strides, narrow indices, vector
growth/copying, pointers, reflection, identity collections, packed arrays and
bitsets. Optimized Bool-to-bit packing is retained and tested for aligned and
unaligned copies.

See [Base port boundaries and audit notes](JOOLIA_BASE_PORT.md). Passing this
checkpoint does not certify every method in the loaded files: several higher-level
array routines depend on later Base files and still need migration and tests.
The real bootstrap completes compiler inference and activation and emits a
native compiler-only image. The `test-compiler-foundation` and
`test-strings-foundation` targets also exercise helpers before inference
activation; their last verified counts are 139 and 251 per mode, respectively.
The string checks include multibyte character repetition at buffer boundaries.
The `test-io-foundation` target has 26 checks per mode using explicit cancellation
arguments where required. Revise still needs its external dependencies ported; doctests have not been
verified. The default image itself
now passes the 138 Base and 251 string foundation checks in both execution
modes, including Cartesian indexing, without replacement Base methods.

## Build and test without Base

Build the native runtime and execute the Core-only branch of `test/core.jl`:

```sh
make -j8 test-core-bootstrap
```

The target runs once with `--compile=min` and once with `--compile=all`, both with
bounds checks enabled. Both runs assert that `Main.Base` is absent before and
after testing. Compilation uses the native bootstrap compiler, without Julia's
inference/optimization module. Passing these tests does not establish correctness
of every Julia-written compiler path.

For code-generation development, use this local `Make.user` setting:

```make
LLVM_ASSERTIONS=1
```

To execute a separate Core-only script, run from `base/`:

```sh
../usr/bin/julia --startup-file=no --compile=all \
    --output-ji /tmp/joolia-unused.ji /absolute/path/to/script.jl
```

`--output-ji` without an explicit system image selects Julia's existing native
bootstrap path: initialize native types and builtins, then load `boot.jl`.
The script should explicitly exit after its module closes, before the runtime
attempts to serialize an image:

```julia
baremodule Example
    Core.isdefined(Core.Main, :Base) && throw(ErrorException("Base was loaded"))
    t = (10, 20)
    getfield(t, 0) === 10 || throw(ErrorException("wrong tuple origin"))
    a = Array{Int,2}(undef, (2,3))
    Core.arrayset(false, a, 42, 0, 1)
    Core.println(Core.arrayref(false, a, 2)) # 42: column-major linear index
end
ccall(:jl_exit, Core.Cvoid, (Core.Int32,), Core.Int32(0))
```

A `baremodule` only controls imports; by itself it does not prevent Base from
being loaded by a system image. Generic `getindex` / bracket indexing, iteration,
string indexing, and generated default constructors belong to the later Base
port. Core-only user structs should define explicit inner constructors.

## Boundary contract

| Interface | Convention |
| --- | --- |
| Integer `getfield`, `setfield!`, `fieldtype`, `isdefined`, and atomic field operations | First field is 0; symbolic field access is unchanged |
| `Core._svec_ref` | First element is 0 |
| `Core.memoryref` / `memoryrefnew` | Zero-based element position from memory, or signed element displacement from a reference |
| `Core.memoryrefoffset` | Zero-based element offset from the underlying memory origin |
| `Core.Intrinsics.pointerref` / `pointerset` | Element offset 0 accesses the pointer itself; alignment argument is unchanged |
| `Core.arraysize(A, d)` | First dimension is 0; dimensions beyond the rank have size 1; negative dimensions fail |
| `Core.arrayref`, `const_arrayref`, `arrayset` | Zero-based linear/Cartesian scalar access, column-major storage; `inbounds=true` permits skipping bounds checks |
| `jl_get_field_offset` | First field is 0; result is still a byte offset |
| Native parser offsets and errors | Zero-based code-unit offsets, with an after-end boundary |
| Struct field-attribute metadata | Zero-based field positions for atomic/const attributes |

Lengths, ranks, alignment, and dimension sizes are counts, not indices. A
256-element memory accepts `UInt8(255)` through `Core.memoryref`, while its length
remains an `Int`. Native C array/field accessors that already use zero-based
indices retain that convention. Their bounds errors now report those indices.

The Scheme lowerer emits zero-based field accesses for typegroups, constructors,
destructuring, and opaque closure captures, and zero-based dimension arguments
for `begin`/`end` lowering, including preceding splats. Its private counters and
SSA/slot/branch identifiers retain their existing internal representation; they
are not collection-position APIs. LLVM ABI argument numbering and internal union
tags are also separate conventions.

The scalar Core array helpers operate independently of Base. The deprecated
`Core._apply` uses Core's iteration hook during bootstrap and Base's hook once
Base exists. The built-in apply machinery already handles tuples and arrays;
this does not supply Base's generic iteration library.

## Native validation

Initialize analysis tools once, then analyze the changed translation units:

```sh
make -C src install-analysis-deps
make -C src analyze-ast analyze-builtins analyze-datatype analyze-rtutils \
    analyze-runtime_intrinsics analyze-codegen analyze-subtype -j8 --output-sync
```

`cgutils.cpp` and `intrinsics.cpp` are included by `codegen.cpp` and are covered by
its analysis. The targets run Clang's static analyzer, GC rooting checker,
safety checker, and clang-tidy. The normal Base/Test/Revise test runner requires a
ported system image; use `test-core-bootstrap` for this stage.

## Next integration boundary

The remaining Base and Compiler code must migrate their explicit tuple/field/memory positions,
axis and dimension conventions, and inference rules together. JuliaLowering must
also adopt the native lowerer's zero-based field-attribute and generated-index
contract. Existing upstream system images and package images must not be used
with this runtime.

The proposed mixed-delimiter ranges (`[0:16)` and `(0:16]`) are a separate future
parser change. Inclusive colon ranges and existing vector/tuple/grouping syntax
have not been changed here. The source-file extension is still undecided.

`make -C test dict-foundation` additionally passes 17 persistent checks per
mode for zero-origin hash storage, UInt8 keys, collisions, and deletion. Set reuse and UInt8 key coverage are included; WeakKeyDict still needs concurrency dependencies.

## Running tests

The September 17 18:12 normal image passes the full build (108 stdlib precompile
configurations), fifteen complete stdlib suites (8,099,856 assertions plus 95
expected broken cases), Pkg's miscellaneous/lifecycle suite (168 parent and five
passing child assertions, plus intentional child-failure propagation), and 4,265
focused checks in each compilation mode. A real styled package REPL verifies
`add Statistics`, loading Statistics, mean and variance in a temporary project.
The focused checks include independent numerical references and empty floating
range endpoints. Restart existing REPL sessions to use the rebuilt image.


The standard upstream runner works with the built executable:

```sh
JULIA_TEST_FAILFAST=1 JULIA_CPU_THREADS=4 ./usr/bin/joolia \
  --startup-file=no --check-bounds=yes test/runtests.jl \
  Test Dates Base64 Printf CRC32c Unicode UUIDs TOML Logging SHA Tar \
  FileWatching Serialization Markdown InteractiveUtils
```

Run Pkg's miscellaneous tests, including a local project that exercises
`Pkg.instantiate` and `Pkg.test` with both passing and deliberately failing tests:

```sh
JULIA_TEST_FAILFAST=1 ./usr/bin/joolia --startup-file=no --check-bounds=yes \
  -e 'using Pkg, Test; include(joinpath(pkgdir(Pkg), "test", "misc.jl"))'
```

Build first, then launch tests in fresh processes. Replacing the system image
while a test process is launching child processes can mix incompatible package
caches. Existing REPL sessions must be restarted after rebuilding.

The `test-revise-*` targets remain blocked in unported external JuliaInterpreter
and LoweredCodeUtils dependencies. Registry download, verification, and dependency
installation now work; the ordinary runner above does not require Revise.
These checks do not certify every stdlib or ecosystem package. See the latest
coverage checkpoint in [the port notes](JOOLIA_BASE_PORT.md).

## External stdlib sources

External stdlibs are tracked as squashed Git subtrees under `stdlib/Name`.
Edit and commit them directly; the former patch-stack workflow is retired.
See [the vendoring guide](stdlib/VENDORED.md) for upstream updates and provenance.

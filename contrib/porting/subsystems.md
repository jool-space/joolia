# Subsystem porting map

Use the entries relevant to the batch. These are inspection starting points,
not a claim that every method in a listed file is already ported or tested.

## Core, native runtime and bootstrap

Start at base/boot.jl, src/builtins.c, src/datatype.c, src/runtime_intrinsics.c,
src/genericmemory.c, src/array.c and the compiler's corresponding transfer rules.
Integer field operations start at zero; symbolic field names retain their meaning.
Check getfield, setfield!, fieldtype, isdefined, const/atomic metadata and generated
constructors together. Undefined fields and invalid positions must retain their
error/undefined-value behavior; shifting the valid first field does not make
all field-like IDs interchangeable.

Core-only code cannot assume that ordinary Base iteration, arithmetic, range
construction, error formatting or Test is available. Follow the existing use of
Core intrinsics. Bootstrap tests deliberately run before later layers are loaded.
A method that works after a complete sysimage loads can still break bootstrap.

C accessors, LLVM structure members and ABI argument numbers often already use
zero-based positions. Existing `n - i - 1` reverse-copy offsets are not evidence
of a one-based public contract. Check element versus byte counts, overlap,
zero-length copies, typetag storage and GC ownership before modifying native code.
Fresh-object and deletion barriers are correctness requirements independent of
index origin. Consult the native-analysis skill for changed translation units.

## Tuples, expressions and generated code

Inspect base/tuple.jl, base/namedtuple.jl, base/ntuple.jl, base/expr.jl, the
Scheme lowerer under src/flisp, and the syntax/lowering libraries involved.

Tuple/named-tuple numeric positions and Expr.args positions start at zero.
`ntuple` passes zero-origin positions to its callback; `enumerate` starts at zero.
Destructuring `(a,b) = result` expresses ordering without numeric positions, but
replacing an access with destructuring is appropriate only when arity is known.
Varargs, empty tuples and dynamic-length tuple fallbacks require independent checks.
A type parameter N describing tuple length is still a count.

Example: an old single-function permutation `p = (1,)` must become `(0,)` if
its values index `fs`. Porting only `p[i]` leaves the nested `fs[p[i]]` wrong.
For multiple functions check that randperm/invperm use the same value convention.
Do not assume every integer tuple is an index tuple: sizes and polynomial
coefficients are values, and native IDs may use another encoding.

Macros can fail before any ordinary function runs. Trace AST production and
consumption for interpolation, splats, generated methods and `begin`/`end`.
A changed Expr.args access may require corresponding lowerer and inference work.
Preserve ordinal names such as Fix1/Fix2 while inspecting numeric Fix{N} positions.

## Arrays, axes, dimensions and Cartesian indexing

Inspect base/abstractarray.jl, base/array.jl, base/multidimensional.jl,
base/cartesian.jl, base/subarray.jl, base/reshapedarray.jl and relevant specializations.

For a conventional m-by-n matrix, dimensions are 0 and 1, its shape is `(m,n)`,
and strides are 1 and m. The zero-origin linear offset of `(i,j)` is `i + m*j`.
Do not change storage to row-major. Dimensions past the rank have singleton size
where the existing API specifies it; negative dimension selectors are invalid.
A 0-D array has an empty shape and one element. An empty 2-D array can have shape
`(0,n)` with zero elements; it is not a 0-D array.

Check dimension selectors embedded in Val parameters, reductions, mapslices,
permutedims, cat, dropdims, find operations and broadcast shape logic. A tuple
holding dimensions has both tuple positions and dimension values to classify.
Do not decrement dimensions twice when a generated helper already translates them.

Not all AbstractArrays have conventional axes. eachindex, axes, firstindex and
lastindex must agree with the algorithm's linear/Cartesian indexing style.
Views, IdentityUnitRange and Slice may deliberately preserve nonzero axes.
Check parent/view coordinate conversion, dropped singleton axes, trailing axes,
Boolean masks, bit-packed array slices, empty selections and aliased destinations.

## Ranges and numeric boundaries

Inspect base/range.jl and base/twiceprecision.jl along with callers that construct
range-based axes. Keep range values, range positions and endpoint conventions
separate. `0:4` denotes five values; `(10:14)[0]` is 10. `OneTo(n)` retains 1:n
as values; `ZeroTo(n)` describes the conventional zero-origin count axis.

Changing a storage-origin adjustment in StepRangeLen can corrupt last(r) without
changing length(r). Check length, isempty, first, last, step, display and collect
together. This caught the empty floating range whose display misleadingly looked
nonempty. An empty collection may still have meaningful stored endpoint values;
do not manufacture them from an unchecked first element access.

Cover positive and negative steps, singleton ranges, zero length, fractional
steps, large endpoints and unsigned inputs. Avoid forming UInt8(256) merely to
terminate iteration over 256 elements whose last valid position is UInt8(255).
Use a count/state representation capable of expressing termination. Inclusive
endpoints do not justify silently changing colon to Python-style slicing.

## Memory, pointers, IO and strings

Inspect base/genericmemory.jl, base/pointer.jl, base/iobuffer.jl and base/strings.
MemoryRef construction from Memory uses a zero-origin element position; movement
from an existing reference uses a signed relative displacement. Distinguish that
from pointer byte arithmetic, typed-pointer element offsets and alignment.
A native API's reported offset may already be zero-based: avoid converting twice.

IOBuffer positions and region boundaries are byte offsets. Trace whether a range
is inclusive or a pair of half-open boundaries. A generic subtraction of one at
both ends produced the REPL's invalid Memory slice beginning at -1.
Check seek/start/end, mark/reset, truncate, take!, growth and overlapping writes.
An EOF result, after-end cursor and valid final byte are three distinct cases.

Strings index UTF-8 code units, not uniformly spaced characters. Inspect
codeunit, thisind, nextind, prevind, SubString, regex/search offsets and invalid
boundaries together. Do not implement "previous character" as `i-1`.
Test a leading multibyte character, an empty string and a final multibyte character.
State the sentinel contract for not-found explicitly; successful position zero
must not be mistaken for failure.

## Compiler, inference and lowering

Inspect Compiler/src plus the paired native lowering/codegen implementation.
SSA, slot and branch IDs keep their internal representation. In this port,
InstructionStream[id], IRCode[SSAValue(id)] and SSAUses[id] accept native IDs
starting at one and translate internally. Raw vectors containing those objects
start at zero. Instruction.idx is an ID, not a raw vector position.

Trace IDs through producers, wrapper accessors and backing storage. Never apply
an origin conversion both at the wrapper and its caller. Check no-use/empty
blocks, phi nodes, control-flow edges, use lists, renumbering, inlining and emitted
IR. LLVM argument numbers, aggregate element numbers and union tags have their
own contracts; a Julia tuple holding them still has zero-origin tuple positions.

When a builtin changes semantics, inspect its inference/type-function rules,
effect/nothrow reasoning, constant folding and emitted native code together.
A test that only exercises a constant index can miss a broken dynamic-index path.
Compare interpreted/minimal compilation with ordinary compilation; test both
valid position zero and invalid bounds. Never loosen inferred types to hide a
wrong transfer rule without explaining the lost precision and correctness need.

## LinearAlgebra, SparseArrays and foreign libraries

Inspect dimensions and storage contracts before any BLAS/LAPACK call. For
matrix multiplication, compare size(A,1) with size(B,0); these are dimensions,
while the resulting sizes are counts. Keep leading dimensions and increments
in the units required by the foreign routine. A dense smoke product does not
certify transposed/adjoint products, factorizations or sparse methods.

Fortran pivot values or sparse-library indices may be one-based even when the
Julia container storing them begins at zero. Convert only at an explicit boundary,
with round-trip tests. Audit every consumer before changing pivot values.
CSC column pointers delimit spans; their values, their container positions,
row indices and library index-base flags are different quantities. Check empty
columns, zero nonzeros, singleton matrices and final column-pointer sentinels.
Do not blanket-convert foreign arrays or alter the ABI.

## REPL, styling and package management

Inspect stdlib/REPL and stdlib/Pkg, including Pkg/ext/REPLExt. Distinguish input
byte positions, cursor columns, rendered cell widths, prompt widths and indentation.
A visible terminal column is not an index into the input buffer. Tabs, Unicode
width and continuation lines need attention. Short input is valuable: one tuple
entry or one package argument exposes an invalid [1] that a longer value hides.

Tuple-valued delimiter metadata, completion regions and display-size results
must use the current tuple origin. Exercise the styled terminal and asynchronous
hints; a script using REPL internals can miss the actual UI path. The existing
PTY test covers backspace after one to three spaces and package completion.

Pkg resolver vertices, version positions, adjacency lists, graph sentinels and
bit masks must agree. Test dependencies present only in newer versions, not just
successful parsing of a package name. For deduplicating an adjacency entry,
write down whether continue means "already present" or "missing"; switching an
index origin must not reverse this logic.

Option enums are values. malloc_log already selects zero-origin entries in the
("none","user","all") tuple; adding one enabled unexpected .mem files.
Test propagation across process boundaries. Preserve package UUIDs, versions,
manifest schema and registry format. Never edit installed ecosystem packages or
use the developer's ~/.julia or ~/.joolia depot to make a CI test pass.

Interactive startup and pkg> load bundled caches without ordinary freshness
checks. Rebuild and restart before verifying. Successful `using Pkg` in a script
is not proof that the bundled package REPL contains the same source changes.

## Vendored stdlibs and upstream-owned metadata

Sources live in tracked stdlib/Name subtrees. Edit them there; never recreate
stdlib/*.patch files, edit usr/share copies, or modify stale Name-SHA directories.
The .version files express Julia's recommendation, not our current build input.
Record the recommended SHA and the actually imported git-subtree-split SHA.
Choose exact subtree revisions explicitly; do not automatically fetch each
library's latest branch. Review and test the imported changes before advancing
provenance.

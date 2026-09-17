# Joolia porting audit — September 17

Read-only audit of the current built fork. This report records confirmed failures;
it does not claim they have been repaired. Three gpt-5.6-luna agents audit
REPL/Pkg, numerical libraries, and less-tested stdlibs; the main agent checks
shared Base helpers and SharedArrays. Probes use startup-file=no and bounds checks.

## Coverage baseline

Fifteen complete stdlib suites pass: Test, Dates, Base64, Printf, CRC32c, Unicode,
UUIDs, TOML, Logging, SHA, Tar, FileWatching, Serialization, Markdown and
InteractiveUtils. Last aggregate: 8,099,856 pass and 95 expected broken; Dates
accounts for most assertions. Separately, 4,265 focused assertions pass in each
compilation mode, plus the subsequent 56 Pkg completion-region/hint regressions.
All 108 build/precompile configurations pass. These are not whole-API coverage
percentages. See JOOLIA_BASE_PORT.md for test logs and known failures.

## Confirmed shared Base and SharedArrays failures

### B1 — Tuple replacement can silently replace the wrong element

Source: `base/set.jl:1023`, `_replace(f, t::Tuple, count)` uses `t[1]` as the
head while recursing through `tail(t)`. It also throws when reaching a singleton.

```julia
replace((10,20), 20=>99; count=1)  # actual (99,20), expected (10,99)
replace(identity, (10,20))         # BoundsError on singleton index1; expected (10,20)
```

Confirmed under normal compilation and compile=min; upstream nightly provides
the expected results. Prioritize this silent wrong-result path.

### B2 — Tuple allequal skips position zero and reads past the end

Source: `base/set.jl:664` and `:672`. Both the generated small-tuple path and
large-tuple loop retain one-origin accesses.

```julia
allequal((7,7))                 # BoundsError at tuple index2; expected true
allequal(ntuple(_ -> 7, 33))     # BoundsError at tuple index33; expected true
```

Confirmed under normal compilation and compile=min. A fix needs both generated
and fallback paths, and tests for unequal tuples plus both sides of the size32
specialization threshold. Logs: `/tmp/joolia-audit-base-tuples{,-min}.log`.

### S1 — SharedArrays explicit process selection reads the second process

Source: `stdlib/SharedArrays/src/SharedArrays.jl:417`, `shared_pids` uses `pids[1]`.

```julia
using SharedArrays, Distributed
SharedArray{Int}((2,2); pids=[myid()])
# BoundsError: 1-element Vector{Int64} at index [1]
```

Expected: a local 2x2 shared matrix. Process IDs remain their protocol values;
the position in the vector holding those IDs is zero-origin.
Log: `/tmp/joolia-audit-sharedarrays.log`.

### S2 — SharedArrays partition arithmetic generates negative indices

Source: `stdlib/SharedArrays/src/SharedArrays.jl:422`, `range_1dim`, called from
`init_loc_flds` at line446 with the zero-origin result of `findfirst`.

```julia
using SharedArrays
SharedArray{Int}((2,2))
# BoundsError: 2x2 Matrix{Int64} at index [-3:0]
```

Expected: successful construction with the local process owning linear positions
0:3. Audit the partition formulas together with the nonparticipant sentinel;
`init_loc_flds` still stores pidx=0 for nonparticipation, colliding with the first
valid process-vector position. The sentinel observation is source evidence;
the default constructor's negative range is dynamically reproduced.
Log: `/tmp/joolia-audit-sharedarrays-default.log`.

### B3 — Single-input asyncmap fails before starting work

Source: `base/asyncmap.jl:77` selects `c[1]` from a singleton varargs tuple.

```julia
asyncmap(identity, [10,20])  # BoundsError on Tuple{Vector{Int64}} at index1
```

Expected `[10,20]`. The less-tested-stdlib agent also encountered this shared
failure through Distributed.pmap; do not count that as a separate Distributed
root cause. Direct root repro: `/tmp/joolia-audit-asyncmap.log`.

## Confirmed numerical-library failures

The numerical agent's findings below were independently reproduced by the main
agent. Log: `/tmp/joolia-audit-reviewed-numerics.log`.

### N1 — Diagonal extraction silently returns wrong elements; diagonal construction fails

Source: `LinearAlgebra/src/dense.jl:287-302,326,402-407` in the fetched stdlib.
`diagind(A,...)` still requests dimensions1/2 and builds linear indices starting
at1; its Cartesian path also starts at (1,1).

```julia
using LinearAlgebra
A = [1 2; 3 4]
diag(A)           # actual [3], expected [1,4]
diag(A, 1)        # actual Int[], expected [2]
collect(diagind(A)) # actual [1], expected [0,3]
diagm(0 => [1,2]) # BoundsError: 1-element StepRange at index1
```

Treat diagm as another exposed path of the diagonal-family contract, not simply
an enumerate bug: enumerate's zero-origin position is appropriate for a
zero-origin range. Here diagind has already computed an incorrectly short range.
Cover rectangular matrices, both diagonal directions, Cartesian indices, and
empty diagonals when repairing this family.

### N2 — Dense LU cannot unpack its LAPACK result

Source: `LinearAlgebra/src/lu.jl:90-93`, tuple accesses still use one-origin positions.

```julia
using LinearAlgebra
lu([1.0 2; 3 4]) # BoundsError at index3 of (matrix,pivots,info)
```

Expected a valid factorization. Fixing the first accessor is not proof that pivot
positions, factor reconstruction, or solves work; verify those separately.

### N3 — Dense SVD reads past the workspace query buffer

Source: `LinearAlgebra/src/lapack.jl:1715-1722`, singleton workspace `work[1]`.

```julia
using LinearAlgebra
svd([1.0 2; 3 4]) # BoundsError: 1-element Vector{Float64} at index1
```

Expected a valid SVD. Distinguish Julia buffer positions from LAPACK's workspace
sizes, query sentinel and other native ABI values.

### N4 — Dense-to-CSC conversion fails on an ordinary 2x2 matrix

Source: `SparseArrays/src/sparsematrix.jl:915-933` still uses dimensions/axes1/2,
`colptr[1]`, and a storage counter starting at1. Validation at lines141-151 also
retains one-origin vector accesses.

```julia
using SparseArrays
sparse([1 2; 3 4]) # ArgumentError: 3 == colptr[1] != 1
```

Expected successful conversion preserving all four values. Audit the whole
constructor/validator/storage contract, including native-library boundaries;
changing only the reported colptr check would conceal earlier mistakes.

### N5 — shuffle changes OneTo's values

Source: `stdlib/Random/src/misc.jl:289` specializes shuffle(OneTo) as randperm.
Joolia's randperm returns zero-origin permutation values, while OneTo retains
its explicit one-origin values.

```julia
using Random
collect(Base.OneTo(5))                              # [1,2,3,4,5]
sort(shuffle(MersenneTwister(1), Base.OneTo(5)))      # [0,1,2,3,4]
```

Expected the same values, merely permuted. This is a silent value-contract bug,
not a disagreement over array indices. Ordinary arrays/ranges did not exhibit
this issue in the agent's selected probes; that is not full Random coverage.

## Confirmed REPL failures

Main-agent repro log: `/tmp/joolia-audit-reviewed-repl.log`.

### R1 — TerminalMenus rendering, default cursor and selection bounds disagree with zero-origin options

Sources: `stdlib/REPL/src/TerminalMenus/AbstractMenu.jl:181-188,214-219,347-350`
and the RadioMenu writeline accessors. Rendering already explains the known
Pkg compat-editor failure. The audit additionally confirmed the default selection.

```julia
using REPL
T = REPL.TerminalMenus
m = T.RadioMenu(["a","b","c"]; warn=false)
T.printmenu(IOBuffer(), m, 0; init=true) # BoundsError at option index3
term = REPL.Terminals.TTYTerminal("dumb", IOBuffer(UInt8[0x0d]), IOBuffer(), IOBuffer())
T.request(term, m; suppress_output=true) # Enter selects position1; expected0
```

The agent also observed that explicit cursor3 is accepted for three options.
Repair navigation, pagination, cursor validation and returned positions together;
process IDs, key characters and menu positions are different contracts.

### R2 — MultiSelect's select-all omits the first option and includes an invalid one

Source: `stdlib/REPL/src/TerminalMenus/MultiSelectMenu.jl:123`.

```julia
m = REPL.TerminalMenus.MultiSelectMenu(["a","b","c"]; warn=false)
REPL.TerminalMenus.keypress(m, UInt32('a'))
sort(collect(m.selected)) # [1,2,3], expected [0,1,2]
```

Group this with the TerminalMenus work package, but retain a separate regression.

### R3 — Multi-character LaTeX sub/superscripts produce no completion

Source: `stdlib/REPL/src/REPLCompletions.jl:977-980,992-996`: keys use k[1]
(the prefix marker) instead of the character after the two-character prefix;
the replacement slice also includes a prefix character.

```julia
C = REPL.REPLCompletions
for s in ("\\_12", "\\^ab", "\\^12")
    C.bslash_completions(s, lastindex(s))
end
```

Each returns an empty completion vector. Expected completions are respectively
`₁₂`, `ᵃᵇ`, `¹²`. Exact single-character forms may succeed through another lookup
path, so single-character tests alone miss this failure.

## Confirmed less-tested stdlib failures

Main-agent repro log: `/tmp/joolia-audit-reviewed-other.log`.

### O1 — DelimitedFiles cannot read a small CSV

Source: fetched `DelimitedFiles/src/DelimitedFiles.jl:281`, `DLMOffsets` writes
`offsets[1]` into a one-element vector. Related storage counters also need review.

```julia
using DelimitedFiles
readdlm(IOBuffer("1,2\n3,4\n"), ',') # BoundsError at offsets[1]
```

Expected a 2x2 numeric matrix containing the four supplied values.

### O2 — LibGit2 index and tree wrappers still translate from one-origin positions

Sources: `stdlib/LibGit2/src/index.jl:203-226` and `tree.jl:131-141`.
In a nonempty repository, using read-only handles:

```julia
using LibGit2
r = GitRepo(pwd())
idx = GitIndex(r)
t = GitTree(r, "HEAD^{tree}")
idx[0] # InexactError converting -1 to UInt64 (i-1 passed to native API)
t[0]   # BoundsError (requires i >= 1, then subtracts1)
LibGit2.findall("AGENTS.md", idx) # 21 in this checkout; git index position is20
# Close t, idx and r after use.
```

Expected zero to select the first native entry, and findall to report its
zero-origin position. Native libgit2 already numbers these entries from zero;
the Julia wrappers' subtraction/addition and bounds checks are the mismatch.
The exact AGENTS.md position depends on the repository; verify against git
ls-files ordering rather than treating20 as a universal fixture.

## Confirmed inherited upstream issue, not a Joolia off-by-one

Pkg's `REPLExt.complete_installed_apps` calls
`extract_specified_names(arguments, partial)`, but only the one-argument helper
exists (`ext/REPLExt/completions.jl:63,216`). The agent reproduced a MethodError.
The main agent checked the pristine pinned Pkg archive and confirmed the same
arity mismatch exists there. A subsequent live GitHub API check confirmed that
current upstream master (5aadcea80dd186bd0aca714b3a6ed90593db79a7) has already
fixed this in PR #4807, commit d4af88d64eeb67df729cd8ef4b903039c5f45499,
merged 2026-09-16 20:12:21 UTC. Joolia's pinned Pkg revision 4b154560 dates to
September13 and predates the fix. The bug originated in PR #4431, commit
3306ed522235e4f8f3c45de7ed2c278a94ac0c16 (October19,2025).
Thus this is an inherited, already-fixed upstream issue still present in the
local pin, not an outstanding bug on current upstream master.
Sources: https://github.com/JuliaLang/Pkg.jl/pull/4807 and
https://github.com/JuliaLang/Pkg.jl/commit/3306ed522235e4f8f3c45de7ed2c278a94ac0c16 .
The web reader's cached master URL initially returned the stale two-argument
version; a live API lookup of master followed by fetching its immutable commit
confirmed the current one-argument call at line216.

## Suggested repair compartments

1. Shared Base tuple replacement, allequal and asyncmap: small independent fixes
   with direct regression tests and generated/fallback-path checks.
2. Diagonal operations and OneTo shuffle: prioritize the demonstrated silent
   wrong results; test value preservation and rectangular shapes.
3. TerminalMenus plus its Pkg consumers; LaTeX completion can be a separate task.
4. Dense factorizations/LAPACK wrappers; validate numerical residuals and native
   ABI boundaries, not merely successful construction.
5. Sparse constructors/storage/validation as a coordinated port.
6. SharedArrays process-vector indices, partitions and nonparticipant sentinel.
7. DelimitedFiles and LibGit2 as separate library-sized tasks.

No source, patches or tests were changed by this audit. The report is an
identification/triage result, not a new passing-suite claim. All three Luna
agents completed their bounded tasks. The main agent reproduced the primary
findings, corrected the diagm attribution, and checked the Pkg upstream origin.

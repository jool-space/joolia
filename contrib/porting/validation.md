# Validation and evidence

## Separate source review from verification

Source inspection is not build or test evidence. Reviewers with no built Joolia
must record checks as pending. Build and test the complete candidate from fresh
outputs, with no agent credentials needed by CI.

Keep unresolved semantic uncertainty separate from ordinary unexecuted checks.
Name additional required checks when the standard gate cannot exercise a change.
For example, stock-GC CI is not evidence that an MMTk-specific barrier works.

## Choose tests by the changed invariant

Write a regression that fails for the wrong semantics, not one that repeats the
implementation's formula. Prefer a small explicit expected value or a separately
derived reference result. Check invalid bounds and state transitions as well as
successful values. Add Julia tests to existing appropriate files, as AGENTS.md
requires. Read its test-changes skill when modifying those files.

Useful boundary matrix; choose relevant cases rather than multiplying every case:

| Area | Cases worth checking |
| --- | --- |
| Length | 0, 1, 2, and a size crossing a storage/word boundary |
| Position | first, last, before-first, after-last |
| Shape | 0-D, vector, non-square matrix, empty axis, trailing singleton axes |
| Index type | ordinary Int and small unsigned positions where supported |
| Ranges | offset first value, singleton, empty, descending, fractional step |
| Strings | empty, ASCII, leading/final multibyte code point, invalid byte boundary |
| Copy/mutation | overlap both directions, aliasing, growth, shrink, no-op |
| Compiler | constant and dynamic indices, inferred and runtime execution |
| Pkg | one argument, conditional dependencies, test subprocess flags |
| Terminal | short input, prompt boundary, spaces, Unicode, completion, async hint |

Examples of independent oracles:

- For a 2-by-3 dense matrix, assert selected Cartesian values and their explicit
  linear offsets; do not compute the expected result with the same helper tested.
- For a 256-element Memory, verify the first and UInt8(255) positions and ensure
  the allocation length remains 256. Do not assume UInt8 can represent that count.
- For a conditional package dependency, inspect the final manifest and load a
  function that actually uses the dependency. Installation output alone is weak.
- For an empty floating range, assert the intended endpoint/display semantics as
  well as length and collection. An empty collect result alone missed a past bug.
- For a macro, test the emitted behavior and relevant AST structure. Parsing or
  successful precompilation alone does not exercise the expanded expression.

Inspect test fixtures too. A failing upstream assertion may encode the old origin,
but that is a hypothesis to demonstrate from the contract, not an excuse to
change the expected value. Keep genuinely mathematical values, counts, foreign
indices and native IDs in expected results unchanged.

## Existing checks and what they establish

The required entry point, run by verification jobs or a human with a built tree:

```sh
python3 contrib/ci/run.py --jobs 4
```

It builds the actual fork, runs seven foundation targets in minimal/all compile
modes with bounds checking, runs fifteen established stdlib suites, runs Pkg's
misc/lifecycle checks and drives a styled package REPL. Read coverage.json before
claiming any wider coverage. Most of the large assertion count is exhaustive
Dates testing; assertion count is not a coverage percentage.

For targeted diagnostics after a successful build:

```sh
make -C test core-bootstrap base-foundation compiler-foundation
make -C test strings-foundation dict-foundation broadcast-foundation io-foundation
./usr/bin/joolia --startup-file=no --check-bounds=yes test/runtests.jl Test Dates
python3 contrib/ci/run.py --stage pkg --stage repl --logs /tmp/joolia-port-ci
```

These commands illustrate existing entry points, not a mandate to rerun every
suite for every edit. Select affected suites and the required gate. Diagnostic
subsets do not count as a full gate pass. Unported upstream suites may fail before
reaching a new regression: record that failure and run a focused relevant check;
never mark the broad suite green because the focused check passed.

Native runtime changes need a rebuild. C/C++ changes also need the repository's
c-static-analysis procedure for affected translation units; included sources such
as cgutils.cpp may be covered through codegen.cpp. LLVM-pass changes need LLVM
assertions and relevant pass tests. These are additional evidence beyond loading
a system image. Report tool/environment failures distinctly from code failures.

The root instructions request Revise-based checks for Julia test changes. Attempt
them in an appropriate verification environment. If JuliaInterpreter or
LoweredCodeUtils prevents Revise from starting, report the concrete blocker and
use the ordinary runner for available evidence; do not claim Revise succeeded.

## Test the artifact a user launches

After Base/runtime changes rebuild the system image. After REPL/Pkg changes
refresh bundled stdlib caches and restart the terminal. A fresh script can select
a different cache than interactive Base.require_stdlib, so both paths matter.
Do not pass a validation by replacing methods at runtime, including patched
source over a stale image, disabling compiled modules, or using stock Julia to
exercise Joolia semantics. Those can be diagnostics only, explicitly labelled.

Use an isolated temporary depot/project. Do not mutate a personal environment,
General registry or installed package source while validating a deterministic
regression. The CI package fixture uses local versioned repositories and checks
both dependency resolution and execution. Live network integration is separate.
Do not use fixed sleeps to coordinate asynchronous behavior: synchronize on a
prompt, readiness marker, task completion or another observable state.

## Failure triage

1. Capture the exact command, revision, architecture, compilation mode, exit code
   and relevant error. Retain the smallest failing input and nearby stack frames.
2. Determine whether the changed code ran. Distinguish build/bootstrap failure,
   stale cache, test-fixture assumption, environment/network failure and actual
   behavior regression using evidence.
3. Trace the failing value across its producer and consumer. Identify its role,
   valid range, units and sentinel. Check analogous specializations.
4. Make a narrow fix plus a regression demonstrating the invariant. Run the
   affected check, then the required gate when the candidate is ready.
5. If diagnosis exceeds the allowed pass/budget, report the blocker and stop.

Never add blanket continue-on-error, skip a newly failing required test, remove a
bounds assertion, invent a passing result, or advance the integrated checkpoint
because time ran out. A build, precompile, parser success or clean Git merge is
not a substitute for behavioral validation.

## Report precise conclusions

Keep these statements distinct:

- Reviewed: which source paths, symbols and commit diffs were inspected.
- Adapted: the exact semantic changes and their rationale.
- Tested: commands actually executed, results and artifact/log locations.
- Recommended: checks that should run elsewhere or need infrastructure.
- Unresolved: questions preventing a defensible adaptation.

Reference Joolia's own report artifacts and CI runs in public PR descriptions.
Use plain SHAs for upstream provenance, with no upstream issue/PR links or
cross-repository reference syntax. Human review must be able to identify missing
coverage without guessing from a green badge or a confident summary.

# Reviewing and adapting an upstream batch

This is an operating procedure for the scheduled porting agent. Read this guide,
subsystems.md and validation.md in addition to the short indexing contract. The
workflow appends their contents to the trusted prompt so review does not depend
on discovering a document by accident.

## Establish the source of truth

The batch contains four different revisions:

- `previous_sha`: the upstream revision integrated on the base branch.
- `base_sha`: Joolia before this proposal, including all local adaptations.
- `target_sha`: the bounded upstream prefix to integrate.
- `fetched_sha`: the upstream tip observed for this run. It is not permission to
  integrate everything through that tip.

The prepared checkout may already contain a clean merge of target into base.
Do not interpret "already merged at HEAD" as already released or validated.
The checkpoint on master advances only when a human merges the proposal.
The workflow collectively reviews the complete list, including merge commits
and their side-branch commits. In a per-commit job, review only the separate
Assigned commits list; use the full batch to understand dependencies and
interactions. Do not return reviews or make unrelated adaptations for another
job's SHAs. For an assigned merge commit, inspect its first-parent diff and check for merge-only
resolutions; do not assume it equals the union of the child diffs.

Current source and the executable's observed behavior outweigh historical notes.
JOOLIA_BASE_PORT.md is chronological: old failures and old passing counts do not
establish the current state. contrib/ci/coverage.json defines the required gate.
The root AGENTS.md and relevant repository skills define contributor procedures.
The scheduled review job has no built Joolia and cannot run their build commands;
record those commands as required follow-up, never claim they ran.

## Review each commit in three views

For each assigned full SHA, inspect:

1. **Upstream intent.** Read the commit diff against its first parent and the
   surrounding definitions/callers in that revision. Identify the behavior being
   fixed, not merely the changed lines. A bug fix must still fix that bug in Joolia.
2. **Existing port.** Compare the affected paths between previous_sha and base_sha.
   Find local origin conversions, sentinels, aliases, custom array axes and
   bootstrap constraints that an upstream change might bypass or duplicate.
3. **Resulting tree.** Read the corresponding functions after the merge. Trace at
   least one input through producer, storage, consumer and error handling.
   Search for callers and related specializations, including generated methods.
   Read the docstrings/contracts of functions used in an adaptation; do not rely
   on remembered upstream signatures after the origin change.

Useful read-only commands, with actual batch SHAs substituted:

```sh
git diff COMMIT^1 COMMIT -- path/to/file
git show COMMIT:path/to/file
git diff PREVIOUS BASE -- path/to/file
rg -n 'function_name|related_helper' base Compiler src stdlib test
```

A clean Git merge answers a textual question. It does not check whether a new
helper expects dimension one, whether a former +1 now converts twice, or whether
a metadata tuple still agrees with generated code.

## Classify numbers before editing

Assign each index-looking expression a role and write down its contract:

| Role | Treatment |
| --- | --- |
| Ordinary collection position | Starts at zero; validate its axes and caller |
| Dimension selector | Starts at zero; a rank is still a count |
| Count, length, rank, capacity, iteration count | Preserve the quantity |
| Inclusive final position | Usually first position + count - 1; handle empty/unsigned cases |
| One-past-end boundary | Usually first position + count; not a valid element |
| Range value | Preserve its mathematical value and inclusive colon semantics |
| Iterator state | Read that iterator's producer/consumer; it need not be an index |
| Compiler ID or serialized tag | Preserve the established encoding unless explicitly migrating that format |
| Byte offset or native pointer offset | Check units and the foreign/native contract; often already zero-based |
| Sentinel or enum | Check valid values and representation, including signedness |
| Human ordinal or diagnostic label | Distinguish first/second from numeric dimension 0/1 |

Do not apply global replacements of `[1]`, `1:n`, `+1`, `-1`, `dims=1` or numeric
`getfield` arguments. A single function can contain several different roles.
Use a short invariant such as "p is a storage position; n is a count; valid
positions satisfy 0 <= p < n". Follow the same invariant into callees.

## Derive the adaptation

Examples apply only when their stated preconditions hold:

- For a conventional dense vector, a position loop is `0:(length(v)-1)`.
  In generic array code prefer `eachindex(v)`/`axes(v,d)` when those match the
  algorithm's indexing requirements; offset arrays remain possible.
- A loop that repeats an action n times can remain `1:n` if its variable is never
  used as a position. Changing it may alter observable ordinal values.
- The inclusive slice of k elements beginning at s is `s:(s+k-1)`.
  Its length is k, not k-1. Check k=0 separately and avoid unsigned underflow.
- For a conventional zero-origin array, missing-neighbor and after-end positions
  are different: -1 is before the first; length(v) is after the last.
- Removing an old +1 wrapper around a native zero-based result is correct only
  when its consumer now expects zero-based positions. Look at both sides.
- Reversing a branch condition is not an origin conversion. Write a truth table
  for found/not-found before changing `&&`, `||`, comparison strictness or continue.

Do not normalize an intentional custom axis into ZeroTo just to make a test pass.
Do not introduce Int conversions that exclude the UInt8 position use case.
When changing an error message, make its dimensions/positions agree with the API.
A tuple reporting `(3,4)` is a shape, not a pair of position values to decrement.

## Preserve Julia behavior outside the indexing contract

Preserve upstream bug fixes, dispatch specificity, inference, exception types,
allocation behavior and foreign ABI contracts where possible. Prefer a small
adaptation at an established boundary over extra conversions at every caller.
Do not replace carefully specialized code with allocation-heavy generic code
without explaining why it is necessary and how performance will be measured.
Do not disable inlining, inference, bounds checks or an optimization merely to
hide a porting failure. Preserve GC roots, barriers, ownership and atomic ordering.

Inspect matching paths together: generic and specialized methods; static and
dynamic tuple lengths; interpreted and compiled builtins; get/set/isassigned;
copy/copyto!; forward and reverse search; native lowering and compiler inference.
Generated expressions require inspection of what they emit, not only their
construction code. No newly introduced Base helper may be assumed available in
an earlier bootstrap phase.

Stay within the selected batch. If an apparent failure requires a prerequisite
outside it, identify that SHA and return manual. Do not cherry-pick unrelated
fixes, pull latest stdlibs, redesign an API, change source extensions, or add the
proposed mixed-delimiter range syntax during routine upstream synchronization.

## Write an auditable per-commit record

For every commit's existing schema fields:

- `subsystems`: name actual affected components, not just "Base" or "runtime".
- `indexing_implications`: cite relevant source paths and symbols, classify the
  integers, and state a concrete invariant. Mention surrounding callers inspected.
- `adaptations`: explain each changed expression and why it preserves upstream
  intent. "None" must include a reason grounded in the inspected code.
- `tests`: name relevant existing test files/targets, boundary inputs and expected
  results. Distinguish recommended tests from tests actually executed.
- `risk`: assess impact if wrong. Native GC/compiler work can be high risk even
  when no origin adaptation is needed.

The report must not assert a test passed, a build succeeded, or a performance
property was measured without evidence. A high-risk change with a clear
contract may be proposed for a draft and CI; unresolved semantics require manual.
Do not confuse these decisions with approval to merge.

Use plain commit SHAs in summaries. Do not include upstream issue/PR URLs,
`owner/repository#number` references, or copied PR numbers from commit subjects
in PR-facing text. We do not want cross-reference notifications on upstream PRs.
The original upstream commit messages remain preserved in Git history.

## Stop conditions

Return decision=manual and explain the exact boundary when:

- The workflow reports merge conflicts, protected-file changes or required
  external-stdlib imports.
- Units, axes, sentinel meaning or native-ID encoding cannot be established.
- A necessary follow-up/prerequisite lies outside the pinned batch.
- A change needs an ABI/serialization-format migration or an unreviewed global
  convention change rather than a narrow adaptation.
- The repair requires weakening tests, replacing a production method only in a
  test process, or guessing about unsafe pointer/GC behavior.
- The time or patch budget is insufficient to complete the review.

Prefer an explicit, actionable unresolved concern over a large speculative patch.

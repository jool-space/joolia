# Pinned original Joolia port

## Source boundary

This branch starts from the original working port, not a reverse patch on the
latest nightly. Its upstream Julia revision is
`07e2c78d9b` (Julia 1.14.0-DEV, September 16, 2026).
The initial Joolia checkpoint is `6580bd5dcd`; `baseline/first-working`
preserves that exact commit. `baseline/initial-port` adds the independent
improvements listed below. `main` is the default development branch built from
that tested baseline. The former default branch is retained as `master` and
`archive/upstream-sync-2026-09-21`.

The original `src/`, `Compiler/`, `base/`, `JuliaSyntax/` and `JuliaLowering/`
trees are preserved byte-for-byte from that checkpoint. The manual 26-commit
Julia update and every later automated upstream integration are excluded.
This is an experimental port, not a stable Julia or Joolia release.

## Preserved work

- All sixteen vendored stdlib subtrees at their original imported revisions,
  including the zero-origin adaptations and direct-source build setup through
  `624288d380`. Existing subtree ancestry and provenance are retained.
- Pkg progress-bar and depot-index fixes from `c75b0fb6e2`.
- Resolver dependency-edge and allocation-mode fixes from `64b009bcce`,
  including the package lifecycle regression checks.
- Standalone build/test CI from `ac7b08d4eb`: foundation checks, fifteen stdlib
  suites, package lifecycle and an actual styled package REPL.
- Subtree import ordering from `c078433b9e`, and removal of the obsolete
  patch-stack check previously removed during the manual integration.
- The previously uncommitted REPL history fix and its boundary/PTY regressions.
  Forward searches stop at the input buffer's logical size, ignoring stale
  history bytes beyond it. The source worktree was left untouched.
- The [porting handbook](contrib/porting/README.md), adapted for deliberate
  integrations without the scheduled-agent machinery.

## Deliberately excluded

The complete [history inventory](contrib/porting/baseline-history.json) records
all 158 commits after the initial checkpoint through source master
`57d27b961063dae2323809b7ac71d10d5b7154de`, with a decision for each commit.
This includes 45 newer Julia commits, subtree imports, integration records and
CI automation changes; it is not a count of 158 independent Joolia changes.

Sync workflows, agent invocation, automatic merging, queue recovery and sync
report/checkpoint files are not part of this branch. The original experiment
remains in master's history. The repository's sync and auto-merge variables were
set to false when this branch was constructed. Both sync workflows were disabled
when the baseline became `main`; ordinary build/test CI is retained. The protected
`main` branch requires `Build and test (ubuntu-24.04)`, with no requirement for
the retired sync tooling.

`c39fcec82c` is not an independent Pkg fix: its skip/force precompile API requires
the excluded newer Base driver. `6b338dc70c` adjusts a test fixture introduced by
an excluded upstream update. Neither is backported. Open proposal 21 is also not
included; it was not merged into the audited master revision.

## Verification

Run the required gate from this checkout:

```sh
python3 contrib/ci/run.py --jobs 8
```

This builds fresh artifacts and uses isolated test depots. Only compressed
native dependency archives may be reused; no system image, bundled package
cache or native Joolia object from the newer tree is used to validate this branch.
The reconstructed baseline passed the complete local gate and the hosted
[build/test run](https://github.com/jool-space/joolia/actions/runs/35518136764).
Results and individual logs are written to `ci-results/`. The machine-readable
coverage limits remain in [coverage.json](contrib/ci/coverage.json).

Preserving the initial source also preserves its known gaps. In particular, the
historically observed IntegerCodeUnits hashing issue is not fixed here. A green
required gate is not a claim that the full upstream test suite is ported.

## Future updates

Keep this upstream SHA fixed while strengthening the port and its tests. Choose
an upstream release milestone explicitly for the next integration, review it by
subsystem, and validate the complete candidate before changing this baseline.
See [the review method](contrib/porting/review-method.md) and
[vendored stdlib instructions](stdlib/VENDORED.md).

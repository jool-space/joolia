# Scheduled upstream review

`.github/workflows/upstream-sync.yml` uses the official pinned
[Codex Action](https://learn.chatgpt.com/docs/github-action) with
`gpt-5.6-luna`, high reasoning effort and Codex CLI 0.155.0. It produces draft
PRs. An optional trusted merge workflow integrates them after dual-architecture CI succeeds. The first hosted Joolia build/test gate passed at
[ac7b08d4eb](https://github.com/jool-space/joolia/actions/runs/35284862101).

## Porting handbook

Every agent prompt includes the short contract plus these guides:

- [Review method](guides/review-method.md): three-way semantic review, number
  classification, derivation of adaptations, source evidence and stop conditions.
- [Subsystem map](guides/subsystems.md): runtime/bootstrap, tuples/ASTs, arrays,
  dimensions, ranges, strings/IO, compiler IDs, foreign numerical libraries,
  REPL/Pkg and vendored stdlibs, with concrete traps from this port.
- [Validation](guides/validation.md): boundary matrices, independent test oracles,
  available checks, artifact/cache hygiene, failure triage and honest reporting.

These guide the review; they cannot certify the agent's reasoning. Reports must
cite source paths and symbols and distinguish reviewed code from executed tests.
Public PR descriptions use plain commit SHAs and sanitized subjects, with no
upstream issue/PR links or cross-repository issue references. The full provenance
remains in the committed report and original Git history.

## Running it

The manual default is a free, deterministic plan without an agent invocation:

```sh
gh workflow run upstream-sync.yml --repo jool-space/joolia --ref master -f mode=plan
```

To try Luna on the next batch, configure `OPENAI_API_KEY` as a repository Actions
secret and allow Actions to create pull requests in the repository's Actions
settings. Do not put the key in a file or commit it.

```sh
gh secret set OPENAI_API_KEY --repo jool-space/joolia
gh workflow run upstream-sync.yml --repo jool-space/joolia --ref master -f mode=propose
```

After inspecting the first proposal, enable the daily 05:47 UTC schedule:

```sh
gh variable set JOOLIA_UPSTREAM_SYNC_ENABLED --body true --repo jool-space/joolia
```

Delete that variable or set it to `false` to stop scheduled proposals. Manual
runs remain available. This switch controls scheduled proposals and post-merge continuation;
automatic merging has a separate switch below. Each incoming commit gets its own
review job against the complete merged batch, with at most two running at once.
Each job has an independent eight-minute deadline including action setup,
a ten-minute step limit and a fifteen-minute outer job limit. These are runtime
bounds, not dollar/token caps. A root-owned watchdog identifies the review action
by its exact environment marker and puts it and its descendants in a separate
cgroup with a 4 GiB memory limit and no swap. This prevents a review from using
all runner memory and lets the deadline kill descendants that clear their marker.
Memory counters and OOM events are retained with the diagnostics. The Actions
worker is outside this group. A killed runner can still prevent diagnostics
from being uploaded; the watchdog is not a guarantee of artifact retention.

A reviewer writes its current SHA and completed record to an ignored progress
file. Each job uploads `upstream-review-<sha>` independently, retaining the review,
patch, action outcome and available watchdog diagnostics. Successful artifacts
survive failures in other jobs. Use GitHub's **Re-run failed jobs** to retry the
failed assignments and collection, retaining successful reviews from the same
pinned plan. Retried jobs replace only their own artifact. A new workflow run
pins a new plan and does not reuse reviews from another source revision.

Diagnostics never replace a validated final review and cannot authorize a PR.
No process arguments, environment contents or Codex authentication files are
uploaded. The collector requires one successful report per planned SHA, validates
patch restrictions, and combines adaptations in a disposable worktree. Identical
patches are applied once; differing patches touching the same file require manual
reconciliation. One manual review blocks integration of the entire batch.

To exercise the actual next batch without publishing or advancing a checkpoint:

```sh
gh workflow run upstream-sync.yml --repo jool-space/joolia --ref master -f mode=review
```

Maintainers can also run this mode on a same-repository workflow branch. It makes
API calls and runs the same review matrix and collector as production. It does
not build Joolia; publication still requires the separate complete CI gate.

To check the action/model path independently of a large review, manually run:

```sh
gh workflow run upstream-sync.yml --ref master -f mode=probe --repo jool-space/joolia
```

The probe asks for a sandboxed shell read of a random challenge file, an
`apply_patch` edit copying its contents, and a tiny JSON response. It verifies
both the response and the edited file, has a three-minute
independent deadline, and never publishes a PR or advances a checkpoint. Maintainers can
also dispatch it on a same-repository workflow branch to validate a fix before
merging. Review-only trials and probes use separate concurrency groups so a stuck batch
does not block diagnosis; they never publish. It still makes an API call. Failed review batches are not retried in an
unbounded loop; inspect the artifact before deciding whether to retry.

## What happens

1. Read `state.json` from the workflow revision on master, fetch upstream master
   and pin its SHA. Verify the last integrated SHA is an ancestor of both trees.
2. Select a first-parent prefix, including every commit reachable through its
   merged branches. Limits are 20 commits, 2,500 changed lines and 250,000 patch
   bytes, counting individual diffs (including merge diffs). Never split an
   upstream merge group. Runtime and compiler changes share these budgets with
   other changes; touching `src/` or `Compiler/` does not force a separate build.
   Luna still reviews every commit individually and flags unsafe changes for
   manual integration. A successful merge immediately starts the next batch;
   the daily schedule is a kickoff, not a one-batch-per-day limit.
3. Preserve the complete ordered incoming list, filenames, sizes and stdlib
   provenance in a plan artifact. Oversized first groups stop with a diagnostic;
   they are never skipped. A pending sync PR prevents preparing another batch.
4. Each matrix job attempts the full merge in an ephemeral checkout. Luna reads
   its assigned commit and surrounding code, returns a schema-constrained report, and can
   make source/test adaptations. Conflicts are aborted and reported for manual
   work. Changes to automation/instructions or stdlib recommendations needing
   subtree imports also produce manual reports rather than source integration.
5. A fresh collector reconstructs the plan, validates exactly one review per
   incoming SHA, and combines compatible patches. The separate publisher recreates
   the upstream merge and applies that combined patch.
   Adaptations are committed separately. Patches cannot change automation or
   agent instructions, or introduce symlinks/submodules. No candidate code is
   executed by the publisher, which has no OpenAI credential.
6. Publish one draft PR with the report, commit list, proposed stdlib pulls,
   concerns and proposed checkpoint. Integrated candidates explicitly dispatch
   Joolia CI on the resulting branch; its manual mode tests x86-64 and ARM64.
   This explicit dispatch avoids depending on bot-created PR workflows starting
   automatically; GitHub can hold those PR-event runs for human approval. See
   [GitHub's trigger documentation](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow).

Agent credentials exist only in the agent job. Compilation and tests run in the
separate Joolia CI workflow without those credentials. The publisher uses only
GitHub's job token. Checkout credentials are not persisted into the agent tree.

## Automatic merging and backlog draining

Set `JOOLIA_UPSTREAM_AUTOMERGE_ENABLED=true` to enable
`.github/workflows/upstream-merge.yml`. Set it to `false` to stop automatic merges;
set `JOOLIA_UPSTREAM_SYNC_ENABLED=false` as well to stop automatic new proposals.
Add the `sync:hold` label to pause a particular PR.

The publisher dispatches the gate as soon as a candidate is published. It also
runs when CI or housekeeping workflows complete. Successful sync CI explicitly
dispatches the gate after both architecture jobs and tooling pass, in a separate
job with no candidate checkout. The gate waits up to five minutes for that final
notification job and the CI workflow to finalize, then applies all existing
revision and success checks. This closes the gap where an early completion event
observed unfinished CI and no later event woke the queue. Hourly recovery
and manual dispatch remain available. It executes only trusted master tooling and reads
candidate Git objects as data; it never checks out or executes candidate code.
It accepts only same-repository bot-authored sync PRs with a complete integrated
report, no unresolved concerns, the expected checkpoint, and no protected-file
changes beyond the generated report and checkpoint. Manual reports stay open.
After that validation, it approves pending PR runs only for Joolia CI, Labels,
Typos and Whitespace, matching the exact head SHA, repository, branch and PR.
Forks, other authors, stale revisions and other workflows remain subject to
normal approval. This approves workflow execution, not a pull-request review.
PR checks on GitHub's synthetic merge commit must finish successfully too.

If master has advanced, the gate merges master into the candidate and dispatches
fresh CI. Otherwise the latest explicit Joolia CI run must succeed on the exact
head SHA, including the tooling, x86-64 and ARM64 jobs. Other pending or failing
checks block merging too. Master must have strict required checks for
`Upstream sync tooling` and `Build and test (ubuntu-24.04)`; configure enforcement
for administrators as well. The gate independently requires ARM64, while ordinary
PRs retain their existing x86-64 gate. Existing branch rules and required reviews
are respected; the workflow neither approves its own PR nor bypasses protection.

After validation, the gate marks the draft ready and uses a SHA-guarded merge
commit. It then explicitly dispatches `upstream-sync.yml` in `propose` mode on
master. Thus the daily cron starts work when idle; each successful merge starts
the next batch immediately, until caught up or blocked. GitHub-token merges do
not automatically trigger ordinary push workflows, so continuation uses an
explicit workflow dispatch ([GitHub event semantics](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)). A failed dispatch can be retried by the daily/manual
sync run. The gate also starts a fresh attempt when there is no pending sync PR,
no active sync run, and master has advanced since the last attempt. This recovers
when a fix lands after a pre-publication failure. It does not repeatedly retry
failures on an unchanged master revision, and held/manual-report PRs still block
new batches. This is a serial queue, not a one-PR-per-day quota.

This can spend API credits on several consecutive batches. Each batch retains
its existing size and agent timeout limits; there is no cumulative dollar cap.

## Checkpoints, retries and limitations

A proposal updates `state.json` on its branch only. Master's checkpoint advances
when the merge gate or a human merges the PR **with a merge commit**. Do not squash/rebase sync PRs:
that loses the upstream ancestry on which subsequent planning relies. Review
whether the selected boundary omits a dependent follow-up before merging.

A retry reuses an already published branch, creates a missing draft PR and
explicitly dispatches missing CI without paying for another agent run. Existing
runs are not automatically rerun. Closed/rejected batches are not silently
reopened or overwritten. Resolve them manually before resuming the queue.
No force-pushes are used. Plans and reviews are retained as artifacts for 30 days;
the full review is also committed under `reports/<target-sha>.json`.

A report-only PR does not import upstream code or advance the checkpoint. It
needs manual integration; marking the draft ready or merging its report does
not resolve the missing source changes. Merge the recorded target SHA, supply
the missing adaptations, preserve the initial review alongside the resolution,
and update the checkpoint only on that integration branch. Run CI on the
resulting tree. A replacement PR can close the report-only PR when it merges,
allowing the queue to resume from the new checkpoint. Closing the report alone
will not make the publisher retry that same batch.

A CI failure likewise remains on the draft for inspection. This initial version has
no automatic repair/bisection loop, no autonomous subtree import, and no measured
Luna recall/cost benchmark yet. These should follow observed trial results.

The plan compares modified `.version` recommendations with reachable subtree
trailers and records the exact suggested `bump_stdlib.sh -b <sha> Name` command.
A new/missing subtree or repository-URL change needs manual handling; the workflow
never executes a URL or branch extracted from untrusted version metadata.

Green CI still covers only `contrib/ci/coverage.json`. Runtime/LLVM adaptations
may need additional static analysis and pass tests beyond the standard gate.
Neither a clean merge nor a positive Luna report establishes correctness.

## Local validation

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s contrib/upstream-sync -p 'test_*.py' -v
python3 contrib/upstream-sync/sync.py plan --upstream upstream/master --out /tmp/joolia-sync-plan
```

The tests use temporary Git repositories and mock only GitHub publication.
They exercise ancestry, merge groups, conflicts, batch limits, complete reports,
stdlib provenance, separate adaptation commits, patch restrictions and retries.
Run `prepare`/`assemble` only in disposable clean worktrees, as the workflow does.

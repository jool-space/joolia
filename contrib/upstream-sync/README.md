# Scheduled upstream review

`.github/workflows/upstream-sync.yml` uses the official pinned
[Codex Action](https://learn.chatgpt.com/docs/github-action) with
`gpt-5.6-luna`, high reasoning effort and Codex CLI 0.155.0. It produces draft
PRs; it never merges them. The first hosted Joolia build/test gate passed at
[ac7b08d4eb](https://github.com/jool-space/joolia/actions/runs/35284862101).

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
runs remain available. There is no automatic merge or scheduled API spending
until this variable is enabled. Each new batch permits one agent invocation,
with a 30-minute timeout; this is a runtime bound, not a dollar/token cap.

## What happens

1. Read `state.json` from the workflow revision on master, fetch upstream master
   and pin its SHA. Verify the last integrated SHA is an ancestor of both trees.
2. Select a first-parent prefix, including every commit reachable through its
   merged branches. Limits are 20 commits, 2,500 changed lines and 250,000 patch
   bytes, counting individual diffs (including merge diffs). Never split an
   upstream merge group. Isolate groups touching `src/` or `Compiler/`.
3. Preserve the complete ordered incoming list, filenames, sizes and stdlib
   provenance in a plan artifact. Oversized first groups stop with a diagnostic;
   they are never skipped. A pending sync PR prevents preparing another batch.
4. Attempt a clean merge in an ephemeral checkout. Luna reads each incoming
   commit and surrounding code, returns a schema-constrained report, and can
   make source/test adaptations. Conflicts are aborted and reported for manual
   work. Changes to automation/instructions or stdlib recommendations needing
   subtree imports also produce manual reports rather than source integration.
5. A fresh publisher runner reconstructs the plan, validates exactly one review
   per incoming SHA, recreates the upstream merge and applies the proposed patch.
   Adaptations are committed separately. Patches cannot change automation or
   agent instructions, or introduce symlinks/submodules. No candidate code is
   executed by the publisher, which has no OpenAI credential.
6. Publish one draft PR with the report, commit list, proposed stdlib pulls,
   concerns and proposed checkpoint. Integrated candidates explicitly dispatch
   Joolia CI on the resulting branch; its manual mode tests x86-64 and ARM64.
   This explicit dispatch is necessary because pushes/PRs created with
   `GITHUB_TOKEN` do not trigger ordinary workflows. See
   [GitHub's trigger documentation](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow).

Agent credentials exist only in the agent job. Compilation and tests run in the
separate Joolia CI workflow without those credentials. The publisher uses only
GitHub's job token. Checkout credentials are not persisted into the agent tree.

## Checkpoints, retries and limitations

A proposal updates `state.json` on its branch only. Master's checkpoint advances
when a human merges the PR **with a merge commit**. Do not squash/rebase sync PRs:
that loses the upstream ancestry on which subsequent planning relies. Review
whether the selected boundary omits a dependent follow-up before merging.

A retry reuses an already published branch, creates a missing draft PR and
explicitly dispatches missing CI without paying for another agent run. Existing
runs are not automatically rerun. Closed/rejected batches are not silently
reopened or overwritten. Resolve them manually before resuming the queue.
No force-pushes are used. Plans and reviews are retained as artifacts for 30 days;
the full review is also committed under `reports/<target-sha>.json`.

A report-only PR does not import upstream code or advance the checkpoint. It
needs manual integration, or closing and manual resolution of the batch. A CI
failure likewise remains on the draft for inspection. This initial version has
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

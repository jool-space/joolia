# Joolia CI

Run the same gate locally and on GitHub Actions:

```sh
python3 contrib/ci/run.py --jobs 4
```

Requirements: Linux, Python 3.11+, Git, and the normal Julia build prerequisites
listed in `doc/src/devdocs/build/build.md`. CI builds with LLVM assertions and
BinaryBuilder dependencies. The entry point always builds first, including
bundled stdlib caches, then tests fresh processes against `usr/bin/joolia`.
It does not install an upstream Julia executable to run Joolia tests.

The required stages are:

1. A complete `make` build.
2. Core, Base, Compiler, strings, Dict, broadcast and IO bootstrap checks in
   interpreted and compiled modes, with bounds checking.
3. The fifteen established stdlib suites listed in `coverage.json`, using the
   ordinary upstream test runner with bounds checking.
4. Pkg miscellaneous tests, including actual passing and failing package-test
   subprocesses and allocation-mode inheritance.
5. A styled PTY session using the bundled REPL/Pkg. A local Git registry has two
   versions of a package: only the newer version requires another package. The
   test installs the newer version through `pkg> add`, checks both manifest
   entries, loads the package, exercises backspace and Tab completion, and runs
   `pkg> test`. Test workers must have allocation tracking disabled and leave no
   `.mem` files. No General registry or package-server access is needed here.

Every listed check is required. `coverage.json` also records what is only
partially covered; passing CI does not certify all of Base, all stdlibs, or
unported ecosystem packages. Add suites to the required list as their ports
become consistently green. Do not hide failures with `continue-on-error`.

Logs and a JSON report (revision, worktree changes, architecture, selected
coverage and individual stage results) go to `ci-results/`, which is ignored by
Git. GitHub uploads these even when a check fails. Test depots and fixture Git
repositories are temporary and never use the developer's personal depot.

For diagnosis after building, select stages with repeated `--stage` arguments:

```sh
python3 contrib/ci/run.py --stage pkg --stage repl --logs /tmp/joolia-ci
```

A subset run is not a full CI pass. Rebuild after source edits before checking
interactive behavior: `pkg>` loads bundled caches without source freshness
checks, whereas `using Pkg` in a script can load a different package instance.

The workflow runs x86-64 on PRs and pushes to `master`. Daily scheduled runs and
manual dispatches run both x86-64 and ARM64 on fresh GitHub-hosted Ubuntu 24.04
VMs. Only compressed dependency downloads are cached; system images, bundled
package images and compiled test depots are never restored from CI caches.
Scheduled runs also bypass the download cache.

After the workflow is pushed and has run successfully, the repository's branch
rules can require `Build and test (ubuntu-24.04)`. This workflow does not change
branch rules, publish binaries, or automatically sync/merge upstream changes.

The separate whitespace workflow scans Joolia-owned files using upstream Julia's
checker. Vendored subtrees retain their own formatting conventions, while
`git diff --check` still rejects newly introduced whitespace errors in all paths.

# Joolia patches for fetched standard libraries

Keep changes to fetched standard libraries in `Name/*.patch`, relative to the
root of that library, with `a/` and `b/` paths for `patch -p1`. The upstream
revision remains pinned by `stdlib/Name.version`.

The standard-library build applies patches in lexical order before marking the
source compiled. It accepts patches already present in the checkout and fails
on mismatches, preserving local changes for inspection. Number new patches in
application order. If changing a patch already applied locally, first reverse
its previous version in the checkout, or use a fresh extraction after saving
any local edits. Overlapping patches are supported: the build helper identifies
an already-applied prefix by reversing it in a temporary copy, then validates the
whole stack in order. Only after validation are patch-owned files updated.
Unrelated local edits are preserved; conflicts leave the fetched tree unchanged.

Include regression changes to the upstream test files in the patch stack.
`make -C stdlib compile-Name` checks application; a full Julia build and the
library tests are still needed to validate behavior. Generated fetched-source
and stamp files are not the durable source of Joolia changes.

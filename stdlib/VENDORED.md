# Working on Joolia's external standard libraries

All 16 externally maintained stdlibs are tracked here as **squashed Git
subtrees**. Edit `stdlib/Pkg/src/...`, `stdlib/LinearAlgebra/src/...`, and the
other libraries directly. Commit changes in this repository, including changes
spanning Base and multiple stdlibs. Clones and source archives contain the
sources; there are no submodules or additional repositories to initialize.

The build links these directories into `usr/share/julia/stdlib/vX.Y/`. It never
downloads, extracts, or patches them. `clean` and `distclean` remove installation
state, never tracked source. Native libraries and their JLL artifacts retain
the usual dependency workflow.

## Updating from upstream

Start with a clean worktree, choose a reviewed upstream revision, then run:

```sh
contrib/bump_stdlib.sh -b <commit-or-branch> Pkg
```

Without `-b`, the helper uses the branch in `stdlib/Pkg.version`. Multiple names
and `all` are supported. It runs `git subtree pull --prefix=stdlib/Pkg --squash`
against the URL in that file. It creates local commits and never pushes.
Conflicts stop the operation; resolve them in the ordinary files and finish the
merge with `git commit`, or cancel it with `git merge --abort`.

The equivalent manual command is:

```sh
git subtree pull --prefix=stdlib/Pkg --squash https://github.com/JuliaLang/Pkg.jl.git <revision>
```

The `git-subtree-dir` and `git-subtree-split` trailers in the squash history
record the actual imported upstream revision:

```sh
git log --all --grep='^git-subtree-dir: stdlib/Pkg$' --format='%h %B'
```

The `.version` files are retained as **Julia's recommended upstream revisions**,
so future Julia merges can update them without silently changing our sources.
They do not select build inputs. Compare them with subtree history before
updating; an upstream Julia merge does not update the subtrees automatically.

Review incoming indexing assumptions even when Git reports a clean merge.
Rebuild with `make -j8` and run the affected tests. For REPL changes, exercise an
actual interactive session too: bundled precompile caches can outlive source
edits until the build refreshes them.

## Migration baseline

Each subtree was imported pristine at the existing `.version` revision before
applying the existing Joolia port. Every upstream-tracked file was compared
byte-for-byte with the formerly extracted source. The 23 patch files and their
application helper were then retired; their history is retained in Git.
Ignored `stdlib/Name-<sha>` directories from older builds are no longer used.
They are left intact during migration and cleaning to preserve any local work.

For a new external stdlib, use `git subtree add --prefix=stdlib/Name --squash
<repository> <revision>`, add its provenance `.version` file, and include its
name in `STDLIBS_EXT` in `stdlib/Makefile`.

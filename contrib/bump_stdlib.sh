#!/bin/bash
# This file is a part of Julia. License is MIT: https://julialang.org/license
# Update vendored stdlibs with squashed subtree merges; never push.
set -euo pipefail

JULIA_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$JULIA_ROOT"
usage() {
    echo "Usage: $0 [-b <commit-or-branch>] <StdlibName>... | all" >&2
    exit 1
}
REVISION=
while getopts 'b:' opt; do
    case "$opt" in
        b) REVISION=$OPTARG ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))
[ "$#" -ge 1 ] || usage
if [ "$#" -eq 1 ] && [ "$1" = all ]; then
    NAMES=()
    for version_file in stdlib/*.version; do
        NAMES+=("$(basename "$version_file" .version)")
    done
else
    NAMES=("$@")
fi
# Validate all inputs before starting any merge.
for name in "${NAMES[@]}"; do
    [[ "$name" =~ ^[A-Za-z][A-Za-z0-9]*$ ]] || usage
    if [ ! -f "stdlib/$name.version" ] || ! git ls-files --error-unmatch "stdlib/$name/Project.toml" >/dev/null 2>&1; then
        echo "error: '$name' is not a vendored stdlib" >&2
        exit 1
    fi
done
if [ -n "$(git status --porcelain)" ]; then
    echo 'error: commit or stash local changes before updating subtrees' >&2
    exit 1
fi
for name in "${NAMES[@]}"; do
    upper=$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')
    getvar() {
        sed -n "s/^$1[[:space:]]*:\{0,1\}=[[:space:]]*//p" "stdlib/$name.version" | tail -n1
    }
    url=$(getvar "${upper}_GIT_URL")
    revision=${REVISION:-$(getvar "${upper}_BRANCH")}
    [ -n "$url" ] && [ -n "$revision" ] || { echo "error: incomplete provenance for $name" >&2; exit 1; }
    git subtree pull --prefix="stdlib/$name" --squash "$url" "$revision"
done

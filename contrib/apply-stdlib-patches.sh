#!/bin/sh
# Validate the complete ordered stack before changing fetched stdlib sources.
set -eu
source_dir=$1
shift
scratch=$(mktemp -d "${TMPDIR:-/tmp}/joolia-stdlib-patches.XXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
printf '%s\n' "$@" > "$scratch/patches"
prefix=$#
matched=false
while [ "$prefix" -ge 0 ]; do
    rm -rf "$scratch/source"
    mkdir "$scratch/source"
    cp -R "$source_dir/." "$scratch/source/"
    awk -v limit="$prefix" 'NR <= limit { lines[NR] = $0 } END { for (i = limit; i > 0; i--) print lines[i] }' "$scratch/patches" > "$scratch/reverse"
    if (
        while IFS= read -r patchfile; do
            patch --batch --no-backup-if-mismatch -s --reverse -d "$scratch/source" -p1 < "$patchfile" || exit 1
        done < "$scratch/reverse"
        while IFS= read -r patchfile; do
            patch --batch --no-backup-if-mismatch -s --forward -d "$scratch/source" -p1 < "$patchfile" || exit 1
        done < "$scratch/patches"
    ) > "$scratch/result" 2>&1; then
        matched=true
        break
    fi
    prefix=$((prefix - 1))
done
if [ "$matched" != true ]; then
    cat "$scratch/result" >&2
    echo "Joolia patch stack does not match fetched source: $source_dir" >&2
    exit 1
fi
# Only patch-owned paths are copied; unrelated local files are left in place.
for patchfile do
    sed -n -e 's|^--- a/||p' -e 's|^+++ b/||p' "$patchfile"
done | sort -u > "$scratch/files"
while IFS= read -r file; do
    case "$file" in
        ''|/*|..|../*|*/../*|*/..) echo "Invalid patch path: $file" >&2; exit 1 ;;
    esac
done < "$scratch/files"
while IFS= read -r file; do
    if [ -f "$scratch/source/$file" ]; then
        if ! cmp -s "$scratch/source/$file" "$source_dir/$file"; then
            mkdir -p "$(dirname "$source_dir/$file")"
            cp "$scratch/source/$file" "$source_dir/$file"
        fi
    elif [ -f "$source_dir/$file" ]; then
        rm "$source_dir/$file"
    fi
done < "$scratch/files"

#!/usr/bin/env python3
"""Combine complete per-commit reports and compatible patches without running candidate code."""
import argparse
import json
import os
from pathlib import Path
import tempfile

import sync


def collect(batch, folder):
    sync.verify_plan(batch)
    reports = folder / 'reviews'
    expected = {'upstream-review-' + c['sha'] for c in batch['commits']}
    if {p.name for p in reports.iterdir()} != expected:
        raise ValueError('Expected exactly one artifact per planned SHA')
    review = dict(target_sha=batch['target_sha'], decision='propose',
                  summary='Every incoming commit was reviewed in a separate job against the full merged batch.',
                  unresolved=[], commits=[])
    patches = []
    for commit in batch['commits']:
        sha = commit['sha']
        artifact = reports / ('upstream-review-' + sha)
        part = json.loads((artifact / 'review.json').read_text())
        sync.validate_review(sync.review_assignment(batch, sha), part)
        if json.loads((artifact / 'action-result.json').read_text()) != {'outcome': 'success'}:
            raise ValueError('Only successful review jobs can authorize publication')
        review['commits'].extend(part['commits'])
        if part['decision'] == 'manual':
            review['decision'] = 'manual'
            review['unresolved'].append(sha + ': ' + part['summary'])
        review['unresolved'].extend(sha + ': ' + s for s in part['unresolved'])
        patch = artifact / 'adaptations.patch'
        if patch.stat().st_size > batch['limits']['max_patch_bytes']:
            raise ValueError('Adaptation patch exceeds size budget')
        if patch.stat().st_size:
            patches.append((sha, patch.resolve()))
    combined = ''
    if review['decision'] == 'propose':
        combined, concerns = combine_patches(batch, patches)
        if concerns:
            review['decision'] = 'manual'
            review['unresolved'].extend(concerns)
    sync.validate_review(batch, review)
    sync.write_json(folder / 'review.json', review)
    (folder / 'adaptations.patch').write_text(combined)


def combine_patches(batch, patches):
    """Validate against one baseline, then three-way merge compatible adaptations."""
    original = Path.cwd()
    with tempfile.TemporaryDirectory(prefix='joolia-review-') as temporary:
        checkout = Path(temporary) / 'tree'
        sync.git('worktree', 'add', '--detach', str(checkout), batch['base_sha'])
        try:
            os.chdir(checkout)
            if sync.merge(batch):
                return '', ['The complete batch has unresolved merge conflicts.']
            merged = sync.output('rev-parse', 'HEAD')
            unique, seen = [], set()
            for sha, patch in patches:
                # Identical adaptations proposed independently only need applying once.
                data = patch.read_bytes()
                if data in seen:
                    continue
                seen.add(data)
                sync.git('reset', '--hard', merged)
                sync.git('apply', '--index', str(patch))
                sync.clean_patch_paths(merged)
                sync.git('diff', '--cached', '--check')
                unique.append((sha, patch))
            sync.git('reset', '--hard', merged)
            for sha, patch in unique:
                result = sync.git('apply', '--3way', '--index', str(patch), check=False)
                if result.returncode:
                    conflicts = sync.output('diff', '--name-only', '--diff-filter=U').splitlines()
                    return '', ['Independent adaptations need reconciliation while applying ' + sha +
                                (': ' + ', '.join(conflicts) if conflicts else '. The patch could not be combined cleanly.')]
            sync.clean_patch_paths(merged)
            sync.git('diff', '--cached', '--check')
            combined = sync.git('diff', '--binary', merged).stdout
            if len(combined.encode()) > batch['limits']['max_patch_bytes']:
                raise ValueError('Combined adaptation patch exceeds size budget')
            return combined, []
        finally:
            os.chdir(original)
            sync.git('worktree', 'remove', '--force', str(checkout))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    collect(json.loads((args.out / 'plan.json').read_text()), args.out.resolve())

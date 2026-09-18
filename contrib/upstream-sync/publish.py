#!/usr/bin/env python3
"""Publish reviewed branches with GitHub's token; never run candidate code."""
import argparse
import json
import os
from pathlib import Path
import subprocess

import sync


def gh(*args):
    return subprocess.check_output(['gh', *args], text=True).strip()


def gate(folder):
    batch = json.loads((folder / 'plan.json').read_text())
    status = batch['status']
    prs = json.loads(gh('pr', 'list', '--state', 'open', '--limit', '100', '--json', 'headRefName,url'))
    pending = [p for p in prs if p['headRefName'].startswith('sync/julia-')]
    if pending and any(p['headRefName'] != batch['branch'] for p in pending):
        status = 'waiting'
    elif status == 'ready':
        if sync.output('ls-remote', '--heads', 'origin', 'refs/heads/' + batch['branch']):
            previous = json.loads(gh('pr', 'list', '--head', batch['branch'], '--state', 'all',
                                     '--json', 'state', '--limit', '100'))
            status = 'waiting' if any(p['state'] != 'OPEN' for p in previous) else 'existing'
    summary = (f'## Upstream sync: {status}\n\n'
               f'Checkpoint: `{batch["previous_sha"]}`\n\n'
               f'Fetched: `{batch["fetched_sha"]}`\n\n'
               f'Batch target: `{batch["target_sha"]}` ({len(batch["commits"])} commits)\n\n'
               + '\n'.join('- ' + s for s in batch['manual_reasons']) + '\n')
    for pr in pending:
        summary += f'\nPending sync: {pr["url"]}\n'
    (folder / 'summary.md').write_text(summary)
    with open(os.environ['GITHUB_OUTPUT'], 'a') as out:
        out.write(f'status={status}\n')


def publish(folder, status):
    batch = json.loads((folder / 'plan.json').read_text())
    expected_branch = f'sync/julia-{batch["previous_sha"][:12]}-{batch["target_sha"][:12]}'
    if batch['branch'] != expected_branch:
        raise ValueError('Unexpected branch name')
    branch = batch['branch']
    if status == 'existing':
        sync.git('fetch', 'origin', f'refs/heads/{branch}')
        sha = sync.output('rev-parse', 'FETCH_HEAD')
        record = json.loads(sync.output('show', f'{sha}:{sync.REPORTS}/{batch["target_sha"]}.json'))
        stored = record['plan']
        if (stored['target_sha'], stored['previous_sha'], stored['branch']) != (
                batch['target_sha'], batch['previous_sha'], branch):
            raise ValueError('Existing branch does not match this batch')
        sync.validate_review(stored, record['review'])
        integrated = record['integrated']
        expected_checkpoint = batch['target_sha'] if integrated else batch['previous_sha']
        state = json.loads(sync.output('show', f'{sha}:{sync.STATE}'))
        if state['integrated_sha'] != expected_checkpoint:
            raise ValueError('Existing branch has inconsistent checkpoint')
        if integrated:
            sync.git('merge-base', '--is-ancestor', batch['target_sha'], sha)
        (folder / 'pr.md').write_text(sync.render_body(stored, record['review'], integrated))
    else:
        candidate = json.loads((folder / 'candidate.json').read_text())
        sha, integrated = candidate['sha'], candidate['integrated']
        if candidate['branch'] != branch or sync.output('rev-parse', 'HEAD') != sha:
            raise ValueError('Unexpected candidate')
        sync.git('push', 'origin', f'{sha}:refs/heads/{branch}')
    prs = json.loads(gh('pr', 'list', '--head', branch, '--state', 'open', '--json', 'url'))
    if prs:
        url = prs[0]['url']
    else:
        url = gh('pr', 'create', '--base', 'master', '--head', branch, '--draft',
                 '--title', f'upstream: Review Julia through {batch["target_sha"][:12]}',
                 '--body-file', str(folder / 'pr.md'))
    print(url)
    if integrated:
        # GITHUB_TOKEN-created pushes/PRs do not trigger ordinary push/PR workflows.
        runs = json.loads(gh('run', 'list', '--workflow', 'joolia.yml', '--branch', branch,
                             '--commit', sha, '--limit', '1', '--json', 'databaseId'))
        if not runs:
            gh('workflow', 'run', 'joolia.yml', '--ref', branch)
            print('Dispatched Joolia CI on the exact candidate branch.')
        if os.environ.get('JOOLIA_UPSTREAM_AUTOMERGE_ENABLED') == 'true':
            gh('workflow', 'run', 'upstream-merge.yml', '--ref', 'master')
            print('Dispatched the trusted merge gate to approve eligible PR checks.')
    if 'GITHUB_STEP_SUMMARY' in os.environ:
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
            summary.write(f'\nDraft sync PR: {url}\n\nCandidate: `{sha}`\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('gate', 'publish'))
    parser.add_argument('--data', type=Path, required=True)
    parser.add_argument('--status', choices=('ready', 'existing'), default='ready')
    args = parser.parse_args()
    if args.command == 'gate':
        gate(args.data)
    else:
        publish(args.data, args.status)


if __name__ == '__main__':
    main()

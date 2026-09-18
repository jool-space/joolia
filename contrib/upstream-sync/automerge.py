#!/usr/bin/env python3
"""Merge validated sync PRs after dual-architecture CI; never execute candidate code."""
import json
import os
import re
import subprocess
import time

import sync
from publish import gh

REQUIRED = {'Upstream sync tooling', 'Build and test (ubuntu-24.04)',
            'Build and test (ubuntu-24.04-arm)'}
PR_WORKFLOWS = {'.github/workflows/joolia.yml', '.github/workflows/LabelCheck.yml',
                '.github/workflows/Typos.yml', '.github/workflows/Whitespace.yml'}
BRANCH = re.compile(r'sync/julia-([0-9a-f]{12})-([0-9a-f]{12})')


def api(path, method='GET', data=None):
    args = ['gh', 'api', f'repos/{os.environ["GH_REPO"]}/{path}', '--method', method]
    if data is not None:
        args += ['--input', '-']
    result = subprocess.run(args, input=None if data is None else json.dumps(data),
                            text=True, stdout=subprocess.PIPE, check=True)
    return json.loads(result.stdout) if result.stdout.strip() else None


def pages(path, key=None):
    result = []
    for page in range(1, 101):
        response = api(f'{path}{"&" if "?" in path else "?"}per_page=100&page={page}')
        items = response if key is None else response[key]
        result.extend(items)
        if len(items) < 100:
            return result
    raise ValueError('API pagination limit exceeded')


def eligible(pr, repo):
    return (pr['state'] == 'open' and pr['user']['login'] == 'github-actions[bot]' and
            pr['base']['ref'] == 'master' and pr['base']['repo']['full_name'] == repo and
            pr['head']['repo'] is not None and pr['head']['repo']['full_name'] == repo and
            BRANCH.fullmatch(pr['head']['ref']) is not None and
            not any(label['name'] in ('sync:hold', 'do not merge') for label in pr['labels']))


def validate_candidate(base, head, branch):
    """Read Git objects as data, including the report and protected-path diff."""
    changed = sync.output('diff', '--name-only', f'{base}...{head}').splitlines()
    reports = [p for p in changed if re.fullmatch(sync.REPORTS + r'/[0-9a-f]{40}\.json', p)]
    if len(reports) != 1:
        raise ValueError('Expected one batch report')
    record = json.loads(sync.output('show', f'{head}:{reports[0]}'))
    batch, review = record['plan'], record['review']
    sync.validate_review(batch, review)
    if record['integrated'] is not True or review['decision'] != 'propose':
        raise ValueError('Manual/report-only batch cannot auto-merge')
    expected = f'sync/julia-{batch["previous_sha"][:12]}-{batch["target_sha"][:12]}'
    if branch != expected or batch['branch'] != branch or batch['status'] != 'ready':
        raise ValueError('Unexpected batch identity')
    for field in ('base_sha', 'previous_sha', 'target_sha', 'fetched_sha'):
        if not sync.SHA.fullmatch(batch[field]):
            raise ValueError('Invalid batch SHA')
    if reports[0] != f'{sync.REPORTS}/{batch["target_sha"]}.json':
        raise ValueError('Report filename does not match target')
    for ancestor, descendant in ((batch['base_sha'], base), (batch['base_sha'], head),
                                 (batch['previous_sha'], batch['target_sha']),
                                 (batch['target_sha'], head)):
        sync.git('merge-base', '--is-ancestor', ancestor, descendant)
    if {c['sha'] for c in batch['commits']} != set(sync.commits_since(batch['previous_sha'], batch['target_sha'])):
        raise ValueError('Review does not cover actual incoming history')
    before = json.loads(sync.output('show', f'{base}:{sync.STATE}'))
    after = json.loads(sync.output('show', f'{head}:{sync.STATE}'))
    if before['integrated_sha'] != batch['previous_sha']:
        raise ValueError('Checkpoint has already moved')
    expected_state = dict(before, integrated_sha=batch['target_sha'])
    if after != expected_state:
        raise ValueError('Candidate changes more than the checkpoint')
    allowed = {sync.STATE, reports[0]}
    if any(sync.protected(p) and p not in allowed for p in changed):
        raise ValueError('Candidate changes protected automation or instructions')


def ci_passed(run, jobs, head, branch, workflow_id, repo):
    return (run['workflow_id'] == workflow_id and run['event'] == 'workflow_dispatch' and
            run['head_sha'] == head and run['head_branch'] == branch and
            run['head_repository']['full_name'] == repo and
            run['status'] == 'completed' and run['conclusion'] == 'success' and
            REQUIRED.issubset({j['name'] for j in jobs}) and
            all(j['status'] == 'completed' and j['conclusion'] == 'success' for j in jobs))


def dispatch_ci(branch):
    gh('workflow', 'run', 'joolia.yml', '--ref', branch)
    print(f'Dispatched both architectures on {branch}')


def approvable(run, pr, repo):
    return (eligible(pr, repo) and run['event'] == 'pull_request' and
            run['conclusion'] == 'action_required' and
            run['head_sha'] == pr['head']['sha'] and
            run['head_branch'] == pr['head']['ref'] and
            run['head_repository']['full_name'] == repo and
            run['path'] in PR_WORKFLOWS and
            any(p['number'] == pr['number'] and p['head']['sha'] == pr['head']['sha']
                for p in run['pull_requests']))


def approve_checks(pr, repo):
    # Call only after validating the candidate, including unchanged workflow files.
    runs = pages(f'actions/runs?head_sha={pr["head"]["sha"]}&event=pull_request', 'workflow_runs')
    for run in runs:
        if approvable(run, pr, repo):
            api(f'actions/runs/{run["id"]}/approve', 'POST')
            print(f'Approved {run["path"]} on validated sync PR {pr["number"]}.')


def advance(pr, workflow_id, repo):
    number, head, branch = pr['number'], pr['head']['sha'], pr['head']['ref']
    sync.git('fetch', '--no-tags', 'origin', 'master', f'refs/heads/{branch}')
    base = sync.output('rev-parse', 'refs/remotes/origin/master')
    validate_candidate(base, head, branch)
    if sync.git('merge-base', '--is-ancestor', base, head, check=False).returncode:
        api(f'pulls/{number}/update-branch', 'PUT', {'expected_head_sha': head})
        for _ in range(30):
            updated = api(f'pulls/{number}')
            if updated['head']['sha'] != head:
                print(f'Updated PR {number} with master; old CI cannot authorize merging.')
                sync.git('fetch', '--no-tags', 'origin', f'refs/heads/{branch}')
                validate_candidate(base, updated['head']['sha'], branch)
                approve_checks(updated, repo)
                dispatch_ci(branch)
                return
            time.sleep(2)
        raise RuntimeError('Branch update pending; retry the merge workflow to resume')

    approve_checks(pr, repo)
    runs = api(f'actions/workflows/{workflow_id}/runs?head_sha={head}&event=workflow_dispatch&per_page=1')['workflow_runs']
    if not runs:
        dispatch_ci(branch)
        return
    run = runs[0]
    jobs = pages(f'actions/runs/{run["id"]}/jobs?filter=latest', 'jobs')
    if not ci_passed(run, jobs, head, branch, workflow_id, repo):
        print(f'PR {number}: waiting for successful CI on both architectures (run {run["id"]}).')
        return
    # Respect failed/pending PR checks and external status integrations as well.
    for revision in dict.fromkeys([head, pr.get('merge_commit_sha')]):
        if revision is None:
            continue
        checks = pages(f'commits/{revision}/check-runs?filter=latest', 'check_runs')
        statuses = pages(f'commits/{revision}/statuses')
        latest = {}
        for status in statuses:
            latest.setdefault(status['context'], status['state'])
        if any(c['status'] != 'completed' or c['conclusion'] not in ('success', 'neutral', 'skipped') for c in checks) or any(s != 'success' for s in latest.values()):
            print(f'PR {number}: another check is pending or unsuccessful.')
            return
    current = api(f'pulls/{number}')
    if not eligible(current, repo) or current['head']['sha'] != head:
        raise ValueError('PR changed during validation')
    if api('git/ref/heads/master')['object']['sha'] != base:
        print('Master advanced during validation; retry with the new base.')
        return
    # Strict required checks configured on master close the base-movement race.
    # The read-only branch API exposes enforcement/contexts, not the strict flag.
    protection = api('branches/master')['protection']
    required = protection['required_status_checks']
    if not protection['enabled'] or required['enforcement_level'] != 'everyone' or not {'Upstream sync tooling', 'Build and test (ubuntu-24.04)'}.issubset(set(required['contexts'])):
        raise ValueError('Required checks must be enforced for everyone')
    if current['draft']:
        gh('pr', 'ready', str(number))
    result = api(f'pulls/{number}/merge', 'PUT', {'sha': head, 'merge_method': 'merge',
                  'commit_title': f'upstream: Integrate reviewed batch ({branch.rsplit("-", 1)[1]})'})
    if not result['merged']:
        raise RuntimeError(result['message'])
    print(f'Merged PR {number}: {result["sha"]}')
    if os.environ.get('JOOLIA_UPSTREAM_SYNC_ENABLED') == 'true':
        gh('workflow', 'run', 'upstream-sync.yml', '--ref', 'master', '-f', 'mode=propose')
        print('Dispatched the next batch immediately.')


def main():
    repo = os.environ['GH_REPO']
    if os.environ.get('JOOLIA_UPSTREAM_AUTOMERGE_ENABLED') != 'true':
        print('Automatic sync merging is disabled.')
        return
    workflow_id = api('actions/workflows/joolia.yml')['id']
    for summary in pages('pulls?state=open&base=master'):
        if eligible(summary, repo):
            advance(api(f'pulls/{summary["number"]}'), workflow_id, repo)


if __name__ == '__main__':
    main()

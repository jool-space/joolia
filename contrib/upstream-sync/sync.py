#!/usr/bin/env python3
"""Plan, validate and assemble bounded upstream syncs; never execute incoming code."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

STATE = 'contrib/upstream-sync/state.json'
REPORTS = 'contrib/upstream-sync/reports'
UPSTREAM = 'https://github.com/JuliaLang/julia.git'
SHA = re.compile(r'[0-9a-f]{40}')
PROTECTED = ('.github/', '.codex/', '.agents/', '.claude/', 'doc/src/devdocs/agents/',
             'contrib/ci/', 'contrib/upstream-sync/')
TRAILER = 'Assisted-by: Codex (GPT-5.6 Luna)'
GUIDES = ('review-method.md', 'subsystems.md', 'validation.md')


def git(*args, check=True):
    return subprocess.run(['git', '-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgsign=false',
                           *args], check=check, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True)


def output(*args):
    return git(*args).stdout.strip()


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + '\n')


def protected(path):
    return (path.startswith(PROTECTED) or path in ('AGENTS.md', '.gitmodules') or
            path.endswith(('/AGENTS.md', '/SKILL.md')) or path == 'SKILL.md')


def commits_since(previous, target):
    return output('rev-list', '--reverse', '--topo-order', f'{previous}..{target}').splitlines()


def commit_info(sha):
    parent = output('rev-parse', sha + '^1')
    paths = output('diff', '--name-only', parent, sha).splitlines()
    stats = output('diff', '--numstat', parent, sha).splitlines()
    binary = any(line.split('\t', 2)[0] == '-' for line in stats)
    lines = sum(int(a) + int(b) for a, b, _ in (line.split('\t', 2) for line in stats)
                if a != '-')
    patch = git('diff', '--binary', parent, sha).stdout
    return {'sha': sha, 'subject': output('show', '-s', '--format=%s', sha), 'paths': paths,
            'changed_lines': lines, 'patch_bytes': len(patch.encode()), 'binary': binary}


def version_value(text, suffix):
    matches = re.findall(r'^\w+_' + suffix + r'\s*:?=\s*(\S+)\s*$', text, re.M)
    return matches[0] if len(matches) == 1 else None


def stdlib_updates(base, previous, target):
    updates = []
    for path in output('diff', '--name-only', previous, target, '--', 'stdlib/*.version').splitlines():
        name = Path(path).stem
        if not re.fullmatch('[A-Za-z][A-Za-z0-9]*', name):
            raise ValueError('Invalid stdlib name')
        old = git('show', f'{base}:{path}', check=False).stdout
        new = git('show', f'{target}:{path}', check=False).stdout
        history = output('log', base, '-1', '--format=%B', '--grep=^git-subtree-dir: stdlib/' + name + '$')
        match = re.search(r'^git-subtree-split: ([0-9a-f]{40})$', history, re.M)
        actual = match.group(1) if match else None
        recommended = version_value(new, 'SHA1')
        url = version_value(new, 'GIT_URL')
        previous_url = version_value(old, 'GIT_URL')
        command = None
        if recommended and SHA.fullmatch(recommended) and url == previous_url and actual:
            command = f'contrib/bump_stdlib.sh -b {recommended} {name}'
        updates.append({'name': name, 'recommended_sha': recommended, 'imported_sha': actual,
                        'repository': url, 'suggested_command': command,
                        'requires_import': actual != recommended or url != previous_url})
    return updates


def plan(target, state_path=STATE):
    state = json.loads(Path(state_path).read_text())
    if state['upstream'] != UPSTREAM or state['branch'] != 'master':
        raise ValueError('Unexpected upstream repository or branch')
    previous = state['integrated_sha']
    if not SHA.fullmatch(previous):
        raise ValueError('Checkpoint must be a full commit SHA')
    target = output('rev-parse', '--verify', target + '^{commit}')
    base = output('rev-parse', 'HEAD')
    for descendant in (base, target):
        if git('merge-base', '--is-ancestor', previous, descendant, check=False).returncode:
            raise ValueError('Checkpoint is not an ancestor; do not squash upstream sync merges')
    first_parents = output('rev-list', '--first-parent', '--reverse', f'{previous}..{target}').splitlines()
    selected, tip, status, reasons = [], previous, 'empty', []
    cache = {}
    for candidate in first_parents:
        incoming = commits_since(previous, candidate)
        for sha in incoming:
            if sha not in cache:
                cache[sha] = commit_info(sha)
        infos = [cache[sha] for sha in incoming]
        exceeds = (len(infos) > state['max_commits'] or
                   sum(c['changed_lines'] for c in infos) > state['max_changed_lines'] or
                   sum(c['patch_bytes'] for c in infos) > state['max_patch_bytes'] or
                   any(c['binary'] for c in infos))
        if exceeds:
            if not selected:
                selected, tip, status = infos, candidate, 'blocked'
                reasons.append('The first upstream group exceeds the batch limits or includes binary changes.')
            break
        selected, tip, status = infos, candidate, 'ready'
    updates = stdlib_updates(base, previous, tip)
    if any(protected(p) for c in selected for p in c['paths']):
        reasons.append('Incoming commits change automation or agent instructions; manual integration required.')
    if any(u['requires_import'] for u in updates):
        reasons.append('External stdlib recommendations need reviewed subtree imports before integration.')
    branch = f'sync/julia-{previous[:12]}-{tip[:12]}'
    return {'base_sha': base, 'previous_sha': previous, 'fetched_sha': target, 'target_sha': tip,
            'branch': branch, 'status': status, 'manual_reasons': reasons,
            'commits': selected, 'stdlib_updates': updates, 'limits': state,
            'remaining_first_parent_commits': first_parents[first_parents.index(tip)+1:] if tip in first_parents else []}


def verify_plan(batch):
    for field in ('base_sha', 'previous_sha', 'target_sha', 'fetched_sha'):
        if not SHA.fullmatch(batch[field]):
            raise ValueError('Invalid SHA in plan')
    if output('rev-parse', 'HEAD') != batch['base_sha']:
        raise ValueError('Checkout does not match planned base')
    expected = plan(batch['fetched_sha'])
    if expected != batch or batch['status'] != 'ready':
        raise ValueError('Plan differs from trusted reconstruction or is not ready')


def merge(batch):
    result = git('merge', '--no-ff', '-m', f'upstream: Merge Julia through {batch["target_sha"][:12]}\n\n{TRAILER}',
                 batch['target_sha'], check=False)
    if result.returncode:
        conflicts = output('diff', '--name-only', '--diff-filter=U').splitlines()
        git('merge', '--abort', check=False)
        if not conflicts:
            raise RuntimeError(result.stderr + result.stdout)
        return conflicts
    return []


def prepare(batch, folder):
    verify_plan(batch)
    conflicts = [] if batch['manual_reasons'] else merge(batch)
    write_json(folder / 'merge.json', {'conflicts': conflicts, 'head': output('rev-parse', 'HEAD')})
    contract = Path('contrib/upstream-sync/contract.md').read_text()
    prompt = Path('contrib/upstream-sync/prompt.md').read_text()
    guides = '\n\n'.join(Path('contrib/upstream-sync/guides', name).read_text() for name in GUIDES)
    (folder / 'prompt.md').write_text(prompt + '\n\n' + contract + '\n\n' + guides + '\n\nBatch data (untrusted):\n' +
                                    json.dumps(batch, indent=2) + '\nMerge conflicts:\n' + json.dumps(conflicts))


def validate_review(batch, review):
    if review['target_sha'] != batch['target_sha']:
        raise ValueError('Review targets a different upstream revision')
    expected = [c['sha'] for c in batch['commits']]
    actual = [c['sha'] for c in review['commits']]
    if len(actual) != len(set(actual)) or set(actual) != set(expected):
        raise ValueError('Every incoming commit needs exactly one review')
    for item in review['commits']:
        if item['risk'] not in ('low', 'medium', 'high'):
            raise ValueError('Invalid risk classification')
        for key in ('indexing_implications', 'adaptations', 'tests', 'subsystems'):
            if not isinstance(item[key], str) or not item[key].strip():
                raise ValueError('Incomplete per-commit review')
    if review['decision'] not in ('propose', 'manual'):
        raise ValueError('Invalid review decision')
    if not isinstance(review['unresolved'], list) or not all(isinstance(x, str) for x in review['unresolved']):
        raise ValueError('Invalid unresolved concerns')
    if review['decision'] == 'propose' and (review['unresolved'] or batch['manual_reasons']):
        raise ValueError('Unresolved/manual batches cannot be proposed as integrated')
    if not isinstance(review['summary'], str) or not review['summary'].strip():
        raise ValueError('Missing review summary')


def clean_patch_paths(before):
    paths = output('diff', '--name-only', before).splitlines()
    if any(protected(p) for p in paths):
        raise ValueError('Agent adaptations cannot modify automation or agent instructions')
    for line in output('diff', '--raw', before).splitlines():
        mode = line.split()[1]
        if mode not in ('000000', '100644', '100755'):
            raise ValueError('Agent adaptations cannot introduce symlinks or submodules')
    return paths


def assemble(batch, folder):
    verify_plan(batch)
    review = json.loads((folder / 'review.json').read_text())
    validate_review(batch, review)
    git('switch', '-c', batch['branch'])
    integrated = review['decision'] == 'propose'
    if integrated:
        if merge(batch):
            raise ValueError('Cannot integrate a batch with unresolved merge conflicts')
        before = output('rev-parse', 'HEAD')
        patch = folder / 'adaptations.patch'
        if patch.stat().st_size > batch['limits']['max_patch_bytes']:
            raise ValueError('Adaptation patch exceeds size budget')
        if patch.stat().st_size:
            git('apply', '--index', str(patch.resolve()))
            clean_patch_paths(before)
            git('diff', '--cached', '--check')
            git('commit', '-m', 'joolia: Adapt upstream batch to zero-origin semantics', '-m', TRAILER)
        state = json.loads(Path(STATE).read_text())
        state['integrated_sha'] = batch['target_sha']
        write_json(STATE, state)
    report_path = f'{REPORTS}/{batch["target_sha"]}.json'
    write_json(report_path, {'plan': batch, 'review': review, 'integrated': integrated})
    git('add', '--', report_path, STATE)
    git('commit', '-m', 'upstream: Record reviewed sync batch' if integrated else 'upstream: Record batch requiring manual integration',
        '-m', TRAILER)
    body = render_body(batch, review, integrated)
    (folder / 'pr.md').write_text(body)
    write_json(folder / 'candidate.json', {'sha': output('rev-parse', 'HEAD'), 'branch': batch['branch'],
                                         'integrated': integrated})


def without_upstream_references(text):
    """Keep descriptions from creating upstream issue/PR/commit cross-references."""
    url = r'https?://(?:www\.)?github\.com/[^/\s)<>\]]+/[^/\s)<>\]]+/(?:pull|issues|commit)/[^\s)<>\]]+'
    text = re.sub(r'\[([^\]]*)\]\(' + url + r'\)', r'\1', text, flags=re.I)
    text = re.sub(url, 'upstream change', text, flags=re.I)
    text = re.sub(r'\b[\w.-]+/[\w.-]+#(\d+)\b', r'upstream change \1', text)
    text = re.sub(r'Merge pull request #\d+ from ', 'Merge upstream branch ', text)
    return re.sub(r'(?<![\w])#(\d+)\b', r'change \1', text)


def render_body(batch, review, integrated):
    text = [f'Upstream Julia `{batch["previous_sha"]}` → `{batch["target_sha"]}`.', '', review['summary'], '',
            'Draft for human review. Automatic merging is disabled.', '',
            ('The upstream history is preserved in a merge commit; any Joolia adaptations are committed separately. '
             'The publisher explicitly dispatches Joolia CI on this branch; inspect its result before merging.' if integrated else
             'REPORT ONLY: upstream code and the integrated checkpoint are unchanged. Resolve the concerns before integrating.'), '',
            f'Review record: `{REPORTS}/{batch["target_sha"]}.json`.', '', 'Incoming commits:', '']
    for item in batch['commits']:
        text.append(f'- `{item["sha"]}` — {item["subject"]}')
    if batch['stdlib_updates']:
        text.extend(['', 'External stdlib revisions:', ''])
        for item in batch['stdlib_updates']:
            text.append(f'- {item["name"]}: recommended `{item["recommended_sha"]}`, imported `{item["imported_sha"]}`. '
                        f'Proposed command: `{item["suggested_command"]}`.')
    concerns = batch['manual_reasons'] + review['unresolved']
    if concerns:
        text.extend(['', 'Unresolved concerns:', ''] + ['- ' + s for s in concerns])
    text.extend(['', 'Merge integrated batches with a merge commit, never squash/rebase, to preserve the upstream ancestry.',
                 'Passing CI covers only `contrib/ci/coverage.json`; it does not certify the entire port.'])
    return without_upstream_references('\n'.join(text) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('plan', 'prepare', 'assemble'))
    parser.add_argument('--upstream', default='refs/remotes/upstream/master')
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    if args.command == 'plan':
        batch = plan(args.upstream)
        write_json(args.out / 'plan.json', batch)
        print(json.dumps(batch, indent=2))
        if 'GITHUB_OUTPUT' in os.environ:
            with open(os.environ['GITHUB_OUTPUT'], 'a') as output_file:
                output_file.write(f'status={batch["status"]}\nbranch={batch["branch"]}\n')
    else:
        batch = json.loads((args.out / 'plan.json').read_text())
        {'prepare': prepare, 'assemble': assemble}[args.command](batch, args.out)


if __name__ == '__main__':
    main()

"""Exercise batch boundaries, complete reviews and merge/checkpoint behavior using real Git histories."""
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import sync
import publish
import automerge

GUIDE_ROOT = Path(__file__).resolve().parent


class SyncTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        previous = Path.cwd()
        os.chdir(self.repo)
        self.addCleanup(os.chdir, previous)
        sync.git('init', '-q', '-b', 'upstream')
        sync.git('config', 'user.name', 'CI Test')
        sync.git('config', 'user.email', 'ci@example.invalid')
        self.commit('initial', 'base.txt', 'base\n')
        self.initial = sync.output('rev-parse', 'HEAD')
        self.commit('first upstream', 'base.txt', 'base\nupstream\n')
        self.first = sync.output('rev-parse', 'HEAD')
        self.commit('second upstream', 'second.txt', 'second\n')
        self.tip = sync.output('rev-parse', 'HEAD')
        sync.git('switch', '-q', '-c', 'master', self.initial)
        state = {'upstream': sync.UPSTREAM, 'branch': 'master', 'integrated_sha': self.initial,
                 'max_commits': 20, 'max_changed_lines': 2500, 'max_patch_bytes': 250000}
        sync.write_json(sync.STATE, state)
        self.commit('fork configuration')
        self.base = sync.output('rev-parse', 'HEAD')
        self.folder = self.root / 'data'
        self.folder.mkdir()

    def commit(self, message, path=None, text=None):
        if path:
            dest = Path(path)
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(text)
        sync.git('add', '.')
        sync.git('commit', '-qm', message)

    def review(self, batch, decision='propose'):
        return {'target_sha': batch['target_sha'], 'decision': decision, 'summary': 'Reviewed.',
                'unresolved': [] if decision == 'propose' else ['Needs manual adaptation.'],
                'commits': [{'sha': c['sha'], 'risk': 'low', 'subsystems': 'test fixture',
                             'indexing_implications': 'No index changes.', 'adaptations': 'None needed.',
                             'tests': 'Run the required gate.'} for c in batch['commits']]}

    def config(self, **values):
        state = json.loads(Path(sync.STATE).read_text())
        state.update(values)
        sync.write_json(sync.STATE, state)
        self.commit('configure limits')

    def test_empty_batch(self):
        self.assertEqual(sync.plan(self.initial)['status'], 'empty')

    def test_bounded_batch_does_not_skip_commits(self):
        self.config(max_commits=1)
        batch = sync.plan(self.tip)
        self.assertEqual(batch['target_sha'], self.first)
        self.assertEqual([c['sha'] for c in batch['commits']], [self.first])
        self.assertEqual(batch['remaining_first_parent_commits'], [self.tip])

    def test_merge_group_is_indivisible(self):
        sync.git('switch', '-q', '-c', 'side', self.initial)
        self.commit('side a', 'side.txt', 'a\n')
        a = sync.output('rev-parse', 'HEAD')
        self.commit('side b', 'side.txt', 'b\n')
        b = sync.output('rev-parse', 'HEAD')
        sync.git('switch', '-q', 'upstream')
        sync.git('merge', '--no-ff', '-qm', 'merge side', 'side')
        target = sync.output('rev-parse', 'HEAD')
        sync.git('switch', '-q', 'master')
        self.config(max_commits=4)
        batch = sync.plan(target)
        self.assertEqual(batch['target_sha'], self.tip)
        self.config(max_commits=5)
        batch = sync.plan(target)
        self.assertTrue({a, b, target}.issubset({c['sha'] for c in batch['commits']}))

    def test_oversized_first_group_blocks(self):
        self.config(max_changed_lines=0)
        self.assertEqual(sync.plan(self.tip)['status'], 'blocked')

    def test_runtime_group_isolated(self):
        sync.git('switch', '-q', 'upstream')
        self.commit('runtime', 'src/example.c', 'runtime\n')
        target = sync.output('rev-parse', 'HEAD')
        sync.git('switch', '-q', 'master')
        self.assertEqual(sync.plan(target)['target_sha'], self.tip)

    def test_checkpoint_must_be_merged(self):
        self.config(integrated_sha=self.first)
        with self.assertRaisesRegex(ValueError, 'ancestor'):
            sync.plan(self.tip)

    def test_missing_and_duplicate_reviews_rejected(self):
        batch = sync.plan(self.tip)
        review = self.review(batch)
        review['commits'].pop()
        with self.assertRaises(ValueError):
            sync.validate_review(batch, review)
        review['commits'] *= 2
        with self.assertRaises(ValueError):
            sync.validate_review(batch, review)

    def test_forged_plan_rejected(self):
        batch = sync.plan(self.tip)
        batch['commits'][0]['paths'] = []
        with self.assertRaises(ValueError):
            sync.verify_plan(batch)

    def test_automation_changes_require_manual(self):
        sync.git('switch', '-q', 'upstream')
        self.commit('workflow', '.github/workflows/upstream.yml', 'name: upstream\n')
        target = sync.output('rev-parse', 'HEAD')
        sync.git('switch', '-q', 'master')
        batch = sync.plan(target)
        self.assertTrue(batch['manual_reasons'])
        with self.assertRaises(ValueError):
            sync.validate_review(batch, self.review(batch))

    def test_merge_conflicts_abort_cleanly(self):
        self.commit('fork modification', 'base.txt', 'fork\n')
        batch = sync.plan(self.tip)
        self.assertEqual(sync.merge(batch), ['base.txt'])
        self.assertEqual(sync.output('rev-parse', 'HEAD'), batch['base_sha'])
        self.assertEqual(sync.output('status', '--porcelain'), '')

    def test_integrated_candidate_preserves_ancestry(self):
        batch = sync.plan(self.tip)
        sync.write_json(self.folder / 'review.json', self.review(batch))
        (self.folder / 'adaptations.patch').write_text('')
        sync.assemble(batch, self.folder)
        sync.git('merge-base', '--is-ancestor', self.tip, 'HEAD')
        self.assertEqual(json.loads(Path(sync.STATE).read_text())['integrated_sha'], self.tip)
        self.assertEqual(json.loads(sync.output('show', f'master:{sync.STATE}'))['integrated_sha'], self.initial)
        self.assertEqual(sync.output('rev-list', '--count', f'{self.base}..HEAD'), '4')

    def test_manual_report_does_not_advance_checkpoint(self):
        batch = sync.plan(self.tip)
        sync.write_json(self.folder / 'review.json', self.review(batch, 'manual'))
        sync.assemble(batch, self.folder)
        self.assertEqual(json.loads(Path(sync.STATE).read_text())['integrated_sha'], self.initial)
        self.assertNotEqual(sync.git('merge-base', '--is-ancestor', self.tip, 'HEAD', check=False).returncode, 0)

    def test_adaptation_cannot_change_workflows(self):
        batch = sync.plan(self.tip)
        sync.write_json(self.folder / 'review.json', self.review(batch))
        (self.folder / 'adaptations.patch').write_text('''diff --git a/.github/workflows/evil.yml b/.github/workflows/evil.yml
new file mode 100644
index 0000000..9daeafb
--- /dev/null
+++ b/.github/workflows/evil.yml
@@ -0,0 +1 @@
+test
''')
        with self.assertRaisesRegex(ValueError, 'automation'):
            sync.assemble(batch, self.folder)

    def test_stdlib_recommendation_records_actual_import(self):
        imported, recommended = '1' * 40, '2' * 40
        version = 'PKG_SHA1 = {}\nPKG_GIT_URL := https://github.com/JuliaLang/Pkg.jl.git\n'
        self.commit('import\n\ngit-subtree-dir: stdlib/Pkg\ngit-subtree-split: ' + imported,
                    'stdlib/Pkg.version', version.format(imported))
        sync.git('switch', '-q', 'upstream')
        self.commit('bump', 'stdlib/Pkg.version', version.format(recommended))
        target = sync.output('rev-parse', 'HEAD')
        sync.git('switch', '-q', 'master')
        batch = sync.plan(target)
        update = batch['stdlib_updates'][0]
        self.assertEqual(update['imported_sha'], imported)
        self.assertEqual(update['recommended_sha'], recommended)
        self.assertIn(recommended, update['suggested_command'])
        self.assertTrue(batch['manual_reasons'])

    def test_safe_adaptation_is_a_separate_commit(self):
        batch = sync.plan(self.tip)
        sync.write_json(self.folder / 'review.json', self.review(batch))
        (self.folder / 'adaptations.patch').write_text("diff --git a/base.txt b/base.txt\n--- a/base.txt\n+++ b/base.txt\n@@ -1,2 +1,2 @@\n base\n-upstream\n+joolia\n")
        sync.assemble(batch, self.folder)
        self.assertEqual(Path('base.txt').read_text(), 'base\njoolia\n')
        self.assertEqual(sync.output('show', '-s', '--format=%s', 'HEAD~1'),
                         'joolia: Adapt upstream batch to zero-origin semantics')
        self.assertEqual(len(sync.output('show', '-s', '--format=%P', 'HEAD~2').split()), 2)

    def test_retry_reuses_published_branch_and_does_not_redispatch(self):
        batch = sync.plan(self.tip)
        sync.write_json(self.folder / 'plan.json', batch)
        sync.write_json(self.folder / 'review.json', self.review(batch))
        (self.folder / 'adaptations.patch').write_text('')
        sync.assemble(batch, self.folder)
        remote = self.root / 'remote.git'
        sync.git('init', '--bare', '-q', str(remote))
        sync.git('remote', 'add', 'origin', str(remote))
        sync.git('push', '-q', 'origin', batch['branch'])
        sync.git('switch', '-q', 'master')
        def responses(*args):
            if args[:2] == ('pr', 'list'):
                return '[{"url": "https://example.invalid/pr/1"}]'
            if args[:2] == ('run', 'list'):
                return '[{"databaseId": 1}]'
            self.fail(f'Unexpected GitHub call: {args}')
        with patch.object(publish, 'gh', side_effect=responses) as mocked:
            publish.publish(self.folder, 'existing')
        self.assertEqual(mocked.call_count, 2)

    def test_publication_explicitly_dispatches_ci(self):
        batch = sync.plan(self.tip)
        sync.write_json(self.folder / 'plan.json', batch)
        sync.write_json(self.folder / 'review.json', self.review(batch))
        (self.folder / 'adaptations.patch').write_text('')
        sync.assemble(batch, self.folder)
        remote = self.root / 'remote.git'
        sync.git('init', '--bare', '-q', str(remote))
        sync.git('remote', 'add', 'origin', str(remote))
        with patch.object(publish, 'gh', side_effect=['[]', 'https://example.invalid/pr/1', '[]', '']) as mocked:
            publish.publish(self.folder, 'ready')
        self.assertEqual(mocked.call_args.args, ('workflow', 'run', 'joolia.yml', '--ref', batch['branch']))
        self.assertIn('--draft', mocked.call_args_list[1].args)

    def test_publication_starts_approval_gate_when_enabled(self):
        batch, _ = self.candidate()
        sync.write_json(self.folder / 'plan.json', batch)
        remote = self.root / 'remote.git'
        sync.git('init', '--bare', '-q', str(remote))
        sync.git('remote', 'add', 'origin', str(remote))
        with patch.object(publish, 'gh', side_effect=['[]', 'https://example.invalid/pr/1', '[]', '', '']) as calls, \
                patch.dict(os.environ, {'JOOLIA_UPSTREAM_AUTOMERGE_ENABLED': 'true'}):
            publish.publish(self.folder, 'ready')
        self.assertEqual(calls.call_args.args, ('workflow', 'run', 'upstream-merge.yml', '--ref', 'master'))

    def test_prompt_embeds_all_porting_guides(self):
        for relative in ('prompt.md', 'contract.md', *(f'guides/{name}' for name in sync.GUIDES)):
            dest = Path('contrib/upstream-sync', relative)
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text((GUIDE_ROOT / relative).read_text())
        self.commit('add trusted guides')
        batch = sync.plan(self.tip)
        sync.prepare(batch, self.folder)
        prompt = (self.folder / 'prompt.md').read_text()
        for name in sync.GUIDES:
            self.assertIn((GUIDE_ROOT / 'guides' / name).read_text(), prompt)
        self.assertIn(batch['target_sha'], prompt)

    def test_pr_body_does_not_reference_upstream(self):
        batch = sync.plan(self.tip)
        batch['commits'][0]['subject'] = 'Merge pull request #123 from author/fix'
        batch['commits'][1]['subject'] = 'Fix indexing (#456) JuliaLang/julia#789'
        review = self.review(batch, 'manual')
        review['summary'] = 'See [upstream PR](https://github.com/JuliaLang/julia/pull/123) and JuliaLang/Pkg.jl#456.'
        review['unresolved'] = ['https://github.com/JuliaLang/julia/issues/42',
                                'https://github.com/JuliaLang/julia/commit/' + self.first]
        body = sync.render_body(batch, review, False)
        self.assertNotIn('github.com/JuliaLang', body)
        self.assertNotRegex(body, r'#[0-9]+')
        self.assertIn('`' + self.first + '`', body)
        self.assertIn('Merge upstream branch author/fix', body)
        self.assertIn('JuliaLang/Pkg.jl#456', review['summary'])  # Source report is preserved.

    def candidate(self):
        batch = sync.plan(self.tip)
        sync.write_json(self.folder / 'review.json', self.review(batch))
        (self.folder / 'adaptations.patch').write_text('')
        sync.assemble(batch, self.folder)
        return batch, sync.output('rev-parse', 'HEAD')

    def test_automerge_validates_real_candidate(self):
        batch, head = self.candidate()
        automerge.validate_candidate(self.base, head, batch['branch'])

    def test_automerge_rejects_changed_automation(self):
        batch, _ = self.candidate()
        self.commit('tamper', '.github/workflows/joolia.yml', 'jobs: {}\n')
        with self.assertRaisesRegex(ValueError, 'protected'):
            automerge.validate_candidate(self.base, sync.output('rev-parse', 'HEAD'), batch['branch'])

    def test_automerge_rejects_altered_checkpoint_settings(self):
        batch, _ = self.candidate()
        self.config(max_commits=1000)
        with self.assertRaisesRegex(ValueError, 'more than the checkpoint'):
            automerge.validate_candidate(self.base, sync.output('rev-parse', 'HEAD'), batch['branch'])

    def test_automerge_rejects_incomplete_actual_history(self):
        batch, _ = self.candidate()
        path = f'{sync.REPORTS}/{self.tip}.json'
        record = json.loads(Path(path).read_text())
        record['plan']['commits'].pop()
        record['review']['commits'].pop()
        sync.write_json(path, record)
        self.commit('incomplete report')
        with self.assertRaisesRegex(ValueError, 'actual incoming history'):
            automerge.validate_candidate(self.base, sync.output('rev-parse', 'HEAD'), batch['branch'])

    def test_automerge_rejects_manual_report(self):
        batch = sync.plan(self.tip)
        sync.write_json(self.folder / 'review.json', self.review(batch, 'manual'))
        sync.assemble(batch, self.folder)
        with self.assertRaisesRegex(ValueError, 'Manual/report-only'):
            automerge.validate_candidate(self.base, sync.output('rev-parse', 'HEAD'), batch['branch'])

    def test_ci_gate_requires_exact_head_and_both_architectures(self):
        run = dict(workflow_id=12, event='workflow_dispatch', head_sha=self.tip,
                   head_branch='sync/julia-test', head_repository={'full_name': 'jool-space/joolia'},
                   status='completed', conclusion='success')
        jobs = [dict(name=name, status='completed', conclusion='success') for name in automerge.REQUIRED]
        def passed(r=run, j=jobs):
            return automerge.ci_passed(r, j, self.tip, 'sync/julia-test', 12, 'jool-space/joolia')
        self.assertTrue(passed())
        for change in ({'head_sha': self.first}, {'workflow_id': 13}, {'event': 'pull_request'},
                       {'status': 'in_progress'}, {'conclusion': 'failure'},
                       {'head_repository': {'full_name': 'somebody/fork'}}):
            with self.subTest(change=change):
                self.assertFalse(passed(dict(run, **change)))
        self.assertFalse(passed(j=[j for j in jobs if j['name'] != 'Build and test (ubuntu-24.04-arm)']))
        for result in ('skipped', 'cancelled', 'failure'):
            self.assertFalse(passed(j=[dict(j, conclusion=result) for j in jobs]))

    def test_merge_gate_excludes_forks_other_authors_and_holds(self):
        repo = 'jool-space/joolia'
        pr = dict(state='open', user={'login': 'github-actions[bot]'}, labels=[],
                  base={'ref': 'master', 'repo': {'full_name': repo}},
                  head={'ref': 'sync/julia-' + 'a'*12 + '-' + 'b'*12, 'repo': {'full_name': repo}})
        self.assertTrue(automerge.eligible(pr, repo))
        for change in ({'labels': [{'name': 'sync:hold'}]}, {'user': {'login': 'someone'}},
                       {'head': dict(pr['head'], repo={'full_name': 'somebody/fork'})},
                       {'state': 'closed'}):
            self.assertFalse(automerge.eligible(dict(pr, **change), repo))

    def approval_fixture(self):
        repo = 'jool-space/joolia'
        pr = dict(number=1, state='open', user={'login': 'github-actions[bot]'}, labels=[],
                  base={'ref': 'master', 'repo': {'full_name': repo}},
                  head={'ref': 'sync/julia-' + 'a'*12 + '-' + 'b'*12,
                        'sha': self.tip, 'repo': {'full_name': repo}})
        run = dict(id=7, event='pull_request', conclusion='action_required',
                   head_sha=self.tip, head_branch=pr['head']['ref'],
                   head_repository={'full_name': repo}, path='.github/workflows/joolia.yml',
                   pull_requests=[{'number': 1, 'head': {'sha': self.tip}}])
        return repo, pr, run

    def test_workflow_approval_is_limited_to_current_trusted_sync(self):
        repo, pr, run = self.approval_fixture()
        self.assertTrue(automerge.approvable(run, pr, repo))
        for change in ({'head_sha': self.first}, {'head_branch': 'other'},
                       {'head_repository': {'full_name': 'someone/fork'}},
                       {'path': '.github/workflows/upstream-sync.yml'},
                       {'event': 'workflow_dispatch'}, {'conclusion': 'failure'},
                       {'pull_requests': []},
                       {'pull_requests': [{'number': 2, 'head': {'sha': self.tip}}]}):
            with self.subTest(change=change):
                self.assertFalse(automerge.approvable(dict(run, **change), pr, repo))
        self.assertFalse(automerge.approvable(run, dict(pr, labels=[{'name': 'sync:hold'}]), repo))
        self.assertFalse(automerge.approvable(run, dict(pr, user={'login': 'someone'}), repo))

    def test_approve_checks_only_approves_eligible_run(self):
        repo, pr, run = self.approval_fixture()
        with patch.object(automerge, 'pages', return_value=[run, dict(run, head_sha=self.first)]), \
                patch.object(automerge, 'api') as calls:
            automerge.approve_checks(pr, repo)
        calls.assert_called_once_with('actions/runs/7/approve', 'POST')

    def test_invalid_candidate_is_never_approved(self):
        repo, pr, _ = self.approval_fixture()
        with patch.object(sync, 'git'), patch.object(sync, 'output', return_value=self.base), \
                patch.object(automerge, 'validate_candidate', side_effect=ValueError('invalid candidate')), \
                patch.object(automerge, 'approve_checks') as approvals:
            with self.assertRaisesRegex(ValueError, 'invalid candidate'):
                automerge.advance(pr, 12, repo)
        approvals.assert_not_called()

    def test_master_advance_updates_branch_and_retests_without_merging(self):
        batch, head = self.candidate()
        pr = dict(number=1, head={'ref': batch['branch'], 'sha': head})
        sync.git('switch', '-q', 'master')
        self.commit('new fork change', 'new.txt', 'new\n')
        base = sync.output('rev-parse', 'HEAD')
        original_output, original_git = sync.output, sync.git
        def output(*args):
            return base if args == ('rev-parse', 'refs/remotes/origin/master') else original_output(*args)
        def git(*args, **kwargs):
            if args[0] == 'fetch':
                return None
            return original_git(*args, **kwargs)
        with patch.object(automerge, 'api', side_effect=[{}, {'head': {'sha': 'a'*40}}]) as calls, \
                patch.object(automerge, 'validate_candidate') as validated, \
                patch.object(automerge, 'approve_checks') as approvals, \
                patch.object(sync, 'git', side_effect=git), patch.object(sync, 'output', side_effect=output), \
                patch.object(automerge, 'gh') as dispatched:
            automerge.advance(pr, 12, 'jool-space/joolia')
        self.assertEqual(calls.call_args_list[0].args,
                         ('pulls/1/update-branch', 'PUT', {'expected_head_sha': head}))
        self.assertEqual(calls.call_count, 2)
        self.assertEqual(validated.call_count, 2)
        validated.assert_called_with(base, 'a'*40, batch['branch'])
        approvals.assert_called_once()
        self.assertEqual(dispatched.call_args.args, ('workflow', 'run', 'joolia.yml', '--ref', batch['branch']))

    def test_successful_merge_immediately_dispatches_next_batch(self):
        batch, head = self.candidate()
        repo = 'jool-space/joolia'
        pr = dict(number=1, state='open', draft=True, user={'login': 'github-actions[bot]'}, labels=[],
                  base={'ref': 'master', 'repo': {'full_name': repo}},
                  head={'ref': batch['branch'], 'sha': head, 'repo': {'full_name': repo}})
        run = dict(id=7, workflow_id=12, event='workflow_dispatch', head_sha=head,
                   head_branch=batch['branch'], head_repository={'full_name': repo},
                   status='completed', conclusion='success')
        jobs = [dict(name=name, status='completed', conclusion='success') for name in automerge.REQUIRED]
        def api(path, method='GET', data=None):
            if path.startswith('actions/workflows/12/runs?'):
                return {'workflow_runs': [run]}
            if path == 'pulls/1':
                return pr
            if path == 'git/ref/heads/master':
                return {'object': {'sha': self.base}}
            if path == 'branches/master':
                return {'protection': {'enabled': True, 'required_status_checks': {
                    'enforcement_level': 'everyone', 'contexts': list(automerge.REQUIRED)}}}
            if path == 'pulls/1/merge':
                self.assertEqual(data['sha'], head)
                self.assertEqual(data['merge_method'], 'merge')
                return {'merged': True, 'sha': head}
            if path == 'actions/variables/JOOLIA_UPSTREAM_SYNC_ENABLED':
                return {'value': 'true'}
            self.fail(path)
        original_output, original_git = sync.output, sync.git
        def output(*args):
            return self.base if args == ('rev-parse', 'refs/remotes/origin/master') else original_output(*args)
        def git(*args, **kwargs):
            if args[0] == 'fetch':
                return None
            return original_git(*args, **kwargs)
        with patch.object(automerge, 'api', side_effect=api), \
                patch.object(automerge, 'pages', side_effect=[[], jobs, [], []]), \
                patch.object(sync, 'git', side_effect=git), patch.object(sync, 'output', side_effect=output), \
                patch.dict(os.environ, {'JOOLIA_UPSTREAM_SYNC_ENABLED': 'true'}), \
                patch.object(automerge, 'gh') as calls:
            automerge.advance(pr, 12, repo)
        self.assertEqual(calls.call_args.args, ('workflow', 'run', 'upstream-sync.yml', '--ref', 'master', '-f', 'mode=propose'))

    def test_idle_queue_recovers_after_master_changes(self):
        for conclusion in ('failure', 'success', 'cancelled'):
            with self.subTest(conclusion=conclusion), \
                    patch.dict(os.environ, {'JOOLIA_UPSTREAM_SYNC_ENABLED': 'true'}), \
                    patch.object(automerge, 'api', side_effect=[
                        {'workflow_runs': [{'status': 'completed', 'conclusion': conclusion, 'head_sha': self.first}]},
                        {'object': {'sha': self.tip}}]), patch.object(automerge, 'gh') as dispatch:
                automerge.resume_idle_queue([])
                dispatch.assert_called_once_with('workflow', 'run', 'upstream-sync.yml', '--ref', 'master', '-f', 'mode=propose')

    def test_idle_queue_does_not_repeat_same_revision(self):
        for conclusion in ('failure', 'success', 'cancelled'):
            with self.subTest(conclusion=conclusion), \
                    patch.dict(os.environ, {'JOOLIA_UPSTREAM_SYNC_ENABLED': 'true'}), \
                    patch.object(automerge, 'api', side_effect=[
                        {'workflow_runs': [{'status': 'completed', 'conclusion': conclusion, 'head_sha': self.tip}]},
                        {'object': {'sha': self.tip}}]), patch.object(automerge, 'gh') as dispatch:
                automerge.resume_idle_queue([])
                dispatch.assert_not_called()

    def test_idle_queue_does_not_duplicate_active_runs(self):
        for status in ('queued', 'pending', 'in_progress', 'waiting'):
            with self.subTest(status=status), \
                    patch.dict(os.environ, {'JOOLIA_UPSTREAM_SYNC_ENABLED': 'true'}), \
                    patch.object(automerge, 'api', return_value={'workflow_runs': [{'status': status}]}), \
                    patch.object(automerge, 'gh') as dispatch:
                automerge.resume_idle_queue([])
                dispatch.assert_not_called()

    def test_idle_queue_respects_holds_manual_reports_and_disable_switch(self):
        for enabled, prs in (('false', []), ('true', [{'head': {'ref': 'sync/julia-pending'}}])):
            with self.subTest(enabled=enabled, prs=prs), \
                    patch.dict(os.environ, {'JOOLIA_UPSTREAM_SYNC_ENABLED': enabled}), \
                    patch.object(automerge, 'api') as api, patch.object(automerge, 'gh') as dispatch:
                automerge.resume_idle_queue(prs)
                api.assert_not_called()
                dispatch.assert_not_called()

    def test_idle_queue_starts_first_run_with_only_unrelated_prs(self):
        with patch.dict(os.environ, {'JOOLIA_UPSTREAM_SYNC_ENABLED': 'true'}), \
                patch.object(automerge, 'api', side_effect=[{'workflow_runs': []}, {'object': {'sha': self.tip}}]), \
                patch.object(automerge, 'gh') as dispatch:
            automerge.resume_idle_queue([{'head': {'ref': 'ci/unrelated-fix'}}])
            self.assertEqual(dispatch.call_count, 1)

    def test_other_open_sync_prevents_new_agent_run(self):
        batch = sync.plan(self.tip)
        sync.write_json(self.folder / 'plan.json', batch)
        out = self.folder / 'outputs'
        with patch.object(publish, 'gh', return_value=json.dumps([{'headRefName': 'sync/julia-other', 'url': 'pr'}])), \
                patch.dict(os.environ, {'GITHUB_OUTPUT': str(out)}):
            publish.gate(self.folder)
        self.assertIn('status=waiting', out.read_text())


if __name__ == '__main__':
    unittest.main()

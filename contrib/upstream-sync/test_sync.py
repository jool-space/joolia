"""Exercise batch boundaries, complete reviews and merge/checkpoint behavior using real Git histories."""
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import sync
import publish


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

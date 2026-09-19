"""Check the deadline against real child processes without API calls."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest
import uuid
from unittest.mock import Mock, patch

import review_watchdog as watchdog


@unittest.skipUnless(sys.platform == 'linux', 'the Actions watchdog uses /proc')
class WatchdogTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.marker = str(uuid.uuid4())

    def child(self, marker, ignore_term=False):
        code = ('import signal,time; '
                + ('signal.signal(signal.SIGTERM, signal.SIG_IGN); ' if ignore_term else '')
                + 'print("ready", flush=True); time.sleep(60)')
        child = subprocess.Popen([sys.executable, '-c', code],
                                 env=dict(os.environ, JOOLIA_REVIEW_MARKER=marker,
                                          NEVER_LOG_THIS_SECRET='sentinel-secret'),
                                 stdout=subprocess.PIPE, text=True)
        def cleanup():
            if child.poll() is None:
                child.kill()
            child.wait()
            child.stdout.close()
        self.addCleanup(cleanup)
        self.assertEqual(child.stdout.readline().strip(), 'ready')
        return child

    def test_deadline_kills_only_marked_process_and_escalates(self):
        target = self.child(self.marker, ignore_term=True)
        unrelated = self.child(self.marker + '-other')
        status = self.root / 'status.json'
        watchdog.watch(self.marker, 0, status, self.root / 'stop', interval=.01, grace=.05)
        self.assertEqual(target.wait(timeout=5), -signal.SIGKILL)
        self.assertIsNone(unrelated.poll())
        record = json.loads(status.read_text())
        self.assertEqual(record['state'], 'timed_out')
        self.assertTrue(record['action_seen'])
        self.assertNotIn('sentinel-secret', status.read_text())
        self.assertNotIn('argv', status.read_text())

    def test_stop_disarms_deadline(self):
        target = self.child(self.marker)
        stop = self.root / 'stop'
        stop.touch()
        status = self.root / 'status.json'
        watchdog.watch(self.marker, 0, status, stop)
        self.assertIsNone(target.poll())
        self.assertEqual(json.loads(status.read_text())['state'], 'stopped')

    def test_reused_pid_is_not_signalled(self):
        with patch.object(watchdog, 'marked_processes', return_value=[{'pid': 1234, 'start_ticks': 20}]), \
                patch.object(watchdog.os, 'kill') as kill:
            watchdog.signal_marked(self.marker, [{'pid': 1234, 'start_ticks': 10}], signal.SIGTERM)
        kill.assert_not_called()

    def test_timeout_before_action_started_is_visible(self):
        status = self.root / 'status.json'
        watchdog.watch(self.marker, 0, status, self.root / 'stop', grace=0)
        record = json.loads(status.read_text())
        self.assertEqual(record['state'], 'timed_out')
        self.assertFalse(record['action_seen'])
        self.assertEqual(record['processes'], [])

    def test_containment_tracks_and_kills_only_its_review_group(self):
        group = Mock()
        group.snapshot.return_value = {'memory.events': 'oom_kill 0'}
        status = self.root / 'status.json'
        watchdog.watch(self.marker, 0, status, self.root / 'stop', grace=0, containment=group)
        group.attach.assert_called_once_with([])
        group.kill.assert_called_once_with()
        self.assertEqual(json.loads(status.read_text())['memory'], {'memory.events': 'oom_kill 0'})

    def test_descendants_include_unmarked_children_but_not_parent_worker(self):
        proc = self.root / 'proc'
        proc.mkdir()
        for pid, parent in ((10, 1), (20, 10), (30, 20), (40, 30), (50, 10)):
            entry = proc / str(pid)
            entry.mkdir()
            (entry / 'stat').write_text(f'{pid} (process) S {parent} 0 0')
        self.assertEqual(watchdog.process_descendants([{'pid': 20}], proc), {20, 30, 40})

    def test_probe_disarming_does_not_kill_contained_processes(self):
        group = Mock()
        group.snapshot.return_value = {}
        stop = self.root / 'stop'
        stop.touch()
        watchdog.watch(self.marker, 0, self.root / 'status.json', stop, containment=group)
        group.kill.assert_not_called()

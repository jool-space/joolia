#!/usr/bin/env python3
"""Bound the review action without terminating the Actions worker.

The workflow runs this from a root-owned directory before drop-sudo. Only
processes with this action's exact environment marker can receive a signal.
Diagnostics contain process identities/counters, never argv or environment.
This is a liveness mechanism, not a security boundary against the reviewer.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import time
import uuid

MARKER = 'JOOLIA_REVIEW_MARKER'
KINDS = {'node', 'bash', 'sh', 'sudo', 'codex', 'codex-responses-api-proxy', 'bwrap', 'npm'}


def marked_processes(marker, proc=Path('/proc')):
    expected = (MARKER + '=' + marker).encode()
    found = []
    for entry in proc.iterdir():
        if not entry.name.isdecimal() or int(entry.name) <= 1:
            continue
        try:
            if expected not in (entry / 'environ').read_bytes().split(b'\0'):
                continue
            fields = (entry / 'stat').read_text().rpartition(')')[2].split()
            if fields[0] == 'Z':
                continue
            executable = (entry / 'exe').readlink().name
            found.append({'pid': int(entry.name), 'start_ticks': int(fields[19]),
                          'kind': executable if executable in KINDS else 'other',
                          'cpu_ticks': int(fields[11]) + int(fields[12]),
                          'rss_pages': int(fields[21])})
        except (OSError, ValueError, IndexError):
            # A process can exit between any two /proc reads.
            continue
    return sorted(found, key=lambda item: item['pid'])


def signal_marked(marker, processes, sig):
    identities = {(p['pid'], p['start_ticks']) for p in processes}
    for current in marked_processes(marker):
        if (current['pid'], current['start_ticks']) in identities:
            try:
                os.kill(current['pid'], sig)
            except ProcessLookupError:
                pass


def process_descendants(processes, proc=Path('/proc')):
    """Include children that clear the action marker; never walk up to the worker."""
    selected = {p['pid'] for p in processes}
    parents = {}
    for entry in proc.iterdir():
        if not entry.name.isdecimal():
            continue
        try:
            fields = (entry / 'stat').read_text().rpartition(')')[2].split()
            parents[int(entry.name)] = int(fields[1])
        except (OSError, ValueError, IndexError):
            continue
    while True:
        children = {pid for pid, parent in parents.items() if parent in selected}
        if children <= selected:
            return selected
        selected |= children


class ReviewCgroup:
    """Keep a review's memory use and termination separate from the Actions worker."""
    def __init__(self, megabytes, root=Path('/sys/fs/cgroup')):
        self.path = root / ('joolia-review-' + uuid.uuid4().hex)
        self.path.mkdir()
        if not (self.path / 'memory.max').exists():
            raise RuntimeError('Review containment requires the cgroup v2 memory controller')
        (self.path / 'memory.max').write_text(str(megabytes * 1024 * 1024))
        (self.path / 'memory.swap.max').write_text('0')
        (self.path / 'memory.oom.group').write_text('1')

    def attach(self, processes):
        for pid in process_descendants(processes):
            try:
                (self.path / 'cgroup.procs').write_text(str(pid))
            except ProcessLookupError:
                pass

    def snapshot(self):
        return {name: (self.path / name).read_text().strip()
                for name in ('memory.current', 'memory.peak', 'memory.max', 'memory.events')}

    def kill(self):
        (self.path / 'cgroup.kill').write_text('1')


def watch(marker, seconds, status, stop, *, interval=2, grace=5, containment=None):
    started = time.monotonic()
    record = {'state': 'watching', 'deadline_seconds': seconds, 'action_seen': False}

    def save():
        record['elapsed_seconds'] = round(time.monotonic() - started, 2)
        temporary = status.with_suffix('.tmp')
        temporary.write_text(json.dumps(record, indent=2) + '\n')
        temporary.replace(status)

    while True:
        processes = marked_processes(marker)
        if containment is not None:
            containment.attach(processes)
            record['memory'] = containment.snapshot()
        record['processes'] = processes
        record['action_seen'] |= bool(processes)
        if stop.exists():
            record['state'] = 'stopped'
            save()
            return
        if time.monotonic() - started >= seconds:
            record['state'] = 'timed_out'
            save()
            signal_marked(marker, processes, signal.SIGTERM)
            time.sleep(grace)
            signal_marked(marker, processes, signal.SIGKILL)
            if containment is not None:
                containment.kill()
                record['memory'] = containment.snapshot()
            record['remaining_processes'] = marked_processes(marker)
            save()
            return
        save()
        time.sleep(interval)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--marker', required=True)
    parser.add_argument('--seconds', type=int, required=True)
    parser.add_argument('--status', type=Path, required=True)
    parser.add_argument('--memory-limit-mb', type=int, default=4096)
    parser.add_argument('--stop', type=Path, required=True)
    args = parser.parse_args()
    if not 1 <= args.seconds <= 1500:
        parser.error('deadline must be between 1 and 1500 seconds')
    if not 128 <= args.memory_limit_mb <= 8192:
        parser.error('memory limit must be between 128 and 8192 MiB')
    containment = ReviewCgroup(args.memory_limit_mb)
    watch(args.marker, args.seconds, args.status, args.stop, containment=containment)


if __name__ == '__main__':
    main()

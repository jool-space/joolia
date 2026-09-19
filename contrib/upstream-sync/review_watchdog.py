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


def watch(marker, seconds, status, stop, *, interval=2, grace=5):
    started = time.monotonic()
    record = {'state': 'watching', 'deadline_seconds': seconds, 'action_seen': False}

    def save():
        record['elapsed_seconds'] = round(time.monotonic() - started, 2)
        temporary = status.with_suffix('.tmp')
        temporary.write_text(json.dumps(record, indent=2) + '\n')
        temporary.replace(status)

    while True:
        processes = marked_processes(marker)
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
    parser.add_argument('--stop', type=Path, required=True)
    args = parser.parse_args()
    if not 1 <= args.seconds <= 1500:
        parser.error('deadline must be between 1 and 1500 seconds')
    watch(args.marker, args.seconds, args.status, args.stop)


if __name__ == '__main__':
    main()

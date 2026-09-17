#!/usr/bin/env python3
"""Build and test the actual Joolia artifact, locally or in GitHub Actions."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
STAGES = ("build", "foundation", "stdlib", "pkg", "repl")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", choices=STAGES, action="append", help="diagnostic subset; default runs every gate")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--logs", type=Path, default=ROOT / "ci-results")
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    logs = args.logs.resolve()
    logs.mkdir(parents=True, exist_ok=True)
    coverage = json.loads((ROOT / "contrib/ci/coverage.json").read_text())
    stages = [stage for stage in STAGES if args.stage is None or stage in args.stage]
    results = {
        "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "worktree": subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True),
        "platform": os.uname().machine,
        "selected_stages": stages,
        "coverage": coverage,
        "results": [],
    }
    with tempfile.TemporaryDirectory(prefix="joolia-ci-") as scratch:
        env = dict(os.environ)
        for name in ("JULIA_PROJECT", "JULIA_BINDIR", "JULIA_SYSIMAGE", "JULIA_HISTORY", "JULIA_FALLBACK_REPL"):
            env.pop(name, None)
        env.update(
            JULIA_DEPOT_PATH=scratch + "/depot:", JULIA_LOAD_PATH="@:@stdlib",
            JULIA_NUM_THREADS="1", JULIA_CPU_THREADS=str(args.jobs),
            JULIA_NUM_PRECOMPILE_TASKS=str(args.jobs), JULIA_TEST_FAILFAST="1",
            JULIA_PKG_PRECOMPILE_AUTO="0",
        )
        julia = str(ROOT / "usr/bin/joolia")
        commands = {
            "build": ["make", f"-j{args.jobs}", "LLVM_ASSERTIONS=1"],
            "foundation": ["make", "-C", "test", "LLVM_ASSERTIONS=1", *coverage["foundation_targets"]],
            "stdlib": [julia, "--startup-file=no", "--check-bounds=yes", "test/runtests.jl", *coverage["stdlib_suites"]],
            "pkg": [julia, "--startup-file=no", "--check-bounds=yes", "-e",
                    'using Pkg, Test; include(joinpath(pkgdir(Pkg), "test", "misc.jl"))'],
            "repl": [sys.executable, str(ROOT / "contrib/ci/repl.py"), "--julia", julia, "--logs", str(logs)],
        }
        try:
            for stage in stages:
                command = commands[stage]
                log = logs / (stage + ".log")
                print(f"[{stage}] starting; log: {log}", flush=True)
                started = time.monotonic()
                with log.open("w") as output:
                    output.write("Command: " + repr(command) + "\n")
                    output.flush()
                    process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=output,
                                               stderr=subprocess.STDOUT, start_new_session=True)
                    try:
                        code = process.wait(timeout=5400 if stage == "build" else 3600)
                    except BaseException:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
                        results["results"].append({"stage": stage, "status": "interrupted"})
                        raise
                results["results"].append({"stage": stage, "status": "passed" if code == 0 else "failed",
                                           "exit_code": code, "seconds": round(time.monotonic() - started, 2)})
                print(f"[{stage}] {'passed' if code == 0 else 'FAILED'} ({results['results'][-1]['seconds']}s)", flush=True)
                if code:
                    print("\n".join(log.read_text(errors="replace").splitlines()[-80:]), flush=True)
                    return 1
        finally:
            (logs / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())

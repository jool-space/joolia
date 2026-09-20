#!/usr/bin/env python3
"""Exercise the bundled REPL/Pkg with an entirely local, versioned registry."""
import argparse
import errno
import fcntl
import os
from pathlib import Path
import pty
import re
import select
import signal
import struct
import subprocess
import tempfile
import termios
import time
import tomllib

ROOT_UUID = "ca901ae1-a196-4b7d-8e82-450d3e398e31"
DEP_UUID = "ca901ae1-a196-4b7d-8e82-450d3e398e32"
REG_UUID = "ca901ae1-a196-4b7d-8e82-450d3e398e33"
OSC = re.compile(rb"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)")
CSI = re.compile(rb"\x1b\[[0-?]*[ -/]*[@-~]")


def git(path, *args):
    env = dict(os.environ, GIT_AUTHOR_NAME="Joolia CI", GIT_AUTHOR_EMAIL="ci@example.invalid",
               GIT_COMMITTER_NAME="Joolia CI", GIT_COMMITTER_EMAIL="ci@example.invalid")
    return subprocess.check_output(["git", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null",
                                    "-C", str(path), *args], env=env, text=True).strip()


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def registry_fixture(root):
    registry = root / "depot/registries/CI"
    registry.mkdir(parents=True)
    packages = {}
    for name, uuid in (("CIDep", DEP_UUID), ("CIRoot", ROOT_UUID)):
        repo = root / "repos" / name
        repo.mkdir(parents=True)
        git(repo, "init", "-q")
        versions = []
        for version in (1, 2):
            needs_dep = name == "CIRoot" and version == 2
            project = f'name = "{name}"\nuuid = "{uuid}"\nversion = "{version}.0.0"\n'
            if needs_dep:
                project += f'\n[deps]\nCIDep = "{DEP_UUID}"\n'
                project += '\n[extras]\nTest = "8dfed614-e22c-5e08-85e1-65c5234f0b40"\n[targets]\ntest = ["Test"]\n'
            write(repo / "Project.toml", project)
            body = "using CIDep\nvalue() = CIDep.value()" if needs_dep else f"value() = {42 if version == 2 else 1}"
            write(repo / f"src/{name}.jl", f"module {name}\n{body}\nend\n")
            if needs_dep:
                write(repo / "test/runtests.jl", '''using Test, CIRoot
@test CIRoot.value() == 42
@test firstindex([10, 20]) == 0
@test (10, 20)[0] == 10
@test Base.JLOptions().malloc_log == 0
''')
            git(repo, "add", ".")
            git(repo, "commit", "-qm", f"Version {version}")
            tree = git(repo, "rev-parse", "HEAD^{tree}")
            versions.append(f'["{version}.0.0"]\ngit-tree-sha1 = "{tree}"\n')
        entry = registry / name
        write(entry / "Package.toml", f'name = "{name}"\nuuid = "{uuid}"\nrepo = "{repo.as_uri()}"\n')
        write(entry / "Versions.toml", "\n".join(versions))
        if name == "CIRoot":
            write(entry / "Deps.toml", f'["2"]\nCIDep = "{DEP_UUID}"\n')
            write(entry / "Compat.toml", '["2"]\nCIDep = "2"\n')
        packages[uuid] = name
    entries = "\n".join(f'"{uuid}" = {{name = "{name}", path = "{name}"}}' for uuid, name in packages.items())
    write(registry / "Registry.toml", f'name = "CI"\nuuid = "{REG_UUID}"\nrepo = "{registry.as_uri()}"\n[packages]\n{entries}\n')


class REPL:
    def __init__(self, julia, root, logs):
        self.output = bytearray()
        self.logs = logs
        self.counter = 0
        self.master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))
        env = dict(os.environ, TERM="xterm-256color", JULIA_DEPOT_PATH=str(root / "depot") + ":",
                   JULIA_LOAD_PATH="@:@stdlib", JULIA_PKG_SERVER="", JULIA_PKG_OFFLINE="false",
                   JULIA_PKG_PRECOMPILE_AUTO="0", JULIA_HISTORY=str(root / "history.jl"))
        env.pop("JULIA_FALLBACK_REPL", None)
        self.process = subprocess.Popen([str(julia), "--startup-file=no", "--color=yes", "--project=" + str(root / "project")],
                                        env=env, stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
        os.close(slave)

    def text(self):
        return CSI.sub(b"", OSC.sub(b"", bytes(self.output))).replace(b"\r", b"").decode(errors="replace")

    def send(self, text):
        os.write(self.master, text.encode())

    def wait(self, marker, start=0, timeout=180):
        deadline = time.monotonic() + timeout
        while True:
            text = self.text()
            tail = text[start:]
            if re.search(r"ERROR:|Unhandled Task ERROR|Error in \w+Pass", tail):
                raise RuntimeError(tail[-6000:])
            if marker in tail:
                return start + tail.index(marker) + len(marker)
            if time.monotonic() >= deadline:
                raise TimeoutError(f"Waiting for {marker!r}\n{text[-4000:]}")
            if select.select([self.master], [], [], min(1, max(0, deadline - time.monotonic())))[0]:
                try:
                    chunk = os.read(self.master, 65536)
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    chunk = b""
                if not chunk:
                    raise RuntimeError(f"REPL exited before {marker!r}\n{text[-4000:]}")
                self.output.extend(chunk)

    def julia(self, code):
        self.counter += 1
        marker = f"CI_DONE_{self.counter}"
        start = len(self.text())
        self.send(code + f'; println("CI_DONE_", {self.counter})\n')
        end = self.wait(marker, start)
        self.wait("joolia> ", end)

    def package(self, command, output):
        start = len(self.text())
        self.send("]" + command + "\n")
        end = self.wait(output, start)
        end = self.wait("pkg> ", end)
        self.send("\x7f")
        self.wait("joolia> ", end)

    def close(self):
        if self.process.poll() is None:
            os.killpg(self.process.pid, signal.SIGTERM)
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(self.process.pid, signal.SIGKILL)
                self.process.wait()
        os.close(self.master)
        (self.logs / "repl.raw").write_bytes(self.output)
        (self.logs / "repl-transcript.log").write_text(self.text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--julia", required=True, type=Path)
    parser.add_argument("--logs", required=True, type=Path)
    args = parser.parse_args()
    args.logs.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="joolia-ci-repl-") as scratch:
        root = Path(scratch)
        (root / "project").mkdir()
        registry_fixture(root)
        repl = REPL(args.julia.resolve(), root, args.logs)
        try:
            repl.wait("joolia> ")
            repl.julia('using LinearAlgebra; @assert ones(3,4) * ones(4,5) == fill(4.0,3,5)')
            repl.julia('o = 73')
            for spaces in (1, 2, 3):
                start = len(repl.text())
                repl.send("o" + " " * spaces + "\x7f\n")
                end = repl.wait("\n73\n", start)
                repl.wait("joolia> ", end)
            # Down must leave recalled multiline history and return to the empty draft.
            repl.julia('history_navigation_count = 0')
            start = len(repl.text())
            repl.send("\x1b[200~begin\n    history_navigation_count += 1\nend\x1b[201~\n")
            end = repl.wait("\n1\n", start)
            repl.wait("joolia> ", end)
            start = len(repl.text())
            repl.send("0\n")
            end = repl.wait("\n0\n", start)
            repl.wait("joolia> ", end)
            repl.send("\x1b[A\x1b[A" + "\x1b[B" * 6)
            repl.julia('@assert history_navigation_count == 1')
            repl.package("add CIRoot", "Updating")
            manifest = tomllib.loads((root / "project/Manifest.toml").read_text())
            assert manifest["deps"]["CIRoot"][0]["version"] == "2.0.0"
            assert "CIDep" in manifest["deps"]["CIRoot"][0]["deps"]
            assert manifest["deps"]["CIDep"][0]["version"] == "2.0.0"
            repl.julia('using CIRoot; @assert CIRoot.value() == 42')
            repl.package("stat\t", "Status")
            repl.package("test CIRoot", "tests passed")
            repl.send("exit()\n")
            assert repl.process.wait(timeout=30) == 0
            assert not list((root / "depot/packages").rglob("*.mem")), "Pkg.test enabled allocation logging"
        finally:
            repl.close()
    print("Styled REPL, backspace, multiline history navigation, completion, versioned dependency resolution, loading and Pkg.test passed.")


if __name__ == "__main__":
    main()

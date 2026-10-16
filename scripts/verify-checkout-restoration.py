"""Verify ordinary update and sync from immutable, real consumer states.

Resolve --producer and --consumer with Mori. Candidate transport changes only the
harness's Git URL routing; --published repeats acceptance against public origins.
All clones and transcripts are retained in a new --area for review.
"""

import argparse
import os
import pathlib
import pty
import select
import shutil
import subprocess
import time
import json


def run(arguments, cwd=None, env=None):
    result = subprocess.run(
        list(map(str, arguments)), cwd=cwd, env=env, text=True, capture_output=True
    )
    if result.returncode:
        raise RuntimeError(f"{arguments}:\n{result.stdout}\n{result.stderr}")
    return result.stdout


def git(directory, *arguments):
    return run(["git", "-C", directory, *arguments])


def snapshot(root):
    paths = git(root, "ls-files", "-z").split("\0")
    blobs = {}
    for name in filter(None, paths):
        path = root / name
        if path.is_symlink():
            blobs[name] = os.readlink(path).encode()
        elif path.is_dir():
            # A gitlink's exact object identity is included in the index snapshot.
            blobs[name] = b"<gitlink>"
        else:
            blobs[name] = path.read_bytes()
    return git(root, "ls-files", "--stage", "-z"), blobs


def interactive_update(binary, root, environment, transcript):
    master, slave = pty.openpty()
    child = subprocess.Popen(
        [str(binary), "update", "master-plan"],
        cwd=root,
        env=environment,
        stdin=slave,
        stdout=slave,
        stderr=slave,
        start_new_session=True,
    )
    os.close(slave)
    output = b""
    accepted = False
    deadline = time.monotonic() + 120
    try:
        while time.monotonic() < deadline:
            if select.select([master], [], [], 0.2)[0]:
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                output += chunk
                transcript.write_bytes(output)
                if b"Choose [g]enerated" in output:
                    raise RuntimeError("ordinary update requested manual conflict resolution")
                if b"Apply? [Y/n]" in output and not accepted:
                    os.write(master, b"y\n")
                    accepted = True
            if child.poll() is not None:
                break
        else:
            raise RuntimeError("ordinary interactive update timed out")
        child.wait(timeout=10)
        if child.returncode:
            raise RuntimeError(output.decode(errors="replace"))
        assert accepted, "normal update did not reach its acceptance prompt"
    finally:
        if child.poll() is None:
            child.terminate()
            child.wait(timeout=10)
        os.close(master)
        transcript.write_bytes(output)


def assert_declarations(root, before, current):
    for skill in ["exec-plan", "master-plan"]:
        for tool in [".claude", ".codex", ".agents"]:
            destination = f"{tool}/skills/{skill}"
            assert current["checkoutOutputs"][destination]["spec"] == {
                "kind": "directory-symlink",
                "source": f"agents/skills/{skill}",
            }
            # Update retains the engine's existing rule: unchanged declarations
            # do not repair local drift. Teammate sync below materializes all six.
            if destination not in before.get("checkoutOutputs", {}):
                assert_link(root, tool, skill)
            assert not git(root, "ls-files", "--", destination), destination


def assert_link(root, tool, skill):
    path = root / tool / "skills" / skill
    assert path.is_symlink(), path
    assert os.readlink(path) == f"../../agents/skills/{skill}", path
    assert (path / "SKILL.md").is_file(), path


def verify_fixture(args, label, repository, revision, area, candidate):
    root = area / label
    home = area / f"{label}-home"
    home.mkdir()
    git(area, "clone", "-q", "--no-hardlinks", repository, root)
    git(root, "checkout", "--detach", revision)
    environment = dict(
        os.environ,
        HOME=str(home),
        XDG_CONFIG_HOME=str(home / "config"),
        XDG_CACHE_HOME=str(home / "cache"),
        GIT_CONFIG_GLOBAL=str(home / ".gitconfig"),
    )
    if not args.published:
        git(
            home, "config", "--file", home / ".gitconfig",
            f"url.{candidate}.insteadOf", "https://github.com/shinzui/agent-seihou.git",
        )
    manifest_path = root / ".seihou/manifest.json"
    before = json.loads(manifest_path.read_text())
    assert before["version"] in [6, 7, 9]
    print(label, "starting schema", before["version"], "revision", revision, flush=True)
    interactive_update(args.binary, root, environment, area / f"{label}-update.txt")
    final_output = (area / f"{label}-update.txt").read_text().split("Apply? [Y/n]", 1)[-1]
    assert "checkout destination is not ignored" not in final_output, final_output
    current = json.loads(manifest_path.read_text())
    assert current["version"] == 10
    assert_declarations(root, before, current)
    if label == "mixed":
        old = [app for app in before["applications"] if app["target"]["name"] != "master-plan"]
        new = [app for app in current["applications"] if app["target"]["name"] != "master-plan"]
        for application in old:
            application["checkoutCommands"] = []
        assert old == new, "unrelated Nix application changed"
    git(root, "add", ".")
    git(
        root, "-c", "user.name=Checkout acceptance", "-c",
        "user.email=checkout@example.invalid", "commit", "-qm",
        "test: record checkout producer adoption",
    )
    clone = area / f"{label}-teammate"
    git(area, "clone", "-q", root, clone)
    receiver_environment = dict(
        os.environ,
        HOME=str(area / f"{label}-teammate-home"),
        XDG_CONFIG_HOME=str(area / f"{label}-teammate-config"),
        XDG_CACHE_HOME=str(area / f"{label}-teammate-cache"),
    )
    original_snapshot = snapshot(clone)
    original_manifest = (clone / ".seihou/manifest.json").read_bytes()
    output = ""
    for _ in range(2):
        output += run([args.binary, "sync"], cwd=clone, env=receiver_environment)
    (area / f"{label}-sync.txt").write_text(output)
    for skill in ["exec-plan", "master-plan"]:
        for tool in [".claude", ".codex", ".agents"]:
            assert_link(clone, tool, skill)
    assert snapshot(clone) == original_snapshot
    assert (clone / ".seihou/manifest.json").read_bytes() == original_manifest
    assert not git(clone, "status", "--porcelain")
    print(label, "ordinary update + teammate sync x2 passed with six exact links", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True, type=pathlib.Path)
    parser.add_argument("--producer", required=True, type=pathlib.Path, help="Checkout of mori://shinzui/agent-seihou")
    parser.add_argument("--consumer", required=True, type=pathlib.Path, help="Checkout of mori://shinzui/haskell-nix")
    parser.add_argument("--area", required=True, type=pathlib.Path, help="New directory retaining transcripts and disposable clones")
    parser.add_argument("--published", action="store_true", help="Use public producer origins without candidate Git URL routing")
    args = parser.parse_args()
    args.binary = args.binary.resolve()
    producer = args.producer.resolve()
    consumer = args.consumer.resolve()
    root = pathlib.Path(__file__).resolve().parents[1]
    area = args.area.resolve()
    area.mkdir()  # Refuse reuse of previously modified acceptance fixtures.
    candidate = area / "producer"
    if not args.published:
        git(area, "clone", "-q", producer, candidate)
        for name in git(producer, "diff", "--name-only", "HEAD").splitlines():
            destination = candidate / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(producer / name, destination)
        git(candidate, "add", ".")
        if git(candidate, "status", "--porcelain"):
            git(
                candidate, "-c", "user.name=Checkout acceptance", "-c",
                "user.email=checkout@example.invalid", "commit", "-qm",
                "test: stage checkout producer candidate\n\n"
                "ExecPlan: mori://shinzui/seihou/plans/108-restore-module-declared-checkout-effects-without-reapplying-modules\n"
                "Intention: intention_01m50b28ccem2axbbn5tj3k1wt",
            )
    print("runtime", run([args.binary, "--version"]).strip(), flush=True)
    print("producer", git(producer if args.published else candidate, "rev-parse", "HEAD").strip(), "published" if args.published else "candidate transport", flush=True)
    fixtures = [
        ("schema6", consumer, "5cb50cab752945d1a0278c9347edaa5918f6d158"),
        ("schema9", consumer, "529fd6d87c414a95223f24c622daaedb50c3ad57"),
        ("mixed", root, "188fbcf60c84661a90748eff3a1e8131076c9bd2"),
    ]
    for fixture in fixtures:
        verify_fixture(args, *fixture, area, candidate)


if __name__ == "__main__":
    main()

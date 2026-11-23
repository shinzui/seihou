"""Exercise Seihou reviewed Codex hooks against a local Codex model fixture.

Requires the pilot Keiro blueprint cohort in the user's installed catalogue.
Supply the Baikai loopback probe with --provider-probe.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import signal
import time
import tempfile
from http.server import ThreadingHTTPServer
from threading import Thread

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--seihou", required=True, type=Path)
parser.add_argument("--provider-probe", required=True, type=Path)
parser.add_argument("--schema", default="schema/package.dhall", type=Path)
options = parser.parse_args()
seihou = str(options.seihou.resolve())
schema = options.schema.resolve()
spec = importlib.util.spec_from_file_location("probe", options.provider_probe.resolve())
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
denial = probe.GATE
until_marker = "if [ -f marker ]; then " + denial + "; fi"

with ThreadingHTTPServer(("127.0.0.1", 0), probe.Model) as model, tempfile.TemporaryDirectory(prefix="seihou-reviewed-codex-") as directory:
    model.requests = 0
    model.require_single_thread = True
    worker = Thread(target=model.serve_forever, daemon=True)
    worker.start()
    root = Path(directory).resolve()
    codex_home = root / "codex"
    codex_home.mkdir()
    config = codex_home / "config.toml"
    config.write_text(f'''model = "gpt-5.4"
model_provider = "fixture"
[model_providers.fixture]
name = "loopback"
base_url = "http://127.0.0.1:{model.server_port}/v1"
wire_api = "responses"
request_max_retries = 0
stream_max_retries = 0
''')
    env = dict(os.environ, CODEX_HOME=str(codex_home))

    def consumer(name):
        work = root / name
        work.mkdir()
        subprocess.run(["git", "init", "-q", str(work)], check=True)
        return work

    def set_hook(work, command):
        path = work / "caller hooks.json"
        path.write_text(json.dumps({"hooks": {"PreToolUse": [
            {"matcher": "^Bash$", "hooks": [{"type": "command", "command": command}]}]}}))
        return path

    def review(work, path):
        result, out = probe.confirm_review(seihou, work, path, env, b"yes")
        assert result == 0, out

    def invoke(work, args, code=0, expected=None):
        result = subprocess.run([seihou, "agent", *args], cwd=work, env=env, stdin=subprocess.DEVNULL,
                                check=False, text=True, capture_output=True, timeout=60)
        text = result.stdout + result.stderr
        assert result.returncode == code and (expected is None or expected in text), text[-2200:]
        return text

    provider = ["--provider", "codex-cli", "--model", "gpt-5.4"]
    run = consumer("run")
    bp = run / ".seihou/modules/reviewed-policy"
    bp.mkdir(parents=True)
    (bp / "blueprint.dhall").write_text(f'''let S = {schema}
in S.Blueprint::{{ name = "reviewed-policy"
, version = Some "1.0.0"
, prompt = "Run the fixture."
, baseModules = [{{module = "review-baseline", source = None Text, vars = [] : List {{name : Text, value : Text}}}}]
}}
''')
    baseline = run / ".seihou/modules/review-baseline"
    baseline.mkdir()
    (baseline / "module.dhall").write_text(f'''let S = {schema}
in S.Module::{{name = "review-baseline", version = Some "1.0.0"
, commands = [S.Command::{{action = S.Command.Action.Apply "echo baseline > base-marker"}}]
}}
''')
    hooks = set_hook(run, denial)
    manifest = run / ".seihou/manifest.json"
    args = ["run", "reviewed-policy", *provider, "--codex-hooks", hooks.name]
    invoke(run, ["--debug", *args], expected="Caller Codex hooks supplied")
    invoke(run, [*args, "--batch"], 1, "seihou agent review-codex-hooks")
    assert model.requests == 0 and not manifest.exists() and not (run / "base-marker").exists()

    review(run, hooks)
    reviewed_bytes = config.read_bytes()
    invoke(run, [*args, "--batch"], 1, "Codex PreToolUse blocked")
    assert (run / "base-marker").read_text() == "baseline\n" and not (run / "marker").exists()
    assert not json.loads(manifest.read_text()).get("blueprint") and model.requests == 2
    assert config.read_bytes() == reviewed_bytes
    before = manifest.read_bytes()
    set_hook(run, ":")
    invoke(run, [*args, "--batch"], 1, "seihou agent review-codex-hooks")
    assert manifest.read_bytes() == before and model.requests == 2
    review(run, hooks)
    config_after_approval = config.read_bytes()
    invoke(run, [*args, "--batch"], expected="Finished.")
    after = json.loads(manifest.read_text())
    assert after["blueprint"]["callerToolPolicy"]["codexHooksSha256"] == hashlib.sha256(hooks.read_bytes()).hexdigest()
    assert (run / "marker").read_text() == "ran" and config.read_bytes() == config_after_approval
    invoke(run, [*args, "--batch", "--allowed-tool", "Read"], 1, "cannot be combined")
    before = manifest.read_bytes()
    codex = shutil.which("codex")
    proxy = root / "bin"
    proxy.mkdir()
    script = proxy / "codex"
    script.write_text(f'''#!{sys.executable}
import json
import subprocess
import sys
with subprocess.Popen([{codex!r}, *sys.argv[1:]], stdin=sys.stdin, stdout=subprocess.PIPE) as app:
    for frame in app.stdout:
        if json.loads(frame).get("method") != "hook/completed":
            sys.stdout.buffer.write(frame)
            sys.stdout.buffer.flush()
    sys.exit(app.wait())
''')
    script.chmod(0o755)
    saved_path = env["PATH"]
    env["PATH"] = str(proxy) + os.pathsep + saved_path
    invoke(run, [*args, "--batch", "--no-baseline"], 1, "without complete hook evidence")
    env["PATH"] = saved_path
    assert before == manifest.read_bytes() and config.read_bytes() == config_after_approval

    previous_requests = model.requests
    model.delay = 3
    with subprocess.Popen([seihou, "agent", *args, "--batch", "--no-baseline"], cwd=run, env=env,
                          stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL) as interrupted:
        deadline = time.monotonic() + 10
        while model.requests == previous_requests and time.monotonic() < deadline:
            time.sleep(0.02)
        interrupted.send_signal(signal.SIGINT)
        assert interrupted.wait(timeout=10) != 0 and model.requests > previous_requests
    model.delay = 0
    assert before == manifest.read_bytes() and config.read_bytes() == config_after_approval
    print("Seihou batch run verified debug, fresh review before baseline, denial, changed gate, SHA-256 receipt, missing evidence and interruption.", flush=True)

    migrate = consumer("migrate")
    hooks = set_hook(migrate, until_marker)
    review(migrate, hooks)
    first_digest = hashlib.sha256(hooks.read_bytes()).hexdigest()
    manifest = migrate / ".seihou/manifest.json"
    args = ["migrate", "keiro-upgrade", "--from=0.22.0.0", "--to=0.25.0.0", "--batch", *provider,
            "--codex-hooks", hooks.name]
    invoke(migrate, args, 1, "Codex PreToolUse blocked")
    first_receipts = json.loads(manifest.read_text())["blueprintMigrations"]
    assert len(first_receipts) == 1 and first_receipts[0]["callerToolPolicy"]["codexHooksSha256"] == first_digest
    old = manifest.read_bytes()
    set_hook(migrate, ":")
    before = model.requests
    invoke(migrate, args, 1, "seihou agent review-codex-hooks")
    assert old == manifest.read_bytes() and model.requests == before
    review(migrate, hooks)
    saved = config.read_bytes()
    invoke(migrate, args)
    final = json.loads(manifest.read_text())["blueprintMigrations"]
    assert len(final) == 6 and config.read_bytes() == saved
    last_digest = hashlib.sha256(hooks.read_bytes()).hexdigest()
    assert [r for r in final if r["callerToolPolicy"]["codexHooksSha256"] == first_digest] == first_receipts
    assert sum(r["callerToolPolicy"]["codexHooksSha256"] == last_digest for r in final) == 5
    owners = sorted(set(r["name"] for r in final))
    print(f"Seihou installed Keiro migration fixture preserved the first receipt on denial and recorded the retry digest on five further edges across {owners}.", flush=True)
    model.shutdown()
    worker.join()

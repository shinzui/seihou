"""Prove recipe extension using ordinary public commands and isolated state.

Candidate repositories are committed producer checkouts. Only Git routing changes;
install still discovers, normalizes and acquires the complete closure itself.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True

SPEC = importlib.util.spec_from_file_location('recipe_terminal', Path(__file__).with_name('verify-recipe-inputs.py'))
terminal = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(terminal)
ROOT_URL = 'https://github.com/shinzui/agent-seihou.git'
BASE_URL = 'https://github.com/shinzui/seihou-modules.git'
TARGET = 'haskell-cli-app-with-agents'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', required=True)
    parser.add_argument('--area', type=Path, required=True)
    parser.add_argument('--candidate-repo', type=Path, action='append', default=[])
    parser.add_argument('--check-update', action='store_true', help='Also verify ordinary update from a fresh committed clone')
    args = parser.parse_args()
    binary = os.path.abspath(shutil.which(args.binary) or args.binary)
    area = args.area.resolve()
    area.mkdir(parents=True, exist_ok=False)
    env = {k: v for k, v in os.environ.items() if not k.startswith(('SEIHOU_VAR_', 'GIT_CONFIG_')) and k != 'SEIHOU_CONTEXT'}
    env.update(HOME=str(area/'home'), XDG_CONFIG_HOME=str(area/'config'),
               XDG_CACHE_HOME=str(area/'cache'), XDG_DATA_HOME=str(area/'data'),
               XDG_STATE_HOME=str(area/'state'), GIT_CONFIG_NOSYSTEM='1',
               GIT_AUTHOR_NAME='Recipe acceptance', GIT_COMMITTER_NAME='Recipe acceptance',
               GIT_AUTHOR_EMAIL='recipe@example.test', GIT_COMMITTER_EMAIL='recipe@example.test')
    evidence = {'binary': binary, 'version': subprocess.check_output([binary, '--version'], text=True).strip(),
                'preparation': ['Create empty isolated HOME and XDG roots', 'Route committed candidate Git sources when requested'],
                'candidates': []}
    sources = area/'candidate-sources'
    for index, candidate in enumerate(args.candidate_repo):
        candidate = candidate.resolve()
        assert not subprocess.check_output(['git', '-C', str(candidate), 'status', '--porcelain'], text=True).strip(), 'Commit candidate changes first'
        remote = subprocess.check_output(['git', '-C', str(candidate), 'remote', 'get-url', 'origin'], text=True).strip()
        if remote.startswith('git@github.com:'):
            remote = 'https://github.com/' + remote.split(':', 1)[1]
        candidate_path = sources/str(index)
        subprocess.run(['git', 'clone', '-q', '--no-local', str(candidate), str(candidate_path)], check=True)
        revision = subprocess.check_output(['git', '-C', str(candidate_path), 'rev-parse', 'HEAD'], text=True).strip()
        env.update({f'GIT_CONFIG_KEY_{index}': 'url.' + candidate_path.as_uri() + '.insteadOf',
                    f'GIT_CONFIG_VALUE_{index}': remote})
        evidence['candidates'].append({'origin': remote, 'revision': revision})
    env['GIT_CONFIG_COUNT'] = str(len(args.candidate_repo))
    (area/'evidence.json').write_text(json.dumps(evidence, indent=2))
    print(json.dumps(evidence, indent=2), flush=True)
    project = area/'project'
    project.mkdir()

    def run(label, command, cwd=project, answers=None, selected_env=None, expected=0):
        selected_env = env if selected_env is None else selected_env
        code, output = terminal.invoke(binary, cwd, selected_env, command, answers)
        (area/(label+'.txt')).write_text(output)
        assert code == expected, (label, code, output)
        print(label + ': passed', flush=True)
        return output

    run('install', ['install', ROOT_URL, '--module', TARGET])
    cache = area/'config/seihou/installed'
    required = {TARGET, 'haskell-cli-app-repo', 'haskell-cli-app', 'git-init', 'nix-haskell-flake', 'agent-gitignore'}
    assert {p.name for p in cache.iterdir()} == required
    for name in required:
        expected = ROOT_URL if name in {TARGET, 'agent-gitignore'} else BASE_URL
        assert json.loads((cache/name/'.seihou-origin.json').read_text())['sourceUrl'].removesuffix('.git') == expected.removesuffix('.git')
    before = snapshot(cache)
    # Physically remove candidate source clones before offline generation.
    if sources.exists():
        shutil.rmtree(sources)
    offline = dict(env, GIT_CONFIG_COUNT='0')
    stubs = area/'offline-bin'
    stubs.mkdir()
    git = shutil.which('git')
    (stubs/'git').write_text('#!/bin/sh\ncase "$1" in clone|fetch|pull|ls-remote) echo "unexpected acquisition during run" >&2; exit 99;; esac\nexec ' + json.dumps(git) + ' "$@"\n')
    (stubs/'git').chmod(0o755)
    offline['PATH'] = str(stubs) + os.pathsep + env['PATH']
    flags = ['--var', 'project.name=extension-probe', '--var', 'project.namespace=ExtensionProbe',
             '--var', 'project.description=Recipe extension acceptance', '--var', 'git.initialCommit=false', '--var', 'nix.process-compose=false', '--var', 'nix.postgresql=false']
    output = run('run', ['run', TARGET, *flags], selected_env=offline)
    assert 'Base chain: haskell-cli-app-repo -> ' + TARGET in output
    assert 'Primary module: haskell-cli-app' in output
    assert (project/'flake.nix').exists() and (project/'extension-probe-core/extension-probe-core.cabal').exists()
    assert '.codex/' in (project/'.gitignore').read_text()
    assert snapshot(cache) == before
    manifest = json.loads((project/'.seihou/manifest.json').read_text())
    if manifest['version'] >= 13:
        chain = manifest['applications'][0]['recipeChain']
        assert [node['name'] for node in chain] == ['haskell-cli-app-repo', TARGET]
        assert all(len(node['descriptorHash']) == 64 for node in chain)
        assert all(node['origin']['kind'] == 'remote' for node in chain)
    repeated = run('repeat-preview', ['run', TARGET, '--dry-run', *flags], selected_env=offline)
    assert 'Recipe descriptor changed:' not in repeated
    interactive = area/'interactive'
    interactive.mkdir()
    output = run('interactive', ['run', TARGET], cwd=interactive, selected_env=offline, answers={
        'What is your project name?': 'interactive-probe',
        'One-line project synopsis': 'Interactive recipe proof',
        'Describe your project in one line:': 'Interactive recipe proof',
        'Longer project description': '',
        'Top-level Haskell module namespace?': 'InteractiveProbe',
        'Include process-compose for service orchestration?': 'false',
        'Include PostgreSQL with local database setup?': 'false',
        'Save? [Y/n]': 'n', 'Proceed? [Y/n]': 'y',
    })
    assert 'Base chain:' in output and (interactive/'flake.nix').exists()
    assert snapshot(cache) == before
    if args.check_update:
        # The offline proof above ran with these checkouts physically absent.
        # Recreate only the Git transport fixtures for the network-enabled replay.
        for index, candidate in enumerate(args.candidate_repo):
            subprocess.run(['git', 'clone', '-q', '--no-local', str(candidate.resolve()), str(sources/str(index))], check=True)
        fresh = area/'fresh-clone'
        fresh.mkdir()
        clone = fresh/'project'
        subprocess.run(['git', 'clone', '-q', str(interactive), str(clone)], check=True)
        replay_env = dict(env, HOME=str(fresh/'home'), XDG_CONFIG_HOME=str(fresh/'config'),
                          XDG_CACHE_HOME=str(fresh/'cache'), XDG_DATA_HOME=str(fresh/'data'),
                          XDG_STATE_HOME=str(fresh/'state'))
        replay_cache = fresh/'config/seihou/installed'
        prior = snapshot(clone)
        preview = run('fresh-preview', ['update', TARGET, '--dry-run'], cwd=clone, selected_env=replay_env)
        assert 'Cache:' in preview and snapshot(clone) == prior and not replay_cache.exists()
        run('fresh-decline', ['update', TARGET], cwd=clone, selected_env=replay_env, answers={'Apply? [Y/n]': 'n'})
        assert snapshot(clone) == prior and not replay_cache.exists()
        run('fresh-accept', ['update', TARGET], cwd=clone, selected_env=replay_env, answers={'Apply? [Y/n]': 'y'})
        assert {p.name for p in replay_cache.iterdir()} == required
        before_repeat = snapshot(clone)
        repeated = run('fresh-repeat', ['update', TARGET, '--dry-run'], cwd=clone, selected_env=replay_env)
        assert 'Already up to date.' in repeated and snapshot(clone) == before_repeat
        print('PASS: fresh-clone update preview, decline, cache restoration and repeat no-op', flush=True)
    print('PASS: real producer install, origins, offline generation, inherited primary, agent files, repeat preview and interactive confirmation', flush=True)


def snapshot(root):
    return sorted((str(p.relative_to(root)), p.read_bytes()) for p in root.rglob('*') if p.is_file())


if __name__ == '__main__':
    main()

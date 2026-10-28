"""Exercise recipe decisions through the ordinary CLI, retaining isolated evidence."""
import argparse
import json
import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import time


def fixture(root):
    schema = Path(__file__).resolve().parents[1] / 'schema'
    modules = root / '.seihou/modules'
    for name in ('one', 'two'):
        target = modules / name
        (target / 'files').mkdir(parents=True)
        shutil.copytree(schema, target / 'schema', ignore=shutil.ignore_patterns('.git'))
        (target / 'files/value').write_text('{{git.createGithub}}/{{nix.redpanda}}\n')
        (target / 'module.dhall').write_text('let S = ./schema/package.dhall in S.Module::{name="' + name + '",version=Some "1.0.0",vars=[S.VarDecl::{name="git.createGithub",type="bool",default=Some "false"},S.VarDecl::{name="nix.redpanda",type="bool",default=Some "false"}],steps=[S.Step::{strategy="template",src="value",dest="' + name + '.txt"}],commands=[S.Command::{run="touch command-marker"}]}')
    recipe = modules / 'recipe-input-probe'
    recipe.mkdir()
    (recipe / 'recipe.dhall').write_text('''let S = ../one/schema/package.dhall in S.Recipe::{name="recipe-input-probe",version=Some "1.0.0",modules=[S.Dependency::{module="one"},S.Dependency::{module="two"}],vars=[S.VarDecl::{name="git.createGithub",type="bool",required=True},S.VarDecl::{name="nix.redpanda",type="bool",required=True}],prompts=[S.Prompt::{var="git.createGithub",text="Create a GitHub repository?"},S.Prompt::{var="nix.redpanda",text="Enable Redpanda?"}]}''')


def invoke(binary, root, env, args, answers=None):
    if answers is None:
        result = subprocess.run([binary, *args], cwd=root, env=env, input='', capture_output=True, text=True, timeout=120)
        return result.returncode, result.stdout + result.stderr
    master, slave = pty.openpty()
    child = subprocess.Popen([binary, *args], cwd=root, env=env, stdin=slave, stdout=slave, stderr=slave)
    os.close(slave)
    output = b''
    sent = set()
    try:
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            if select.select([master], [], [], .1)[0]:
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                output += chunk
                for question, answer in answers.items():
                    if question not in sent and question.encode() in output:
                        os.write(master, (answer + '\n').encode())
                        sent.add(question)
            if child.poll() is not None:
                break
        else:
            raise RuntimeError('interactive command timed out: ' + output.decode(errors='replace'))
        return child.wait(timeout=10), output.decode(errors='replace')
    finally:
        if child.poll() is None:
            child.kill()
            child.wait()
        os.close(master)


def consumer(binary, area, env):
    import re
    references = [
        'mori://shinzui/seihou-modules/templates/git-init',
        'mori://shinzui/seihou-modules/templates/nix-haskell-flake',
        'mori://shinzui/agent-seihou/templates/master-plan',
        'mori://shinzui/seihou-modules/templates/haskell-keiro-project',
    ]
    sources = {}
    revisions = {}
    for uri in references:
        output = subprocess.check_output(['mori', 'path', uri], text=True)
        source = Path(output.strip().splitlines()[-1])
        repo = Path(subprocess.check_output(['git', '-C', source, 'rev-parse', '--show-toplevel'], text=True).strip())
        revisions[uri] = subprocess.check_output(['git', '-C', repo, 'rev-parse', 'HEAD'], text=True).strip()
        for definition in (repo / 'modules').rglob('module.dhall'):
            sources[definition.parent.name] = definition.parent
    (area / 'consumer-revisions.json').write_text(json.dumps(revisions, indent=2))
    for choice in ('true', 'false'):
        root = area / ('consumer-' + choice)
        root.mkdir()
        modules = root / '.seihou/modules'
        pending = ['git-init', 'nix-haskell-flake', 'master-plan', 'haskell-keiro-project']
        copied = set()
        while pending:
            name = pending.pop()
            if name in copied:
                continue
            source = sources[name]
            shutil.copytree(source, modules / name, symlinks=False)
            copied.add(name)
            pending.extend(re.findall(r'module\s*=\s*"([^"\n]+)"', (source / 'module.dhall').read_text()))
        recipe = modules / 'recipe-input-probe'
        recipe.mkdir()
        shutil.copytree(Path(__file__).resolve().parents[1] / 'schema', recipe / 'schema', ignore=shutil.ignore_patterns('.git'))
        bindings = {'nix.postgresql': 'true', 'nix.process-compose': 'true', 'intentions.enabled': 'true', 'mori.generate': 'true', 'mori.namespace': 'tan'}
        literals = ','.join('{name=' + json.dumps(k) + ',value=' + json.dumps(v) + '}' for k, v in bindings.items())
        definition = 'let S = ./schema/package.dhall in S.Recipe::{name="recipe-input-probe",version=Some "1.0.0",modules=[S.Dependency::{module="git-init",vars=[' + literals + ']},S.Dependency::{module="nix-haskell-flake"},S.Dependency::{module="master-plan"},S.Dependency::{module="haskell-keiro-project"}],vars=[S.VarDecl::{name="git.createGithub",type="bool",required=True},S.VarDecl::{name="nix.redpanda",type="bool",required=True}],prompts=[S.Prompt::{var="git.createGithub",text="Create a GitHub repository?"},S.Prompt::{var="nix.redpanda",text="Enable Redpanda?"}]}'
        (recipe / 'recipe.dhall').write_text(definition)
        args = ['run', 'recipe-input-probe', '--no-commands', '--no-save-prompted']
        for key, value in {'project.name': 'recipe-probe', 'project.namespace': 'Probe', 'project.description': 'Recipe input acceptance', 'git.githubTeam': 'probe', 'nix.pg-database': 'probe'}.items():
            args.extend(['--var', key + '=' + value])
        answers = {'Create a GitHub repository?': choice, 'Enable Redpanda?': choice, 'GitHub org or username?': 'probe', 'GitHub repo name?': 'probe', 'Proceed? [Y/n]': 'y'}
        (area / ('consumer-' + choice + '-preparation.json')).write_text(json.dumps({'copiedModules': sorted(copied), 'command': args, 'answers': answers}, indent=2))
        code, output = invoke(binary, root, env, args, answers)
        (area / ('consumer-' + choice + '.txt')).write_text(output)
        assert code == 0, output
        for question in list(answers)[:2]:
            assert output.count(question) == 1, output
        assert ('GitHub org or username?' in output) == (choice == 'true'), output
        manifest = json.loads((root / '.seihou/manifest.json').read_text())
        assert manifest['applications'][0]['recipeInputs']['nix.redpanda'] == choice
        assert (root / 'nix/redpanda.nix').exists() == (choice == 'true')
    print('Representative consumer acceptance passed; commands intentionally disabled to avoid remote effects')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', required=True)
    parser.add_argument('--area', type=Path, required=True)
    parser.add_argument('--expect-unresolved-bug', action='store_true')
    parser.add_argument('--consumer', action='store_true')
    args = parser.parse_args()
    binary = shutil.which(args.binary) or str(Path(args.binary).resolve())
    args.area.mkdir(parents=True, exist_ok=False)
    env = {k: v for k, v in os.environ.items() if not k.startswith('SEIHOU_VAR_')}
    env.update(HOME=str(args.area / 'home'), XDG_CONFIG_HOME=str(args.area / 'config'), XDG_CACHE_HOME=str(args.area / 'cache'))
    for label, choice in [('true', 'true'), ('false', 'false')]:
        root = args.area / label
        root.mkdir()
        fixture(root)
        code, output = invoke(binary, root, env, ['run', 'recipe-input-probe'])
        (args.area / (label + '-closed.txt')).write_text(output)
        if args.expect_unresolved_bug:
            assert code == 0 and (root / 'one.txt').read_text().strip() == 'false/false', output
            print('Expected baseline bug reproduced: required recipe inputs ignored')
            return
        assert code != 0 and 'git.createGithub' in output and 'nix.redpanda' in output, output
        assert not (root / 'one.txt').exists() and not (root / '.seihou/manifest.json').exists()
        assert not (root / 'command-marker').exists() and not (root / '.seihou/config.dhall').exists()
        answers = {'Create a GitHub repository?': choice, 'Enable Redpanda?': choice, 'Save? [Y/n]': 'n', 'Proceed? [Y/n]': 'y'}
        code, output = invoke(binary, root, env, ['run', 'recipe-input-probe'], answers)
        (args.area / (label + '-interactive.txt')).write_text(output)
        assert code == 0, output
        for question in list(answers)[:2]:
            assert output.count(question) == 1, output
        for module in ('one', 'two'):
            assert (root / (module + '.txt')).read_text().strip() == choice + '/' + choice
        app = json.loads((root / '.seihou/manifest.json').read_text())['applications'][0]
        assert app['recipeInputs'] == {'git.createGithub': choice, 'nix.redpanda': choice}
        before = (root / '.seihou/manifest.json').read_bytes()
        code, output = invoke(binary, root, env, ['update', 'recipe-input-probe', '--dry-run'])
        (args.area / (label + '-update.txt')).write_text(output)
        assert code == 0, output
        assert (root / '.seihou/manifest.json').read_bytes() == before
        # A checked-in project must replay independently of config and caches.
        for command in [['git', 'init', '-q'], ['git', 'add', '.'], ['git', '-c', 'user.name=Recipe acceptance', '-c', 'user.email=recipe@example.test', 'commit', '-qm', 'fixture']]:
            subprocess.run(command, cwd=root, env=env, check=True, capture_output=True)
        clone = args.area / (label + '-clone')
        subprocess.run(['git', 'clone', '-q', str(root), str(clone)], check=True, capture_output=True)
        clone_env = dict(env, XDG_CONFIG_HOME=str(args.area / (label + '-clone-config')), XDG_CACHE_HOME=str(args.area / (label + '-clone-cache')))
        code, output = invoke(binary, clone, clone_env, ['update', 'recipe-input-probe', '--dry-run'])
        (args.area / (label + '-clone-update.txt')).write_text(output)
        assert code == 0 and 'Already up to date' in output, output
        # Change ambient input and add a new consumer to the producer recipe.
        opposite = 'false' if choice == 'true' else 'true'
        clone_env['SEIHOU_VAR_GIT_CREATEGITHUB'] = opposite
        third = root / '.seihou/modules/three'
        shutil.copytree(root / '.seihou/modules/two', third)
        definition = third / 'module.dhall'
        definition.write_text(definition.read_text().replace('name="two"', 'name="three"').replace('dest="two.txt"', 'dest="three.txt"'))
        recipe = root / '.seihou/modules/recipe-input-probe/recipe.dhall'
        recipe.write_text(recipe.read_text().replace('S.Dependency::{module="two"}', 'S.Dependency::{module="two"},S.Dependency::{module="three"}'))
        changed_env = dict(env, SEIHOU_VAR_GIT_CREATEGITHUB=opposite)
        code, output = invoke(binary, root, changed_env, ['update', 'recipe-input-probe'], {'Apply? [Y/n]': 'y'})
        (args.area / (label + '-new-consumer.txt')).write_text(output)
        assert code == 0, output
        assert (root / 'three.txt').read_text().strip() == choice + '/' + choice
        code, output = invoke(binary, root, changed_env, ['update', 'recipe-input-probe', '--dry-run'])
        assert code == 0 and 'Already up to date' in output, output
    if args.consumer:
        consumer(binary, args.area, env)
    print('Recipe terminal and replay acceptance passed: ' + str(args.area))


if __name__ == '__main__':
    main()

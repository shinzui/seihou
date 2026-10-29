"""Exercise recipe decisions through the ordinary CLI, retaining isolated evidence."""
import argparse
import json
import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import sys
import time


def fixture(root):
    schema = Path(__file__).resolve().parents[1] / 'schema'
    modules = root / '.seihou/modules'
    for name in ('one', 'two'):
        target = modules / name
        (target / 'files').mkdir(parents=True)
        shutil.copytree(schema, target / 'schema', ignore=shutil.ignore_patterns('.git'))
        (target / 'files/value').write_text('{{git.createGithub}}/{{nix.redpanda}}\n')
        (target / 'module.dhall').write_text('let S = ./schema/package.dhall in S.Module::{name="' + name + '",version=Some "1.0.0",vars=[S.VarDecl::{name="git.createGithub",type="bool",default=Some "false"},S.VarDecl::{name="nix.redpanda",type="bool",default=Some "false"}],steps=[S.Step::{strategy="template",src="value",dest="' + name + '.txt"}],commands=[S.Command::{action=S.Command.Action.Apply "touch command-marker"}]}')
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


def owner_policy(binary, area, env, producer, previous_revision):
    """Install the actual producer; never synthesize or populate its members."""
    root = area / 'owner-policy'
    root.mkdir()
    commands = []

    def run(label, args, answers=None, cwd=root, run_env=env, expected=0):
        commands.append({'label': label, 'command': [binary, *args], 'answers': answers})
        code, output = invoke(binary, cwd, run_env, args, answers)
        (area / (label + '.txt')).write_text(output)
        (area / 'owner-policy-preparation.json').write_text(json.dumps(commands, indent=2))
        assert code == expected, output
        return output

    run('owner-version', ['--version'])
    run('owner-install', ['install', producer, '--module', 'tan-keiro-project'])
    run('owner-config', ['config', 'set', 'git.githubOwner', 'someone-else', '--global'])
    # Closed stdin proves the bug report's unattended path, without an owner flag.
    flags = ['--var', 'project.name=probe', '--var', 'project.namespace=Probe',
             '--var', 'project.description=probe', '--var', 'git.createGithub=true',
             '--var', 'git.repoName=probe', '--var', 'nix.redpanda=false']
    output = run('owner-preview', ['run', 'tan-keiro-project', '--dry-run', '--no-save-prompted', *flags])
    assert 'gh repo create topagentnetwork/probe' in output, output
    assert 'gh repo create someone-else/' not in output, output
    assert not (root / '.seihou/manifest.json').exists()
    output = run('owner-rejected', ['run', 'tan-keiro-project', *flags,
                                   '--var', 'git.githubOwner=someone-else'], expected=1)
    assert 'git.githubOwner' in output and '--var' in output and '^topagentnetwork$' in output, output
    assert not (root / '.seihou/manifest.json').exists()
    assert not (root / 'flake.nix').exists()
    # Preview the ordinary one-command interactive workflow; no project answer flags.
    answers = {'Create a private GitHub repository in topagentnetwork?': 'true',
               'Enable Redpanda lifecycle tools?': 'false',
               'Project name? (lowercase, hyphenated)': 'probe',
               'One-line project synopsis?': 'probe',
               'Haskell namespace? (single PascalCase segment)': 'Probe',
               'GitHub repository name?': 'probe', 'Organization team to grant access?': '', 'Save? [Y/n]': 'n'}
    output = run('owner-interactive-preview', ['run', 'tan-keiro-project', '--dry-run'], answers)
    assert 'gh repo create topagentnetwork/probe' in output, output
    # Safe generation deliberately skips provisioning. Command suppression is
    # recorded here; the separate public-binary fixture tests effect prevention.
    run('owner-apply', ['run', 'tan-keiro-project', '--no-commands', '--no-save-prompted', *flags])
    manifest = root / '.seihou/manifest.json'
    before = manifest.read_bytes()
    assert json.loads(before)['applications'][0]['recipeInputs']['git.githubOwner'] == 'topagentnetwork'
    run('owner-repeat', ['run', 'tan-keiro-project', '--no-commands', '--no-save-prompted', *flags])
    before = manifest.read_bytes()
    for label, extra in [('owner-update', []), ('owner-reconfigure', ['--reconfigure', *flags])]:
        run(label, ['update', 'tan-keiro-project', '--dry-run', *extra])
        assert manifest.read_bytes() == before
    run('owner-update-rejected', ['update', 'tan-keiro-project', '--var', 'git.githubOwner=someone-else'], expected=1)
    assert manifest.read_bytes() == before
    for command in [['git', 'init', '-q'], ['git', 'add', '.'],
                    ['git', '-c', 'commit.gpgsign=false', '-c', 'user.name=Recipe acceptance',
                     '-c', 'user.email=recipe@example.test', 'commit', '-qm', 'fixture']]:
        subprocess.run(command, cwd=root, env=env, check=True, capture_output=True)
    clone = area / 'owner-clone'
    subprocess.run(['git', 'clone', '-q', str(root), str(clone)], env=env, check=True, capture_output=True)
    clone_env = dict(env, HOME=str(area / 'clone-home'), XDG_CONFIG_HOME=str(area / 'clone-config'),
                     XDG_CACHE_HOME=str(area / 'clone-cache'))
    run('owner-clone-config', ['config', 'set', 'git.githubOwner', 'someone-else', '--global'], cwd=clone, run_env=clone_env)
    run('owner-clone-update', ['update', 'tan-keiro-project', '--dry-run'], cwd=clone, run_env=clone_env)
    # Exercise the actual producer command phase with harmless provisioning
    # stubs. Git runs normally in this disposable project; gh and registration
    # record arguments and never contact GitHub or the operator's Mori registry.
    stubs = area / 'command-stubs'
    stubs.mkdir()
    command_log = area / 'provisioning.jsonl'
    for name in ('gh', 'sh'):
        executable = stubs / name
        executable.write_text('#!' + sys.executable + '\n' +
            "import json, os, sys\n" +
            "from pathlib import Path\n" +
            "name = Path(sys.argv[0]).name\n" +
            "with open(os.environ['OWNER_POLICY_COMMAND_LOG'], 'a') as stream: stream.write(json.dumps([name, *sys.argv[1:]]) + '\\n')\n" +
            "if name == 'sh' and sys.argv[1:] != ['scripts/tan-mori-register']: os.execv('/bin/sh', ['/bin/sh', *sys.argv[1:]])\n")
        executable.chmod(0o755)
    effect_root = area / 'owner-effects'
    effect_root.mkdir()
    effect_env = dict(env, PATH=str(stubs) + os.pathsep + env['PATH'],
                      OWNER_POLICY_COMMAND_LOG=str(command_log),
                      GIT_AUTHOR_NAME='Recipe acceptance', GIT_COMMITTER_NAME='Recipe acceptance',
                      GIT_AUTHOR_EMAIL='recipe@example.test', GIT_COMMITTER_EMAIL='recipe@example.test')
    run('owner-effects-rejected', ['run', 'tan-keiro-project', *flags, '--var', 'git.githubOwner=someone-else'],
        cwd=effect_root, run_env=effect_env, expected=1)
    assert not command_log.exists()
    assert not (effect_root / '.seihou/manifest.json').exists()
    assert not (effect_root / 'flake.nix').exists()
    run('owner-effects-apply', ['run', 'tan-keiro-project', '--no-save-prompted', *flags], cwd=effect_root, run_env=effect_env)
    records = [json.loads(line) for line in command_log.read_text().splitlines()]
    assert ['gh', 'repo', 'create', 'topagentnetwork/probe', '--private', '--source=.', '--remote=origin', '--push'] in records, records
    assert ['sh', 'scripts/tan-mori-register'] in records, records
    manifest_before = (effect_root / '.seihou/manifest.json').read_bytes()
    commands_before = command_log.read_bytes()
    run('owner-effects-repeat-rejected', ['run', 'tan-keiro-project', *flags, '--var', 'git.githubOwner=someone-else'],
        cwd=effect_root, run_env=effect_env, expected=1)
    assert (effect_root / '.seihou/manifest.json').read_bytes() == manifest_before
    assert command_log.read_bytes() == commands_before
    if previous_revision:
        # Recreate an actual older application using committed producer history
        # and only public install/run/update commands. No manifest edits.
        old_repo = area / 'previous-producer'
        subprocess.run(['git', 'clone', '-q', producer, str(old_repo)], env=env, check=True, capture_output=True)
        subprocess.run(['git', '-C', str(old_repo), 'checkout', '-q', previous_revision], env=env, check=True, capture_output=True)
        old_env = dict(env)
        # Replace an existing candidate redirect, or append one for published checks.
        index = int(old_env.get('GIT_CONFIG_COUNT', '0'))
        rewrite_key = 'url.'
        for i in range(index):
            if old_env.get(f'GIT_CONFIG_KEY_{i}', '').startswith(rewrite_key) and old_env.get(f'GIT_CONFIG_VALUE_{i}') == producer:
                old_env[f'GIT_CONFIG_KEY_{i}'] = 'url.' + old_repo.as_uri() + '.insteadOf'
                break
        else:
            old_env.update({f'GIT_CONFIG_KEY_{index}': 'url.' + old_repo.as_uri() + '.insteadOf',
                            f'GIT_CONFIG_VALUE_{index}': producer, 'GIT_CONFIG_COUNT': str(index + 1)})
        adoption = area / 'owner-adoption'
        adoption.mkdir()
        old_env.update(HOME=str(area / 'adoption-home'), XDG_CONFIG_HOME=str(area / 'adoption-config'),
                       XDG_CACHE_HOME=str(area / 'adoption-cache'))
        run('owner-previous-install', ['install', producer, '--module', 'tan-keiro-project'], cwd=adoption, run_env=old_env)
        run('owner-previous-config', ['config', 'set', 'git.githubOwner', 'someone-else', '--global'], cwd=adoption, run_env=old_env)
        run('owner-previous-apply', ['run', 'tan-keiro-project', '--no-commands', '--no-save-prompted', *flags], cwd=adoption, run_env=old_env)
        old_manifest = adoption / '.seihou/manifest.json'
        before = old_manifest.read_bytes()
        assert json.loads(before)['applications'][0]['recipeInputs']['git.githubOwner'] == 'someone-else'
        next_env = dict(env, HOME=old_env['HOME'], XDG_CONFIG_HOME=old_env['XDG_CONFIG_HOME'], XDG_CACHE_HOME=old_env['XDG_CACHE_HOME'])
        run('owner-adoption-preview', ['update', 'tan-keiro-project', '--dry-run', '--no-commands'], cwd=adoption, run_env=next_env)
        assert old_manifest.read_bytes() == before
        run('owner-adoption-apply', ['update', 'tan-keiro-project', '--no-commands'], {'Organization team to grant access?': '', 'Apply? [Y/n]': 'y'}, cwd=adoption, run_env=next_env)
        assert json.loads(old_manifest.read_bytes())['applications'][0]['recipeInputs']['git.githubOwner'] == 'topagentnetwork'
    print('Actual TAN owner policy passed: install, preview, interactive, rejection, safe generation, repeat, update, reconfigure and fresh clone')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', required=True)
    parser.add_argument('--area', type=Path, required=True)
    parser.add_argument('--expect-unresolved-bug', action='store_true')
    parser.add_argument('--consumer', action='store_true')
    parser.add_argument('--owner-policy', action='store_true', help='Install and exercise the actual TAN recipe')
    parser.add_argument('--producer', default='https://github.com/topagentnetwork/tan-seihou-modules.git')
    parser.add_argument('--previous-producer-revision', help='Replay adoption from this committed producer revision using normal install/run/update')
    parser.add_argument('--candidate-repo', type=Path, help='Redirect only the TAN Git URL to this committed candidate for unpublished acceptance')
    parser.add_argument('--github-auth', action='store_true', help='Retain current gh credentials in subprocess memory for private-registry installs')
    args = parser.parse_args()
    binary = str(Path(shutil.which(args.binary) or args.binary).resolve())
    args.area.mkdir(parents=True, exist_ok=False)
    env = {k: v for k, v in os.environ.items() if not k.startswith('SEIHOU_VAR_') and k != 'SEIHOU_CONTEXT'}
    if args.github_auth:
        env['GH_TOKEN'] = subprocess.check_output(['gh', 'auth', 'token'], text=True).strip()
        env.update(GIT_CONFIG_COUNT='2', GIT_CONFIG_KEY_0='credential.https://github.com.helper',
                   GIT_CONFIG_VALUE_0='', GIT_CONFIG_KEY_1='credential.https://github.com.helper',
                   GIT_CONFIG_VALUE_1='gh auth git-credential')
    if args.candidate_repo:
        assert args.owner_policy, '--candidate-repo requires --owner-policy'
        candidate = args.candidate_repo.resolve()
        assert not subprocess.check_output(['git', '-C', str(candidate), 'status', '--porcelain'], text=True).strip(), 'Commit the producer candidate before acceptance'
        index = int(env.get('GIT_CONFIG_COUNT', '0'))
        env.update({f'GIT_CONFIG_KEY_{index}': 'url.' + candidate.as_uri() + '.insteadOf',
                    f'GIT_CONFIG_VALUE_{index}': args.producer, 'GIT_CONFIG_COUNT': str(index + 1)})
        (args.area / 'candidate-source.json').write_text(json.dumps({
            'url': args.producer, 'candidate': str(candidate),
            'revision': subprocess.check_output(['git', '-C', str(candidate), 'rev-parse', 'HEAD'], text=True).strip(),
            'preparation': 'Git URL rewrite for unpublished candidate; installer and update still own the complete closure'}, indent=2))
    env.update(HOME=str(args.area / 'home'), XDG_CONFIG_HOME=str(args.area / 'config'), XDG_CACHE_HOME=str(args.area / 'cache'))
    if args.owner_policy:
        owner_policy(binary, args.area, env, args.producer, args.previous_producer_revision)
        return
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

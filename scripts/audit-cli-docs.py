#!/usr/bin/env python3
"""Check help/command coverage, packaged assets, and optional provider-free renders.

This checks wiring and discoverability. Release reviewers must also compare the
meaning of the help and prompts with the changes being released.
"""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / 'seihou-cli'


def require(condition, message):
    if not condition:
        raise SystemExit(f'CLI documentation audit failed: {message}')


def source_audit():
    help_source = (CLI / 'src-exe/Seihou/CLI/Help.hs').read_text()
    entries = re.findall(r'HelpTopic "([\w-]+)" "[^"]+" (\w+)', help_source)
    topics = {name for name, _ in entries}
    require(len(topics) == len(entries), 'duplicate help topic')
    bindings = dict(re.findall(r'(\w+) = \$\(embedStringFile "(help/[^"]+)"\)', help_source))
    require(all(bindings.get(content) == f'help/{name}.md' for name, content in entries),
            'topic does not embed its matching help file')
    files = {path.stem for path in (CLI / 'help').glob('*.md')}
    require(topics == files, f'unregistered/missing help files: {topics ^ files}')

    docs = (ROOT / 'docs/cli/help.md').read_text()
    index, coverage = docs.split('## Command coverage', 1)
    documented = set(re.findall(r'^\| `([\w-]+)` \|', index.split('## Available Topics', 1)[1], re.M))
    require(topics == documented, f'help index differs from executable topics: {topics ^ documented}')
    command_topics = {}
    for topic, cells in re.findall(r'^\| `([\w-]+)` \| (.+) \|$', coverage, re.M):
        require(topic in topics, f'command coverage names unknown topic {topic}')
        for command in re.findall(r'`([\w-]+)`', cells):
            require(command not in command_topics, f'duplicate command coverage: {command}')
            command_topics[command] = topic
    parser = (CLI / 'src-exe/Seihou/CLI/Commands.hs').read_text()
    top_level = parser.split('commandParser =', 1)[1].split('-- Command info blocks', 1)[0]
    commands = set(re.findall(r'command "([\w-]+)"', top_level))
    require(commands == set(command_topics), f'undocumented/removed commands: {commands ^ set(command_topics)}')

    cabal = (CLI / 'seihou-cli.cabal').read_text().split('extra-source-files:', 1)[1].split('source-repository', 1)[0]
    packaged = set(cabal.split())
    assets = {f'{directory}/{path.name}' for directory in ('data', 'help')
              for path in (CLI / directory).glob('*.md')}
    require(assets <= packaged, f'assets missing from sdist: {assets - packaged}')
    embedded = set()
    for directory in ('src', 'src-exe'):
        for path in (CLI / directory).rglob('*.hs'):
            embedded.update(re.findall(r'embed(?:String)?File "((?:data|help)/[^"]+)"', path.read_text()))
    require(assets == embedded, f'unembedded/missing assets: {assets ^ embedded}')
    for asset in assets:
        for target in re.findall(r'seihou help ([a-z][a-z-]*)', (CLI / asset).read_text()):
            require(target in topics, f'{asset}: link to unknown help topic {target}')
    print(f'Source audit passed: {len(topics)} topics, {len(commands)} commands, {len(assets)} packaged assets.')
    return topics, commands


def runtime_audit(executable, topics, commands, report):
    executable = str(Path(executable).resolve())
    with tempfile.TemporaryDirectory(prefix='seihou-doc-audit-') as temporary:
        project = Path(temporary)
        env = {key: value for key, value in os.environ.items()
               if not key.startswith(('SEIHOU_', 'XDG_'))}
        for key, directory in [('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache'),
                               ('XDG_STATE_HOME', 'state'), ('XDG_DATA_HOME', 'data')]:
            env[key] = str(project / directory)

        def run(args, label=None):
            result = subprocess.run([executable, *args], cwd=project, env=env,
                                    text=True, capture_output=True, timeout=240)
            require(result.returncode == 0, f'{args}: {result.stderr}\n{result.stdout}')
            require(result.stdout.strip(), f'{args}: empty output')
            if report and label:
                (report / f'{label}.txt').write_text(result.stdout + result.stderr)
            return result.stdout

        version = run(['--version'], 'version').strip()
        index = run(['help'], 'help-index')
        listed = set(re.findall(r'^  ([\w-]+)\s+', index, re.M))
        require(listed == topics, 'built executable has a stale help index')
        for topic in sorted(topics):
            output = run(['help', topic], f'help-{topic}')
            require(output.strip() == (CLI / f'help/{topic}.md').read_text().strip(),
                    f'built help {topic} differs from source')
        for command in sorted(commands):
            run([command, '--help'])

        # Explicit local-schema fixtures exercise renderers without a network or provider.
        modules = project / '.seihou/modules'
        modules.mkdir(parents=True)
        schema = (ROOT / 'schema/package.dhall').as_posix()
        for name, definition, body in [
            ('audit-module', 'module', 'S.Module::{ name = "audit-module", version = Some "1.0.0" }'),
            ('audit-blueprint', 'blueprint', 'S.Blueprint::{ name = "audit-blueprint", prompt = "Audit blueprint", migrations = [ S.BlueprintMigration::{ from = "1.0.0", to = "2.0.0", prompt = "Audit migration" } ] }'),
            ('audit-prompt', 'prompt', 'S.AgentPrompt::{ name = "audit-prompt", prompt = "Audit prompt" }'),
        ]:
            directory = modules / name
            directory.mkdir()
            (directory / f'{definition}.dhall').write_text(f'let S = {schema}\nin {body}\n')
        # Type-check the actual authoring examples through the public validator.
        reference = (CLI / 'data/module-reference.md').read_text()
        examples = re.findall(r"```dhall\n(.*?)```", reference, re.S)
        require(len(examples) == 3, 'expected module, checkout and removal examples')
        example_modules = {
            'nix-base': 'S.Module::{ name = "nix-base", version = Some "1.0.0" }',
            'my-module': examples[0],
            'audit-checkout': 'S.Module::{ name = "audit-checkout", version = Some "1.0.0", steps = [ ' + examples[1] + ' ] }',
            'audit-removal': 'S.Module::{ name = "audit-removal", version = Some "1.0.0", ' + examples[2] + ' }',
        }
        for name, body in example_modules.items():
            directory = modules / name
            (directory / 'files').mkdir(parents=True)
            (directory / 'module.dhall').write_text(f'let S = {schema}\nin {body}\n')
            (directory / 'files/README.md.tpl').write_text('# {{project.name}}\n')
            run(['validate-module', str(directory)], f'example-{name}')
        cases = [
            ('assist', ['agent', '--debug', 'assist'], 'assist-prompt.md'),
            ('bootstrap', ['agent', '--debug', 'bootstrap'], 'bootstrap-prompt.md'),
            ('bootstrap-repo', ['agent', '--debug', 'bootstrap', '--repo'], 'bootstrap-prompt.md'),
            ('setup', ['agent', '--debug', 'setup'], 'setup-prompt.md'),
            ('blueprint', ['agent', '--debug', 'run', 'audit-blueprint', '--no-baseline'], 'blueprint-prompt.md'),
            ('migration', ['agent', '--debug', 'migrate', 'audit-blueprint', '--from', '1.0.0', '--to', '2.0.0'], 'blueprint-migration-prompt.md'),
            ('prompt', ['prompt', 'run', 'audit-prompt', '--debug'], 'prompt-run-prompt.md'),
            ('upgrade', ['agent', '--debug', 'upgrade', 'audit-module'], 'upgrade-prompt.md'),
        ]
        for name, args, template in cases:
            output = run(args, f'prompt-{name}')
            require((CLI / f'data/{template}').read_text().splitlines()[0] in output,
                    f'{name}: wrong template rendered')
            require(str(project) in output, f'{name}: missing current environment')
            for slot in ('cwd', 'module_reference', 'manifest_state', 'available_modules',
                         'bootstrap_mode', 'baseline_status', 'blueprint_name', 'prompt_body',
                         'migration_from', 'diagnosis_summary', 'backup_dir'):
                require('{{' + slot + '}}' not in output, f'{name}: unresolved runtime slot {slot}')
            if name in ('assist', 'bootstrap', 'bootstrap-repo', 'setup'):
                require((CLI / 'data/module-reference.md').read_text().strip() in output,
                        f'{name}: shared module reference is not rendered')
        print(f'Runtime audit passed: {version}; {len(topics)} topics, {len(commands)} command help pages, {len(example_modules)} example modules validated, {len(cases)} prompt renders (no providers).')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--executable', help='built seihou executable; omit for source checks only')
    parser.add_argument('--report-dir', type=Path, help='save rendered evidence outside the repository')
    args = parser.parse_args()
    if args.report_dir:
        args.report_dir = args.report_dir.resolve()
        args.report_dir.mkdir(parents=True, exist_ok=True)
    topics, commands = source_audit()
    if args.executable:
        runtime_audit(args.executable, topics, commands, args.report_dir)
    else:
        print('Runtime audit not run; use just audit-cli-docs to build and exercise the executable.')


if __name__ == '__main__':
    main()

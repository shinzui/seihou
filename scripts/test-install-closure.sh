#!/usr/bin/env bash
set -euo pipefail
# An isolated public-command proof, with no writes to the user's install cache.
python3 - "$1" "$(pwd)/schema" <<'PY'
import json, os, pathlib, subprocess, sys, tempfile
binary, schema = sys.argv[1:]
with tempfile.TemporaryDirectory(prefix='seihou-closure-acceptance-') as tmp:
    base = pathlib.Path(tmp)
    env = dict(os.environ, XDG_CONFIG_HOME=str(base/'config'), XDG_CACHE_HOME=str(base/'cache'))
    work = base/'work'; work.mkdir()
    def run(*args, ok=True):
        p = subprocess.run([binary,*args], cwd=work, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        print(p.stdout)
        assert (p.returncode == 0) == ok, (args,p.returncode)
        return p.stdout
    def git(repo,*args):
        subprocess.run(['git','-C',str(repo),*args],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    def write(p,s):
        p.parent.mkdir(parents=True,exist_ok=True); p.write_text(s)
    def dep(name,source=None):
        return '{ module = '+json.dumps(name)+', vars = [] : List { name : Text, value : Text }, source = '+('None Text' if source is None else 'Some '+json.dumps(str(source)))+' }'
    a,b,c = [base/n for n in ['a','b','c']]
    for repo in [a,b,c]:
        repo.mkdir(); git(repo,'init','-q')
    def module(repo,name,deps=[]):
        text = f'let S = {schema}/package.dhall in S.Module::{{ name = "{name}", version = Some "1.0.0", steps = [ S.Step::{{ strategy = "copy", src = "payload", dest = "{name}.txt" }} ]'
        if deps: text += ', dependencies = [ '+', '.join(deps)+' ]'
        text += ' }'
        write(repo/name/'module.dhall',text); write(repo/name/'files'/'payload',name)
    module(c,'leaf'); module(c,'sentinel-c')
    module(b,'external',[dep('leaf',c)]); module(b,'sentinel-b')
    module(a,'local'); module(a,'sentinel-a')
    write(a/'root'/'recipe.dhall',f'let S = {schema}/package.dhall in S.Recipe::{{ name = "root", modules = [ '+dep('local')+', '+dep('external',b)+' ] }')
    def registry(repo,mods,recipes=[]):
        entries=lambda names: '[ '+', '.join(f'{{ name = "{n}", path = "{n}", version = None Text, description = None Text, tags = [] : List Text }}' for n in names)+' ]'
        text='{ repoName = "fixture", repoDescription = None Text, modules = '+entries(mods)
        if recipes: text += ', recipes = '+entries(recipes)
        write(repo/'seihou-registry.dhall',text+' }')
        git(repo,'add','.'); git(repo,'-c','user.name=Fixture','-c','user.email=fixture@example.com','commit','-qm','fixture')
    registry(c,['leaf','sentinel-c']); registry(b,['external','sentinel-b']); registry(a,['local','sentinel-a'],['root'])
    run('install',str(a),'--module','root')
    cache=base/'config'/'seihou'/'installed'
    assert set(p.name for p in cache.iterdir()) == {'root','local','external','leaf'}
    for name,repo in [('root',a),('local',a),('external',b),('leaf',c)]:
        assert json.loads((cache/name/'.seihou-origin.json').read_text())['sourceUrl']==str(repo)
    run('run','root')
    assert (work/'leaf.txt').read_text()=='leaf'
    snapshot=lambda: sorted((str(p.relative_to(cache)),p.read_bytes()) for p in cache.rglob('*') if p.is_file())
    before=snapshot(); run('run','root','--dry-run','--no-save-prompted'); assert before==snapshot()
    run('install',str(a),'--module','root')
    # Every refusal preserves existing contents and reports the requesting chain.
    def save(repo):
        git(repo,'add','.')
        git(repo,'-c','user.name=Fixture','-c','user.email=fixture@example.com','commit','--allow-empty','-qm','scenario')
    original=(a/'root'/'recipe.dhall').read_text()
    def recipe(members):
        write(a/'root'/'recipe.dhall',f'let S = {schema}/package.dhall in S.Recipe::{{ name = "root", modules = [ '+', '.join(members)+' ] }'); save(a)
    def refused(*flags,contains):
        before=snapshot(); out=run('install',str(a),'--module','root',*flags,ok=False)
        assert contains in out, (contains,out)
        assert 'selected artifacts are ready' not in out and snapshot()==before
        return out
    recipe([dep('missing',b)]); out=refused(contains='missing'); assert str(b) in out and 'root' in out
    recipe([dep('external',base/'unavailable')]); refused(contains='unavailable')
    write(a/'root'/'recipe.dhall',original); save(a)
    run('install',str(a),'--module','root')
    marker=cache/'external'/'marker'; marker.write_text('preserve')
    metadata=cache/'external'/'.seihou-origin.json'
    info=json.loads(metadata.read_text()); info['sourceUrl']='https://example.com/foreign.git'; metadata.write_text(json.dumps(info))
    refused(contains='different artifact'); assert marker.read_text()=='preserve'
    run('install',str(a),'--module','root','--force'); assert not marker.exists()
    metadata.unlink(); marker.write_text('unknown'); refused(contains='no provenance')
    run('install',str(a),'--module','root','--force')
    module(c,'external'); registry(c,['leaf','sentinel-c','external'])
    module(a,'local',[dep('external',c)]); save(a)
    recipe([dep('local'),dep('external',b)]); refused('--force',contains='conflicting sources')
    module(a,'local'); save(a)
    module(b,'external',[dep('external')]); save(b)
    recipe([dep('external',b)]); refused(contains='cycle')
    module(b,'external',[dep('leaf',c)]); save(b)
    write(a/'root'/'recipe.dhall',original); save(a)
    run('install',str(a),'--module','root')
    module(a,'local',[dep('leaf',c)]); save(a)
    run('install',str(a),'--module','root')
    assert set(p.name for p in cache.iterdir())=={'root','local','external','leaf'}
    # Explicit requirements refuse unproven local shadows before generation.
    shadow=work/'.seihou'/'modules'/'external'
    import shutil
    shutil.copytree(cache/'external',shadow)
    (shadow/'.seihou-origin.json').unlink()
    out=run('run','root','--dry-run','--no-save-prompted',ok=False)
    assert 'provenance' in out and 'external' in out
    shutil.rmtree(shadow)
    # Legacy bare names still follow same-registry acquisition.
    write(a/'root'/'recipe.dhall','{ name = "root", version = None Text, description = None Text, modules = ["local"], vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) } }'); save(a)
    run('install',str(a),'--module','root')
    run('run','root','--dry-run','--no-save-prompted')
    print('PASS: closure, origins, run, dry-run, repeat, missing/unavailable source, collisions, force, contradictory sources, cycle, diamond, local shadow, legacy names')
PY

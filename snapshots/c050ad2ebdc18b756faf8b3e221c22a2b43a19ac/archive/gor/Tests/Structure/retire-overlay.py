#!/usr/bin/env python3
"""Move exact absorbed overlay inputs to a rollback backup before compilation."""
from pathlib import Path
import datetime, hashlib, importlib.util, json, shutil, sys

def regular(p):
    if p.is_symlink() or not p.is_file():
        raise RuntimeError('overlay retirement: expected regular file: '+str(p))
    return hashlib.sha256(p.read_bytes()).hexdigest()

def safe(relative):
    p=Path(relative)
    if p.is_absolute() or '..' in p.parts or not relative.startswith('Sources/gor/') or p.suffix!='.swift':
        raise RuntimeError('overlay retirement: unsafe source path')
    return relative

def retire(project, backups, external):
    project,backups,external=map(Path,(project,backups,external))
    data=json.loads((project/'Tests/Structure/retirements.json').read_text())
    if data['schema']!=1: raise RuntimeError('overlay retirement: unknown inventory schema')
    present=[];seen=set()
    for item in data['entries']:
        rel=safe(item['path'])
        if rel in seen: raise RuntimeError('overlay retirement: duplicate inventory path')
        seen.add(rel);p=project/rel
        if not p.exists() and not p.is_symlink():continue
        actual=regular(p)
        accepted=item.get('accepted_sha256',[item['sha256']])
        if actual not in accepted:raise RuntimeError('overlay retirement: local edits preserved: '+rel+' sha256='+actual)
        if not item['replacements']:raise RuntimeError('overlay retirement: missing replacement')
        for dest,digest in item['replacements'].items():
            dest_rel,_,dest_unit=dest.partition('#')
            if dest_unit:
                ss=importlib.util.spec_from_file_location('section_source',project/'Tests/Structure/section_source.py')
                if ss is None or not (project/'Tests/Structure/section_source.py').is_file():raise RuntimeError('overlay retirement: section pin without resolver: '+dest)
                mod=importlib.util.module_from_spec(ss)
                try:ss.loader.exec_module(mod);got=hashlib.sha256(mod.pinned_bytes(project,dest)).hexdigest()
                except Exception:raise RuntimeError('overlay retirement: replacement mismatch: '+dest)
                if got!=digest:raise RuntimeError('overlay retirement: replacement mismatch: '+dest)
            elif regular(project/safe(dest))!=digest:raise RuntimeError('overlay retirement: replacement mismatch: '+dest)
        present.append(rel)
    if not present:
        print('overlay retirement: no absorbed sources remain');return None
    # Reuse the full pre-update inventory, so --rollback restores one coherent tree.
    prior=next((p for p in sorted(backups.glob('*-pre-update'),reverse=True) if (p/'changes.txt').is_file()),None)
    if prior is None:raise RuntimeError('overlay retirement: pre-update rollback backup missing; nothing moved')
    rows=[]
    for line in (prior/'changes.txt').read_text().splitlines():
        kind,rel=line.split('\t',1);p=Path(rel)
        if kind not in ('added','changed','deleted') or p.is_absolute() or '..' in p.parts:raise RuntimeError('overlay retirement: unsafe rollback manifest')
        if kind!='added':regular(prior/rel)
        rows.append((kind,rel))
    name=datetime.datetime.now().strftime('%y%m%d-%H%M%S-%f')+'-absorbed-sources'
    dest=external/name;pointer=backups/name
    external.mkdir(parents=True,exist_ok=True)
    if dest.exists() or pointer.exists() or pointer.is_symlink():raise RuntimeError('overlay retirement: backup collision')
    shutil.copytree(prior,dest)
    # Copy and verify all originals before moving any. Saved copies also permit
    # recovery if moving across disks fails halfway through.
    for rel in present:
        p=dest/'retired-inputs'/rel;p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(project/rel,p)
        if regular(p)!=regular(project/rel):raise RuntimeError('overlay retirement: backup verification failed')
        target=dest/rel;target.parent.mkdir(parents=True,exist_ok=True)
        if not target.exists():shutil.copy2(project/rel,target)
        if not any(r==rel for _,r in rows):rows.append(('deleted',rel))
    (dest/'changes.txt').write_text(''.join(k+'\t'+r+'\n' for k,r in rows))
    (dest/'retirement.json').write_text(json.dumps({'prior_update':str(prior),'moved':present},indent=2)+'\n')
    pointer.symlink_to(dest.resolve(),target_is_directory=True)
    moved=[]
    try:
        for rel in present:
            target=dest/'moved-inputs'/rel;target.parent.mkdir(parents=True,exist_ok=True)
            shutil.move(str(project/rel),str(target));moved.append(rel)
    except OSError:
        for rel in moved:shutil.copy2(dest/'retired-inputs'/rel,project/rel)
        raise RuntimeError('overlay retirement: move failed; originals restored; build refused')
    print('overlay retirement: moved %d exact inputs; backup=%s'%(len(present),dest))
    print('overlay retirement: rollback with ./build.sh --rollback '+name)
    return dest

if __name__=='__main__':
    try:retire(*sys.argv[1:])
    except (OSError,RuntimeError,ValueError,KeyError) as e:raise SystemExit(str(e))

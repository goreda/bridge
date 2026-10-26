#!/usr/bin/env python3
"""Apply a verified Gor kit to an explicit local tree. Offline. Draft, not delivery."""
import argparse,datetime,hashlib,json,os,pathlib,shutil,stat,subprocess,tempfile

sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def safe(root,rel):
    parts=pathlib.PurePosixPath(rel).parts
    if not parts or rel.startswith('/') or any(x in ('..','.') for x in parts): raise ValueError('unsafe path '+rel)
    p=root
    for part in parts:
        p=p/part
        if p.is_symlink(): raise ValueError('symlink '+str(p))
    return p

def inventory(root):
    out={}
    for p in root.rglob('*'):
        mode=p.lstat().st_mode
        if stat.S_ISDIR(mode): continue
        if not stat.S_ISREG(mode): raise ValueError('nonregular resource '+str(p))
        out[p.relative_to(root).as_posix()]=sha(p)
    return out

def replace_file(src,dst):
    fd,name=tempfile.mkstemp(prefix='.gor-kit-',dir=dst.parent)
    try:
        with os.fdopen(fd,'wb') as f: f.write(src.read_bytes());f.flush();os.fsync(f.fileno())
        shutil.copymode(dst if dst.exists() else src,name);os.replace(name,dst)
    finally:
        if os.path.exists(name):os.unlink(name)

def restore(root,backup):
    if (root/'.gor-build.lock').exists():raise ValueError('active/interrupted build lock')
    try: rec=json.loads((backup/'BACKUP.json').read_text())
    except (OSError,ValueError) as e: raise ValueError('corrupt backup metadata: '+repr(e)) from e
    for key in ('root','applied_files','backup_files','resource_path','resource_absent','applied_resource'):
        if key not in rec: raise ValueError('corrupt backup metadata: missing '+key)
    if str(root)!=rec['root']: raise ValueError('backup belongs to another root')
    for rel,digest in rec['applied_files'].items():
        p=safe(root,rel)
        old=safe(backup,rel)
        if not old.is_file() or sha(old)!=rec['backup_files'][rel]:raise ValueError('corrupt backup: '+rel)
        if not p.is_file() or sha(p) not in (digest,rec['backup_files'][rel]): raise ValueError('changed after apply; refusing restore: '+rel)
    res=safe(root,rec['resource_path'])
    if res.exists() and (not res.is_dir() or inventory(res)!=rec['applied_resource']): raise ValueError('resource changed after apply; refusing restore')
    for rel in rec['applied_files']: replace_file(backup/rel,safe(root,rel))
    if res.exists():shutil.rmtree(res)
    if not rec['resource_absent']:shutil.copytree(backup/rec['resource_path'],res)
    print('Restored source/resource backup:',backup,flush=True)

def verify_backup_authority(root,backup,kit):
    # A backup is data, never authority. Restrict restore to this kit's exact
    # targets, known previous bytes, expected applied bytes and resource path.
    meta=json.loads((kit/'HASHES-DRAFT.json').read_text())
    rec=json.loads((backup/'BACKUP.json').read_text())
    files={f['path']:f for f in meta['files']}
    if rec.get('root')!=str(root):raise ValueError('backup root mismatch')
    if set(rec.get('backup_files',{}))!=set(files):raise ValueError('backup targets differ from kit')
    if rec.get('applied_files')!={rel:f['sha256'] for rel,f in files.items()}:raise ValueError('backup applied pins differ from kit')
    for rel,f in files.items():
        old=safe(backup,rel)
        if not old.is_file() or sha(old) not in f['accepted_base_sha256'] or sha(old)!=rec['backup_files'][rel]:raise ValueError('backup bytes outside accepted base: '+rel)
    if rec.get('resource_path')!=meta['resource']['destination'] or rec.get('resource_absent') is not True:raise ValueError('backup resource scope differs from kit')
    expected=json.loads((kit/meta['resource']['manifest']).read_text())
    expected['GOR-CLOSURE.json']=sha(kit/meta['resource']['manifest'])
    if rec.get('applied_resource')!=expected:raise ValueError('backup resource pins differ from kit')

def apply(root,kit,build=False):
    meta=json.loads((kit/'HASHES-DRAFT.json').read_text())
    # Final packaging must rename/hash-lock metadata and helper before delivery.
    if meta['status']!='INTEGRATION_DRAFT_NATIVE_UNTESTED_HELPER_PENDING':raise ValueError('unexpected draft status')
    closure=json.loads((kit/meta['resource']['manifest']).read_text())
    resrel=meta['resource']['destination'];res=safe(root,resrel)
    base=meta['baseline'];files={f['path']:f for f in meta['files']}
    def verify():
        if (root/'.gor-build.lock').exists():raise ValueError('active/interrupted build lock')
        swift=safe(root,'Sources/gor');expected={pathlib.PurePosixPath(x).name for x in base if x.startswith('Sources/gor/')}
        actual={p.relative_to(swift).as_posix() for p in swift.rglob('*.swift')}
        if actual!=expected:raise ValueError('unknown/missing Swift files')
        for rel,digest in base.items():
            if rel=='Sources/gor/BuildID.swift':continue # Generated, not a fixed input.
            p=safe(root,rel);allowed=files[rel]['accepted_base_sha256'] if rel in files else [digest]
            if not p.is_file() or sha(p) not in allowed:raise ValueError('wrong source base: '+rel)
        for rel,digest in meta['resource_guard'].items():
            p=safe(root,rel)
            if not p.is_file() or sha(p)!=digest:raise ValueError('resource guard mismatch: '+rel)
        for rel,f in files.items():
            p=safe(root,rel)
            if not p.is_file() or sha(p) not in f['accepted_base_sha256']:raise ValueError('unknown target: '+rel)
            if sha(kit/f['name'])!=f['sha256']:raise ValueError('kit payload mismatch: '+f['name'])
        if res.exists():raise ValueError('resource destination already exists; explicit reconciliation required')
    verify()
    archive=kit/meta['resource']['archive']
    if archive.stat().st_size!=meta['resource']['size'] or sha(archive)!=meta['resource']['sha256']:raise ValueError('wrong official resource archive')
    from materialize_verified_zip import materialize_verified_zip
    with tempfile.TemporaryDirectory(prefix='.gor-kit-stage-',dir=root) as temp:
        staged=pathlib.Path(temp)/'resource'
        materialize_verified_zip(archive,staged,meta['resource']['sha256'],closure)
        if inventory(staged)!=closure:raise ValueError('materialized resource closure differs')
        shutil.copy2(kit/meta['resource']['manifest'],staged/'GOR-CLOSURE.json')
        applied_resource=inventory(staged)
        backroot=safe(root.parent,'gor-bbu');backroot.mkdir(exist_ok=True)
        backup=backroot/(datetime.datetime.now().strftime('%y%m%d-%H%M%S-%f-')+'gor-r14-p3v5');backup.mkdir()
        for rel in files:
            dst=backup/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(safe(root,rel),dst)
        rec={'root':str(root),'resource_path':resrel,'resource_absent':True,'backup_files':{rel:sha(backup/rel) for rel in files},'applied_files':{rel:f['sha256'] for rel,f in files.items()},'applied_resource':applied_resource}
        (backup/'BACKUP.json').write_text(json.dumps(rec,indent=2,sort_keys=True)+'\n')
        verify()
        try:
            for rel,f in files.items():replace_file(kit/f['name'],safe(root,rel))
            res.parent.mkdir(parents=True,exist_ok=True);os.replace(staged,res)
            if inventory(res)!=applied_resource:raise ValueError('post-apply resource mismatch')
            if any(sha(safe(root,rel))!=f['sha256'] for rel,f in files.items()):raise ValueError('post-apply source mismatch')
        except BaseException as exc:
            # No later user work can have occurred in this synchronous transaction.
            # Roll back every file independently: one failed restore must not
            # abandon the rest, and any unrestored path is named in the error.
            unrestored=[]
            for rel in files:
                try: replace_file(backup/rel,safe(root,rel))
                except BaseException as e: unrestored.append(rel+': '+repr(e))
            try:
                if res.exists():shutil.rmtree(res)
            except BaseException as e: unrestored.append(resrel+': '+repr(e))
            if unrestored: raise RuntimeError('rollback incomplete; restore manually from '+str(backup)+' for: '+'; '.join(unrestored)) from exc
            raise
        print('Applied verified full files and whole resource closure. Backup:',backup,flush=True)
    if build:
        result=subprocess.run(['bash','build.sh'],cwd=root)
        if result.returncode:print('Build failed. Backup retained. No install success claimed.',flush=True)
        return result.returncode
    return 0

def main():
    p=argparse.ArgumentParser();p.add_argument('--root',type=pathlib.Path,required=True);p.add_argument('--kit',type=pathlib.Path,default=pathlib.Path(__file__).parent);p.add_argument('--restore',type=pathlib.Path);p.add_argument('--build',action='store_true');a=p.parse_args()
    root=a.root.absolute()
    if root.is_symlink() or root.resolve()!=root or not root.is_dir():raise ValueError('root must be an actual nonsymlink directory')
    lock=root/'.gor-kit.lock';lock.mkdir()
    try:
        if a.restore:
            backup=a.restore.absolute()
            if backup.is_symlink() or backup.resolve()!=backup:raise ValueError('symlink backup path')
            verify_backup_authority(root,backup,a.kit.resolve());restore(root,backup);return 0
        return apply(root,a.kit.resolve(),a.build)
    finally:lock.rmdir()
if __name__=='__main__':raise SystemExit(main())

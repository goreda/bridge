#!/usr/bin/env python3
"""Exercise the real provider gate against the delivered inputs and isolated faults."""
from pathlib import Path
import contextlib
import importlib.util
import io
import shutil
import tempfile

root=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('provider_architecture',root/'tools/architecture.py')
a=importlib.util.module_from_spec(spec)
spec.loader.exec_module(a)

def check(path):
    with contextlib.redirect_stdout(io.StringIO()):
        return a.provider_errors(path)

errors=check(root)
assert not errors,errors
print('PASS current product manifests, lock bytes and vendored revision accepted by real provider_errors')
data=(root/'ffmpeg-provider.lock').read_bytes()
marker=b'gorav_lock_source: '
prefix,source=data.rsplit(marker,1)
revision,blob=source.rstrip().split(b' ')
repo,revision=revision.split(b'@')
revision,filename=revision.split(b':')
assert revision==b'cf3e3f1772033dbc8465b19689e93f53c60006ce'
assert blob==b'52a2b9390b35121cb60618f3963fceca64bd1b62'
with tempfile.TemporaryDirectory() as tmp:
    p=Path(tmp)
    for relative in ['Package.swift','Packages/GorKit/Package.swift','Packages/gorav/source-lock.json']:
        original=root/relative
        if original.exists():
            target=p/relative
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(original,target)
    lock=p/'ffmpeg-provider.lock'
    lock.write_bytes(data)
    assert not check(p)
    cases=[
        ('wrong revision',prefix+marker+source.replace(revision,b'0'*40), 'revision differs'),
        ('wrong blob',prefix+marker+source.replace(blob,b'0'*40),'blob mismatch'),
        ('edited lock recipe',prefix.replace(b'--prefix',b'--wrong-prefix',1)+marker+source,'blob mismatch'),
    ]
    for label,mutated,expected in cases:
        assert mutated!=data,label
        lock.write_bytes(mutated)
        errors=check(p)
        assert any(expected in error for error in errors),(label,errors)
        print('RED expected:',label,errors)
    lock.write_bytes(data)
    assert not check(p)
print('PASS 3 negative controls; no native/provider rebuild or performance claim')

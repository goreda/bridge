#!/usr/bin/env python3
"""Fail-closed receipt regression; no native/hardware acceptance inferred."""
import importlib.util,json
from pathlib import Path
s=importlib.util.spec_from_file_location('native_c',Path(__file__).with_name('run-c.py'))
m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
rows=[json.dumps({'stage':'C','check':c,'status':'PASS'}) for c in sorted(m.REQUIRED)]
text='\n'.join(rows)
assert m.assess(0,text)['checks_green']
assert m.assess(0,text)['status']=='PARTIAL'
assert not m.assess(1,text)['checks_green']
assert not m.assess(0,text,True)['checks_green']
for i in range(len(rows)):
 assert not m.assess(0,'\n'.join(rows[:i]+rows[i+1:]))['checks_green']
assert not m.assess(0,text+'\n'+json.dumps({'stage':'C','check':'extra','status':'FAIL'}))['checks_green']
assert not m.assess(0,'Build complete!')['checks_green']
root=Path(__file__).resolve().parents[2]
h=(root/'Sources/gor/Engine/GorAVPlayerHost.swift').read_text()
assert 'func gatePauseAction() async { togglePause(); await gateControlTask?.value }' in h
assert 'seekValue.stringValue = String(seconds); seek(); await gateControlTask?.value' in h
assert 'func gateCloseAction() async { closeSession(); await gateCloseTask?.value }' in h
# native111: the toggle route gained a typed trace (request + observed
# states); the contract below still pins the real session route, the task
# wrapping and the failure funnel.
assert 'togglePause requested' in h
assert 'let before = await session.lifecycleState' in h
assert 'gateControlTask = Task {' in h
assert 'try await session.togglePause()' in h
assert '} catch { fail(error) }' in h
assert 'gateControlTask = Task { do { try await session.seek(toSeconds: value)' in h
assert 'gateCloseTask = Task { gateCloseReport = await previous.close() }' in h
print('PASS exact check set, missing-each-check mutants, timeout/failure/exit/uninstrumented refusal, PARTIAL scope, shared real host control route')

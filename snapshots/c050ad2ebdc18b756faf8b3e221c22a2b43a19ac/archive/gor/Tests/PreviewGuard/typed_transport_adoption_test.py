#!/usr/bin/env python3
"""Optional historical proof. ADOPTION_REF must identify the actual adoption commit, not current tip."""
from pathlib import Path
import os,subprocess
ROOT=Path(__file__).resolve().parents[2]
base='839e236efdffb95ca6c458b1d7d9ae7f9e08f471'
ref=os.environ.get('ADOPTION_REF')
if not ref:raise SystemExit('NOT_RUN historical adoption: set actual ADOPTION_REF')
path='archive/gor/Sources/gor/GorSources/FileBrowser.swift'
def read(r):return subprocess.check_output(['git','-C',str(ROOT),'show',r+':'+path]).decode()
original='{ _ = IPCClient.socketRoundtrip(path: path, payload: "{\\"command\\":[\\"quit\\"]}\\n", timeout: 0.25, sendOnly: true) }'
replacement='{ HoverPreviewTransport.quit(socketPath: path) }'
before=read(base);after=read(ref)
assert before.count(original)==1
assert after==before.replace(original,replacement)
print('PASS historical adoption exact one substitution; this is not a current-host freeze')

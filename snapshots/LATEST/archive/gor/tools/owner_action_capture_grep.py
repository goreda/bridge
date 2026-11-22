#!/usr/bin/env python3
"""Bounded exact routing diagnostics for the update capture. Does not infer missing actions."""
import sys
from pathlib import Path
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from session_log_paths import resolve
PATTERNS=('3D-TRANSITION ','3D-VERIFIED ','3D-CLOSE ','vrOpenRoute ','vrProbeResult ','3D-FILE-RESET ','3D-DROPPED ','3D-LUA-FAIL ','flat store kind crossed native engine','3D-REJECTED ','3D-LUA ','3D-APPLIED ','3D-DECISION path=store_applier','3D-DECISION lua_enable requested=','vr180-look: shader variant','3D-DECISION path=store_applier_reject')
def collect(paths,limit=262144,max_lines=80):
    result=['BEGIN 191o routing diagnostic grep']
    for path in paths:
        path=resolve(path)
        result.append('LOG '+path.name)
        try:
            with path.open('rb') as file:
                file.seek(0,2);file.seek(max(0,file.tell()-limit));text=file.read(limit).decode('utf-8','replace')
        except OSError:
            result.append('NOT_RUN log_unavailable');continue
        for pattern in PATTERNS:
            matches=[line for line in text.splitlines() if pattern in line]
            result.extend(matches[-max_lines:] if matches else ['NO_MATCH '+pattern])
    result.append('END 191o routing diagnostic grep')
    return '\n'.join(result)+'\n'
if __name__=='__main__':
    print(collect(sys.argv[1:] or ['/tmp/gor_diag.log','/tmp/gor_direct.log']),end='')

```packet-json
{
  "code_owner": "gdb gor-structure consuming test owner",
  "product_repo": "goreda/instinct",
  "product_sha": "408752f7427425c5c55c0fc55cdf6f27f06c8c40",
  "touched_files": [
    {
      "path": "archive/gor/Tests/Architecture/viewport_s4a_preservation_test.py",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "verify(base: str, post: str, new: str) -> None; AssertionError on byte drift",
    "types": "UTF-8 source strings; fixed move sentinels; SHA-256 hex body digest",
    "ownership_lifetime": "Fixture strings are immutable copies owned by the test process; no threads or network; process lifetime only",
    "caller": "viewport_s4a_preservation_test.py relocation test entry point; portable fixture driver supplied below",
    "callee": "Exact source splice, residual equality and hashlib.sha256 body check"
  },
  "test": {
    "command": "python3 portable_move.py",
    "expected": "CAUGHT body mutation; CAUGHT residual mutation; CAUGHT lost newline; PASS portable byte-preservation fixture and 3 negative controls; exit 0",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "lane/gdb-native87-full-app-gate",
    "paths": [
      "archive/gor/Tests/Architecture/viewport_s4a_preservation_test.py"
    ],
    "return_form": "patch"
  }
}
```

# W-gdb-gor-1: portable move-verification exercise, r3

## Task
Improve a byte-preservation checker for a geometry/crop source relocation.
No private repository, account, network, or local worktree is required.
All input bytes appear in the executable Python block below.

## Source pin and sanitization
Source pin: `8f025463a48f3e01b0fff950fb70fe5a847751a7`.
The fixture contains exact `GorFitSize` / `GorFitRect` declarations from
`archive/gor/Sources/gor/GorFit.swift`, and exact `currentMainPlayback` /
`isMainPlaybackCurrent` methods from `PPController.swift` at that pin.
Unrelated source, personal context, comments and paths have been omitted.
Sentinel comments and surrounding fixture layout are synthetic. These are
text fixtures, not a standalone compilable Swift application. No private
source fetch is needed or permitted by the exercise.

This portable test proves the checker against included sanitized excerpts.
It does not verify the full product move. Earlier full-worktree hashes and
PASS statements were producer claims, not independently verified by the
recipient from packet bytes. Full-product compilation and integration
remain separate acceptance work.

## Interface and passing tests
Save the code block as `portable_move.py`; run `python3 portable_move.py`.
Expected: CAUGHT body mutation; CAUGHT residual mutation; CAUGHT lost newline;
PASS portable byte-preservation fixture and 3 negative controls. Exit 0.
Reject any changed body byte or changed residual, including whitespace.
Do not normalize newlines, trim text or replace byte checks with semantics.

## Target branch and return
Target: `lane/gdb-native87-full-app-gate`, path
`archive/gor/Tests/Architecture/viewport_s4a_preservation_test.py`. No push is requested. Return a unified patch against the complete
Python file below, or its full replacement plus stdout and interpreter
version. Do not change product files, private refs, baseline allowances or
application behavior. Explain any additional negative controls.

## Complete runnable fixture and checker

```python id=fixtures1
import hashlib
BASE = '// sanitized base fixture\nstruct GorFitSize: Equatable {\n    var w: Double\n    var h: Double\n}\n\nstruct GorFitRect: Equatable {\n    var x: Double\n    var y: Double\n    var w: Double\n    var h: Double\n}\n\n// BEGIN MOVE\n    func currentMainPlayback() -> Int? {\n        mainPlaybackCondition.lock(); defer { mainPlaybackCondition.unlock() }\n        return mainPlaybackActive ? mainPlaybackGeneration : nil\n    }\n    func isMainPlaybackCurrent(_ generation: Int) -> Bool {\n        mainPlaybackCondition.lock(); defer { mainPlaybackCondition.unlock() }\n        return mainPlaybackActive && mainPlaybackGeneration == generation\n    }\n// END MOVE\n// residual sentinel\n'
POST = '// sanitized base fixture\nstruct GorFitSize: Equatable {\n    var w: Double\n    var h: Double\n}\n\nstruct GorFitRect: Equatable {\n    var x: Double\n    var y: Double\n    var w: Double\n    var h: Double\n}\n\n// residual sentinel\n'
MOVED = '    func currentMainPlayback() -> Int? {\n        mainPlaybackCondition.lock(); defer { mainPlaybackCondition.unlock() }\n        return mainPlaybackActive ? mainPlaybackGeneration : nil\n    }\n    func isMainPlaybackCurrent(_ generation: Int) -> Bool {\n        mainPlaybackCondition.lock(); defer { mainPlaybackCondition.unlock() }\n        return mainPlaybackActive && mainPlaybackGeneration == generation\n    }\n'
PREFIX = "// relocated excerpt\n"
NEW = PREFIX + MOVED

def verify(base, post, new):
    start = base.index("// BEGIN MOVE\n")
    body_start = start + len("// BEGIN MOVE\n")
    end = base.index("// END MOVE\n", body_start)
    body = base[body_start:end]
    assert post == base[:start] + base[end + len("// END MOVE\n"):], "residual"
    assert new == PREFIX + body, "moved bytes"
    assert hashlib.sha256(body.encode()).hexdigest() == '5376f09eb96c2b52afc503647436cfe1fafd754be8809ef27b17902afc100dc2', "body hash"
verify(BASE, POST, NEW)
for name, b, p, n in [
    ("body mutation", BASE, POST, NEW.replace("mainPlaybackActive", "wrong", 1)),
    ("residual mutation", BASE, POST + "x", NEW),
    ("lost newline", BASE, POST, NEW.rstrip()),
]:
    try: verify(b,p,n)
    except AssertionError: print("CAUGHT",name)
    else: raise RuntimeError("uncaught mutant: " + name)
print("PASS portable byte-preservation fixture and 3 negative controls")
```

## Actual consuming checker at product pin

```python id=source1
#!/usr/bin/env python3
"""S4a strict placement evidence. Product bytes, not equivalent rewritten logic."""
from pathlib import Path
import json,subprocess,hashlib
r=Path(__file__).resolve().parents[2];spec=json.loads((r/'Tests/Architecture/viewport-s4a-map.json').read_text());s=r/'Sources/gor'
for m in spec['moves']:
 old=subprocess.check_output(['git','-C',str(r),'show',spec['base']+':archive/gor/Sources/gor/'+m['old']],text=True)
 new=(s/m['new']).read_text()
 if 'start' in m:
  a=old.index(m['start']);b=old.index(m['end'],a);body=old[a:b]
  assert new==m['prefix']+body,m['new']
  current=(s/m['old']).read_text()
  ra=old.index(m['residual_start']);rb=old.index(m['residual_end'],ra)
  assert current==old[:ra]+old[rb:],m['old']
 else:
  body=old;assert new==old,m['new'];assert not (s/m['old']).exists()
 assert hashlib.sha256(body.encode()).hexdigest()==m['sha256']
print('PASS S4a exact source bytes preserved, old residual byte-identical')
```

Return a patch for the consuming checker above plus the portable test file. The portable fixture is the single test command, not a claim of product acceptance. The checker at the product pin still uses git for its full-product integration mode; do not execute that mode in the lab. Retain the existing strict integration assertions and add a supplied-fixture mode.

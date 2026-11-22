#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# ///
"""Rendered-shot route ordering regression.

The player's plan lock must be sent before loadfile, and the store's generated
source must be published only after loadfile. Publishing the generated source
first applies the generated route to the still-loaded parent film.
"""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import os
from pathlib import Path

root = Path(__file__).resolve().parents[2]
_override = os.environ.get("GOR_COORDINATOR_SOURCE")
if _override:
    source = Path(_override).read_text()
else:
    _b = (_threed_split().path(root)).read_text()
    source = _b[_b.index("// BEGIN relocated ThreeDRenderCoordinator.swift "):_b.index("// END relocated ThreeDRenderCoordinator.swift\n")]

fails = []


def fail(name: str, detail: str) -> None:
    fails.append(name)
    print(f"FAIL {name} {detail}")


def ok(name: str, detail: str) -> None:
    print(f"PASS {name} {detail}")


load = source.find('} else if let cmd = RenderedShotMPV.load')
if load < 0:
    fail("rendered-shot load block", "not found")
else:
    send = source.find("send(cmd); showing = hit.shot", load)
    generated = source.find("ThreeDStore.shared.dispatch(.generated", load)
    planned = source.find("RenderedShotMPV.plannedLook(plan:plan)", load)
    if send < 0 or generated < 0:
        fail("rendered-shot route markers", f"send={send} generated={generated}")
    else:
        if planned >= 0 and load < planned < send:
            ok("planned look data precedes loadfile", f"planned={planned} send={send}")
        else:
            fail("planned look data precedes loadfile", f"planned={planned} send={send}")
        if send < generated:
            ok("generated source follows loadfile", f"send={send} generated={generated}")
        else:
            fail("generated source follows loadfile", f"send={send} generated={generated}")
        before = source[load:send]
        if "send(message)" in before:
            fail("single writer has no direct look send", "generated dispatch precedes send(cmd)")
        else:
            ok("single writer has no direct look send", "no generated dispatch before send(cmd)")

if 'candidateURL:candidate' not in source:
    fail("same-shot replacement identity", "candidate URL not checked")
else:
    ok("same-shot replacement identity", "URL-aware reload in addition to shot and seek")
print(f"rendered-shot order: {len(fails)} failure(s)")
raise SystemExit(1 if fails else 0)

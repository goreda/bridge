#!/usr/bin/env python3
"""Backend routes for the look script (owner 2026-11-09, E-G request 17:00): tools-active, orientation reset and the single 3D switch plan.
Linux model of Sources/gor/Stereo/LookToolsRoute.swift, with the message formats and the decision text read out of the Swift file, plus pins that the
controller reaches the player only through the one existing line (so no new player-socket baseline row is needed). Swift is not compiled here."""
import json, os, re, subprocess, sys
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
rd = lambda p: open(os.path.join(ROOT, p)).read()
sw, feat = rd("Sources/gor/Stereo/LookToolsRoute.swift"), open(_pp_split().path(ROOT, "PPController_Features.swift")).read()
bad = 0


def check(n, c):
    global bad
    print(("PASS " if c else "FAIL ") + n)
    bad += (not c)


FORBIDDEN = re.compile(r"\b(?:MPVCommand|ipcCommand|IPCClient|PersistentEventConnection)\b|mpv\.conf", re.I)


def tools_active(head, blink, loaded):
    return (head or blink) and loaded


def tools_json(active):
    return json.dumps({"command": ["script-message-to", "vr180_look", "vr180-look-tools-active", "true" if active else "false"]}, separators=(",", ":"))


ARGS = re.search(r'neutralOrientationArgs = \[(.*?)\]', sw).group(1).replace('"', '').replace(' ', '').split(",")


def reset_json():
    return json.dumps({"command": ["script-message-to", "vr180_look", "vr180-look-set-orientation"] + ARGS}, separators=(",", ":"))


def plan(kind):
    return {"vr180": "nativeVR180", "flat-sbs": "nativeSBS", "flat-tb": "nativeTB"}.get(kind, "convert2D")


# message formats: the Swift text must carry exactly these tokens
check("tools-active message names the look script and command", '"vr180_look\\",\\"vr180-look-tools-active\\"' in sw)
check("tools-active carries true/false", '\\(active ? "true" : "false")' in sw)
check("model json for true", tools_json(True) == '{"command":["script-message-to","vr180_look","vr180-look-tools-active","true"]}')
check("model json for false", tools_json(False) == '{"command":["script-message-to","vr180_look","vr180-look-tools-active","false"]}')
check("reset orientation args are 0,0,135,0,0,0,0,0", ARGS == ["0", "0", "135", "0", "0", "0", "0", "0"])
check("reset message is a vr180-look-set-orientation script message", "vr180-look-set-orientation" in sw and reset_json().count(",") == 10)
check("reset json valid and 8 args", len(json.loads(reset_json())["command"]) == 3 + 8)

# the decision: (head tracking or blink log) and a loaded film; VR/3D state is not an input
rows = [(False, False, False, False), (True, False, True, True), (False, True, True, True), (True, True, False, False), (False, False, True, False), (True, False, False, False)]
for h, b, l, want in rows:
    check("toolsActive head=%s blink=%s loaded=%s -> %s" % (h, b, l, want), tools_active(h, b, l) == want)
check("Swift decision is that expression", "(headTracking || blinkLog) && loadedVideo" in sw)
check("tools-active has no aspect/keepaspect/stereo/projection words", not re.search(r"keepaspect|aspect|stereo|projection", sw.split("enum SingleSwitchRoute")[0].split("static func toolsActive(")[1].split("neutralOrientationArgs")[0], re.I))
check("refreshToolsActive passes no VR or 3D state", "vrModeEnabled" not in sw.split("func refreshToolsActive")[1].split("}")[0])

# Legacy route is a compatibility dispatch only. Production reducer is compiled by Tests/ThreeDState/run.py.
check("single switch dispatches toggle, never writes legacy prefs", "ThreeDStore.shared.dispatch(.toggle3D)" in sw and "SourceFormatChoice.setOutput" not in sw)
check("facade has no defaults writes", ".set(" not in sw.split("enum LookToolsRoute")[0])
check("no old callback or polling reconciliation", all(x not in sw+feat for x in ["onSingleSwitchResolved", "onSourceResolved", "reconcileSingleSwitch"]))
check("one raw sender records then sends", len(re.findall(r"func sendRaw",feat))==1 and "recordAppliedCommand(json)" in feat and "ipcCommand(json)" in feat)
check("applier is guarded by original film identity", "let identityReady = !recognitionIdentity.isEmpty && state.currentFilm == recognitionFilm" in feat)
check("applier handles exact Off", "if requestedPlan.output == .off && !identityReady" in feat)
check("detection dispatches evidence to store", "store.dispatch(.open(" in feat)
check("resetTestVRProperty exists in compatibility adapter", "func resetTestVRProperty()" in sw)
check("PPController_Features ceiling",len(feat.splitlines())<=2307)
sys.exit(1 if bad else 0)

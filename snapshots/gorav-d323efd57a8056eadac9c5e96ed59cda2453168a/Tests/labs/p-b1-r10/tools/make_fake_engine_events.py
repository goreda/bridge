#!/usr/bin/env python3
"""Deterministic generator for Tests/MediaFacadeKitTests/Fixtures/fake-engine-events.json.

Regenerate with:  python3 tools/make_fake_engine_events.py > Tests/MediaFacadeKitTests/Fixtures/fake-engine-events.json

The "generated" field is a fixed fixture label (the fa31ade contract publication
instant), not a claim about when the suite last ran; the run record lives in
TEST-RUN.txt. Output is byte-stable: fixed content, fixed key order, no clocks.
"""
import json

def v(t, val=None):
    d = {"type": t}
    if t != "none":
        d["value"] = val
    return d

def step(step, action, expect, name=None, property=None, arguments=None, value=None,
         seedProperty=None, token=None):
    d = {"step": step, "action": action}
    if name is not None: d["name"] = name
    if property is not None: d["property"] = property
    if arguments is not None: d["arguments"] = arguments
    if value is not None: d["value"] = value
    if seedProperty is not None: d["seedProperty"] = seedProperty
    if token is not None: d["token"] = token
    d["expect"] = expect
    return d

def ret(val): return {"returns": val}
def throws(msg): return {"throws": msg}
def notified(n): return {"callbackCount": n}

TRACKS_1 = v("list", [v("object", {"id": v("number", 1), "kind": v("text", "audio")})])
TRACKS_2 = v("list", [v("object", {"id": v("number", 2), "kind": v("text", "sub")})])

fixture = {
    "name": "fake-engine-events",
    "generated": "2026-11-06T22:06:40Z",
    "purpose": ("P-B1-E2 (fa31ade): generated sequence covering the E2 vocabulary "
                "(cycle/add/frame-step/frame-back-step, time-pos set, volume get, vid "
                "set/mutate, aid/sid/vid gets, track-list observe/notify/unobserve) "
                "plus the original empty/load/playback/error legs, driven against "
                "FakeEngine through the facade with the merged 34-row table installed."),
    "sequence": [
        step("empty",    "get",     ret(v("none")), property="pause"),
        step("load",     "command", ret(v("none")), name="loadfile", arguments=[v("text", "a1-v24.mp4")]),
        step("playback", "set",     ret(v("none")), property="pause", value=v("bool", False)),
        step("playback", "get",     ret(v("number", 1.25)), property="time-pos", seedProperty=v("number", 1.25)),
        step("e2-cycle",       "command", ret(v("none")), name="cycle", arguments=[v("text", "pause")]),
        step("e2-add",         "command", ret(v("none")), name="add", arguments=[v("text", "speed"), v("number", 0.5)]),
        step("e2-frame-step",  "command", ret(v("none")), name="frame-step"),
        step("e2-frame-back",  "command", ret(v("none")), name="frame-back-step"),
        step("e2-time-pos-set","set",     ret(v("none")), property="time-pos", value=v("number", 12.5)),
        step("e2-volume-get",  "get",     ret(v("number", 80)), property="volume", seedProperty=v("number", 80)),
        step("e2-vid-set",     "set",     ret(v("none")), property="vid", value=v("text", "auto")),
        step("e2-vid-mutate",  "set",     ret(v("none")), property="vid", value=v("number", 2)),
        step("e2-aid-get",     "get",     ret(v("number", 1)), property="aid", seedProperty=v("number", 1)),
        step("e2-sid-get",     "get",     ret(v("text", "no")), property="sid", seedProperty=v("text", "no")),
        step("e2-vid-get",     "get",     ret(v("number", 2)), property="vid"),
        step("e2-track-list-observe",   "observe",   ret(v("none")), property="track-list", token=900),
        step("e2-track-list-notify",    "notify",    notified(1), property="track-list", value=TRACKS_1),
        step("e2-track-list-unobserve", "unobserve", ret(v("none")), token=900),
        step("e2-track-list-notify-after-remove", "notify", notified(0), property="track-list", value=TRACKS_2),
        step("error", "command", throws("engineFailure: simulated seek failure"), name="seek", arguments=[v("number", 10.0)]),
    ],
}

print(json.dumps(fixture, indent=2))

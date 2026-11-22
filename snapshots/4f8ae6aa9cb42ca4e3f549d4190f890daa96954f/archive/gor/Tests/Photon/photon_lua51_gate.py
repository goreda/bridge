#!/usr/bin/env python3
"""Photon Lua 5.1 load gate.

Compiles every *.lua under Resources/vendor/mpv/scripts with a real
Lua 5.1 compiler (lupa.lua51). A syntax error or the 200 top-level-local
limit ("too many local variables") fails the script load, so it fails here.
Needs: pip install lupa. Run: python3 Tests/Photon/photon_lua51_gate.py
"""
import pathlib, sys
from lupa import lua51

root = pathlib.Path(__file__).resolve().parents[2] / "Resources/vendor/mpv/scripts"
files = sorted(root.glob("*.lua"))
lua = lua51.LuaRuntime()
load = lua.eval("loadstring")
bad = 0
for f in files:
    res = load(f.read_text(encoding="utf-8"), "@" + f.name)
    fn, err = (res if isinstance(res, tuple) else (res, None))
    if fn is None:
        bad += 1
        print("FAIL", f.name, err)
    else:
        print("ok  ", f.name)
    if f.name == "photon.lua" and fn is not None:
        # Keep four top-level slots spare, not merely a just-loadable script.
        # Lua's compiler is the source of truth for active locals and scopes.
        reserve = "local headroom_a,headroom_b,headroom_c,headroom_d\n"
        spare = load(reserve + f.read_text(encoding="utf-8"), "@photon-headroom")
        spare_fn, spare_error = spare if isinstance(spare, tuple) else (spare, None)
        if spare_fn is None:
            bad += 1
            print("FAIL photon.lua lacks four-local headroom:", spare_error)
        else:
            print("ok   photon.lua retains at least four top-level local slots")
# Lua 5.3+ library calls compile fine on 5.1 but fail at run time (mpv 0.41 here runs LuaJIT/5.1).
import re
api = re.compile(r"\b(utf8\.|table\.move\(|math\.type\(|math\.tointeger\(|string\.pack\(|string\.unpack\(|math\.ult\()")
for f in files:
    for i, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
        code = line.split("--")[0]
        m = api.search(code)
        if m:
            bad += 1
            print("FAIL", f.name, i, "Lua 5.3+ API:", m.group(1))
sys.exit(1 if bad else 0)

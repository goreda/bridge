#!/usr/bin/env python3
"""Source-wiring checks for the overlay Space gate (static, Linux; the real behaviour needs macOS).
Guards the decisions the model test cannot see: the overlay never joins all Spaces, is moved only on order-front,
only while visible (alpha > 0), the gate is skipped during the minimize hold, and a Space change re-checks at once
and three more times."""

# Platform source acquisition only; exact original units via the shared MARK resolver.
import importlib.util as _plat_iu
from pathlib import Path as _PlatPath
_plat_root=next(p for p in _PlatPath(__file__).resolve().parents if (p/'Tests/Structure/platform_source.py').is_file())
_plat_spec=_plat_iu.spec_from_file_location('platform_source_view',_plat_root/'Tests/Structure/platform_source.py')
_plat_view=_plat_iu.module_from_spec(_plat_spec);_plat_spec.loader.exec_module(_plat_view)
_plat_read=_plat_view.read_source
_plat_bytes=_plat_view.read_bytes
_plat_compile_input=_plat_view.compile_input
import pathlib, re, sys
R = pathlib.Path(__file__).resolve().parents[2] / "Sources/gor"
G = _plat_read(R / "OverlaySpaceGate.swift"); A = _plat_read(R / "AppDelegate.swift")
fails = []
def check(n, ok):
    print(("ok   " if ok else "FAIL ") + n)
    if not ok: fails.append(n)
code = lambda t: chr(10).join(l for l in t.splitlines() if not l.lstrip().startswith("//"))
check("overlay never gets canJoinAllSpaces (code, comments aside)", "canJoinAllSpaces" not in code(G) and "canJoinAllSpaces" not in code(A))
check("overlay base behaviour is ignoresCycle + fullScreenAuxiliary", "win.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary]" in A)
check("moveToActiveSpace is inserted then removed around one order-front", re.search(r"insert\(\.moveToActiveSpace\).*?orderFrontRegardless\(\).*?remove\(\.moveToActiveSpace\)", G, re.S) is not None)
check("move requires a visible overlay (alpha > 0)", "win.alphaValue > 0 && needsMove" in G)
check("move is rate limited to 0.5 s", "moveInterval: TimeInterval = 0.5" in G and "now - lastMove >= Self.moveInterval" in G)
check("hide needs 3 consecutive off-screen samples", "hideAfterMisses = 3" in G)
check("Space change re-checks now and at 0.1/0.25/0.5 s", "for d in [0.1, 0.25, 0.5]" in G and "handler()" in G)
check("gate is skipped during the minimize hold", re.search(r"systemUptime >= overlayMinimizeHoldUntil \{[^}]*overlaySpace\.apply", A) is not None)
check("Space observer is registered with the activation observers", "OverlaySpaceGate.observeSpaceChange" in A)
check("state changes are logged to the [spaces] diag", '"[spaces]' in G or "[spaces]" in G)
check("audit notes no longer claim the overlay joins all Spaces", "overlay joins all Spaces" not in G)
print("PASS" if not fails else "FAIL"); sys.exit(1 if fails else 0)

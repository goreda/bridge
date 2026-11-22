#!/usr/bin/env python3
"""ThreeDPreflight text pins + a Python model of the decision (Swift uncompiled, nothing run on a Mac)."""
import pathlib, re, sys
root = pathlib.Path(__file__).resolve().parents[2]; S = root / 'Sources/gor'
pf = (S / 'ThreeDPreflight.swift').read_text(); menu = (S / 'ThreeDMenu.swift').read_text(); wi = (S / 'ThreeDWiring.swift').read_text()
bad = 0
def check(n, c):
    global bad; print(('PASS ' if c else 'FAIL ') + n); bad += (not c)
def decide(enc, dec, pl):
    if not enc: return 'enc'
    if not dec: return 'dec'
    if 'hevc' not in pl: return 'player'
    return None
check('model: decision order VT encode > VT decode > player HEVC > ok', decide(False, True, ['hevc']) == 'enc' and decide(True, False, ['hevc']) == 'dec' and decide(True, True, ['h264']) == 'player' and decide(True, True, ['hevc', 'h264']) is None)
check('VideoToolbox probes: encoder list has HEVC, hardware HEVC decode', 'VTCopyVideoEncoderList' in pf and 'kCMVideoCodecType_HEVC' in pf and 'VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)' in pf)
check('no ffmpeg / libx265 / install / network in the preflight code', not re.search(r'ffmpeg|libx265|URLSession|curl|brew (install|update)', re.sub(r'///.*', '', pf)))
check('player decoder probe is the existing --vd=help one', 'RenderedShotMPV.probeDecoders(executable:' in pf)
check('probe runs once off the main thread', 'started' in pf and 'DispatchQueue.global(qos: .utility)' in pf)
check('reasons are plain and say staying 2d', pf.count('staying 2d') == 3)
check('menu disables sbs/vr180 with the reason, off stays selectable', 'ThreeDPreflight.shared.reason' in menu and menu.index('3d off') < menu.index('ThreeDPreflight.shared.reason'))
check('wiring starts the probe with the player-path closure', 'ThreeDPreflight.shared.start(mpvExecutable:' in wi)
check('no player-socket words', all(not re.search(r'\b(MPVCommand|ipcCommand|IPCClient|PersistentEventConnection)\b|mpv\.conf', t, re.I) for t in (pf, menu, wi)))
check('unresolved player is waited for, never reported as no decoder', 'waited < 90' in pf and 'guard let player = exe else { return }' in pf)
check('empty decoder read is retried once', 'pl.isEmpty' in pf and pf.count('probeDecoders(executable: player)') == 2)
# Run the real Foundation subprocess probe against a fake player that lists decoders on stderr.
import subprocess, tempfile, os
mpv = (S / 'RenderedShotMPV.swift').read_text()
body = mpv[mpv.index('    static func probeDecoders'):mpv.index('    private static func line')]
with tempfile.TemporaryDirectory() as d:
    script = pathlib.Path(d) / 'player'
    script.write_text('#!/bin/sh\necho "hevc h264" >&2\n'); script.chmod(0o755)
    code = 'import Foundation\nenum Probe {\n' + body + '\n}\nlet found = Probe.probeDecoders(executable: URL(fileURLWithPath: CommandLine.arguments[1]))\nprint(found == ["hevc", "h264"] ? "DECODERS_OK" : "DECODERS_BAD")\n'
    src = pathlib.Path(d) / 'test.swift'; src.write_text(code)
    build = subprocess.run([os.environ.get('SWIFTC','swiftc'), str(src), '-o', d+'/test'], capture_output=True, text=True)
    result = subprocess.run([d+'/test', str(script)], capture_output=True, text=True).stdout if build.returncode == 0 else build.stderr
    check('real probe reads stderr and logs decoder result (compiled Foundation test)', 'DECODERS_OK' in result and 'gor3d-decoder-probe v1' in result)
sys.exit(1 if bad else 0)

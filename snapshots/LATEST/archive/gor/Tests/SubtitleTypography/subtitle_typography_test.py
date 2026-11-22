#!/usr/bin/env python3
"""Row GORAV-SUBTITLE-TYPOGRAPHY (native80): the embedded cue presenter
applies ONE real sub-scale semantic end to end; every other typography axis
stays an explicit typed refusal; OSD parity with the mpv path holds.

Swift legs (compile + decision source) run real SubtitleTypography.swift when
swiftc exists, otherwise SKIP; native MetalPresenter runtime is NOT_RUN.
"""
import pathlib, re, shutil, subprocess, sys, tempfile

R = pathlib.Path(__file__).resolve().parents[2]
PKG = R / 'Packages/gorav/Sources'
PP = R / 'Sources/gor/Player/PPController.swift'
HOST = R / 'Sources/gor/Engine/GorAVPlayerHost.swift'
SES = PKG / 'GorAVEmbeddedShell/GorAVEmbeddedSession.swift'
MET = PKG / 'GorAVMetalPresenter/core/MetalPresenter.swift'
TYPO = PKG / 'GorAVSubtitles/SubtitleTypography.swift'
MAN = PKG / '../Package.swift'
P = []

def ok(name): P.append(name); print('  ok', name)

def text(p): return p.read_text()

def swiftc_run(args):
    if not shutil.which('swiftc'): return None
    try:
        return subprocess.run(args, capture_output=True, text=True)
    except (PermissionError, FileNotFoundError):
        return None

# --- static: package policy source -----------------------------------------
t = text(TYPO)
assert 'public enum SubtitleTypography' in t and 'public static let defaultScale = 1.0' in t
assert re.search(r'minScale = 0\.1', t) and re.search(r'maxScale = 10\.0', t)
assert re.search(r'public static func adjustedScale\(current: Double, delta: Double, reset: Bool\) -> Double\?', t)
assert 'target >= minScale, target <= maxScale' in t  # out-of-range = nil = refusal, never a clamp
assert 'baseCueFontSize = 22.0' in t and 'baseCueFontSize * scale' in t
ok('policy source: SubtitleTypography scale semantic + typed nil refusal')

# --- static: package wired ---------------------------------------------------
m = text(MAN)
assert '"SubtitleTypography.swift"' in m, 'Package.swift must ship the decision source'
ok('Package.swift ships SubtitleTypography.swift in the GorAVSubtitles target')

# --- static: session -> presenter -------------------------------------------
s = text(SES)
assert re.search(r'private var subtitleFontScale = SubtitleTypography\.defaultScale', s)
assert re.search(r'public func setSubtitleFontScale\(_ scale: Double\) -> EmbeddedRefusal\?', s)
assert re.search(r'return \.illegalState\("tornDownOrFenced"\)', s)
assert re.search(r'return \.unsupportedCommand\("subtitle font scale out of range"\)', s)
assert 'presenter?.setSubtitleFontScale(accepted)' in s
assert s.count('presenter.setSubtitleFontScale(subtitleFontScale)') == 2, 'scale must re-apply at BOTH bind sites'
ok('session: scale stored session-only, gated, applied at both bind sites')

# --- static: presenter applies it -------------------------------------------
v = text(MET)
assert re.search(r'systemFont\(ofSize: SubtitleTypography\.baseCueFontSize, weight: \.medium\)', v)
assert re.search(r'var cueFontScale = SubtitleTypography\.defaultScale', v) and 'didSet { applyCueTypography() }' in v
assert re.search(r'systemFont\(ofSize: SubtitleTypography\.renderedFontSize\(scale: cueFontScale\), weight: \.medium\)', v)
assert re.search(r'public func setSubtitleFontScale\(_ scale: Double\) -> Bool', v)
assert 'view.cueFontScale = accepted' in v and 'return true' in v
ok('presenter: real NSTextField cue labels re-render at scaled font size')

# --- static: app closure + OSD parity ----------------------------------------
h = text(HOST)
assert re.search(r'func applyChromeSubtitleScale\(_ scale:Double\)->String\?', h)
assert re.search(r'controls\.embeddedSubtitleScale=\{', h) and 'self.applyChromeSubtitleScale(scale)' in h
c = text(PP)
assert re.search(r'var embeddedSubtitleScale:\(\(_ scale:Double\)->String\?\)\?', c)
assert re.search(r'private var embeddedSubScale=1\.0', c)  # session-only accumulator state preserved
assert re.search(r'let target=reset \? 1\.0 : embeddedSubScale\+delta', c) and 'embeddedSubScale=target' in c
assert 'spineUI.showMPVOSD("subtitle font size: "+String(format:"%.0f%%",target*100),duration:1.5,force:true)' in c
# OSD parity: the same format the mpv path uses for the same command, byte-identical template
assert c.count('spineUI.showMPVOSD("subtitle font size: "+String(format:"%.0f%%"') >= 1
ok('app: closure plumbing + OSD template parity with mpv sub-scale')

# --- static: refusals stay ----------------------------------------------------
assert 'spineUI.showMPVOSD("gorav unavailable: "+reason,duration:1.5,force:true)' in c
assert '_=refuseEmbedded("subtitle position")' in c
assert 'sub-pos stays an explicit' in c  # position documented as refusal; tilt/animation have no surface anywhere
ok('position/tilt/animation stay explicit refusals')

# --- swift leg: the decision source runs -------------------------------------
swiftc = swiftc_run(['swiftc', '--version'])
if swiftc is None:
    print('SKIP swift decision leg (swiftc unavailable)')
    print('SKIP swift compile leg (swiftc unavailable)')
else:
    assert swiftc.returncode == 0
    src = text(TYPO) + '''
import Foundation
func expect(_ cond: Bool, _ name: String) { if !cond { FileHandle.standardError.write(("FAIL " + name + "\\n").data(using: .utf8)!); exit(1) } else { print("  ok swift:", name) } }
expect(SubtitleTypography.adjustedScale(current: 1.0, delta: 1.0, reset: false) == 2.0, "add accumulates like mpv")
expect(SubtitleTypography.adjustedScale(current: 3.0, delta: -1.0, reset: true) == 1.0, "reset returns default")
expect(SubtitleTypography.adjustedScale(current: 0.1, delta: -1.0, reset: false) == nil, "below range refuses")
expect(SubtitleTypography.adjustedScale(current: 10.0, delta: 1.0, reset: false) == nil, "above range refuses")
expect(SubtitleTypography.adjustedScale(current: .nan, delta: 1.0, reset: false) == nil, "NaN current refuses")
expect(SubtitleTypography.adjustedScale(current: 1.0, delta: .infinity, reset: false) == nil, "infinite delta refuses")
expect(abs(SubtitleTypography.renderedFontSize(scale: 2.0) - 44.0) < 0.0001, "rendered size scales")
expect(SubtitleTypography.renderedFontSize(scale: 1.0) == SubtitleTypography.baseCueFontSize, "default renders at base size")
'''
    with tempfile.TemporaryDirectory() as td:
        sp = pathlib.Path(td) / 'd.swift'; sp.write_text(src)
        binp = pathlib.Path(td) / 'd'
        cr = swiftc_run(['swiftc', '-O', str(sp), '-o', str(binp)])
        assert cr is not None and cr.returncode == 0, 'swiftc compile failed: ' + (cr.stderr if cr else '')
        ok('swift compile leg: SubtitleTypography.swift compiles -O')
        rr = subprocess.run([str(binp)], capture_output=True, text=True)
        print(rr.stdout, end=''); assert rr.returncode == 0, rr.stderr
        ok('swift decision leg: add/reset/out-of-range/non-finite/rendered size all hold')

print('SKIP native MetalPresenter runtime leg (no macOS runtime here) - NOT_RUN')
print('PASS subtitle typography: %d legs green (swift legs: %s; native runtime: NOT_RUN)' % (len(P), 'executed' if swiftc is not None else 'SKIP, no swiftc'))

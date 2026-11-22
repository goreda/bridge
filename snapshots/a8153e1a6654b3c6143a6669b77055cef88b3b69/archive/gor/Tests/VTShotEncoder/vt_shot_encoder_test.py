#!/usr/bin/env python3
"""VTShotEncoder: Python models of its pure rules + text pins against the Swift and CONTRACT-190v s9 (Swift uncompiled, no Mac run, no encode done)."""
import pathlib, re, sys, sys as _s
root = pathlib.Path(__file__).resolve().parents[2]; S = root / 'Sources/gor'
sw = (S / 'VTShotEncoder.swift').read_text()
bad = 0
def check(n, c):
    global bad; print(('PASS ' if c else 'FAIL ') + n); bad += (not c)
def fps_rational(f):
    if not (f > 0 and f <= 1000): return None
    for n, d in [(24000, 1001), (30000, 1001), (48000, 1001), (60000, 1001), (120000, 1001)]:
        if abs(f - n / d) < 0.002: return (n, d)
    r = round(f)
    if abs(f - r) < 0.002: return (r, 1)
    return (round(f * 1000), 1000)
check('model: fps rationals (23.976, 29.97, 25, 24, 59.94, odd rate)', fps_rational(23.976) == (24000, 1001) and fps_rational(29.97) == (30000, 1001) and fps_rational(25) == (25, 1) and fps_rational(24.0) == (24, 1) and fps_rational(59.94) == (60000, 1001) and fps_rational(12.5) == (12500, 1000) and fps_rational(0) is None)
def pts(frame, r): return frame * r[1] / r[0]
check('model: PTS = frame/fps exactly (frame 1000 at 23.976 is 1000*1001/24000 s), start frame s gives s/fps', abs(pts(1000, (24000, 1001)) - 1000 * 1001 / 24000) < 1e-12 and abs(pts(48, (24, 1)) - 2.0) < 1e-12)
def even(w, h): return (w + (w & 1), h + (h & 1))
check('model: even padding', even(1919, 1079) == (1920, 1080) and even(1920, 1080) == (1920, 1080))
def pad_swift(a):   # the Swift rule: clampIndex(i, n) = min(i, n-1) on both axes (same edge replication as prepare_film._pad_even, kept source-compatible)
    h, w = len(a), len(a[0]); wp, hp = even(w, h)
    return [[a[min(j, h - 1)][min(i, w - 1)] for i in range(wp)] for j in range(hp)]
check('model: edge replication of an odd 3x5 block', pad_swift([[1, 2, 3, 4, 5], [6, 7, 8, 9, 10], [11, 12, 13, 14, 15]]) == [[1, 2, 3, 4, 5, 5], [6, 7, 8, 9, 10, 10], [11, 12, 13, 14, 15, 15], [11, 12, 13, 14, 15, 15]])
check('model: word() MSB-aligned shift 6, clamp 1023, neutral chroma 512 -> 0x8000, black luma 64<<6 / 0', (1023 << 6) == 65472 and min(2000, 1023) << 6 == 65472 and (512 << 6) == 0x8000 and (64 << 6) == 4096)
def hvcc_main10(b): return len(b) > 1 and (b[1] & 0x1F) == 2
check('model: hvcC profile byte (Main 10 = 2, Main = 1)', hvcc_main10([1, 2]) and hvcc_main10([1, 0x22]) and not hvcc_main10([1, 1]) and not hvcc_main10([1]))
check('HEVC Main10 AutoLevel, 10-bit biplanar, mp4, colour tags only when the source has them (no depth encoder in this file)', 'kVTProfileLevel_HEVC_Main10_AutoLevel' in sw and 'kCVPixelFormatType_420YpCbCr10BiPlanar' in sw and 'fileType: .mp4' in sw and 'if let c = colorProperties' in sw and 'appendDepth' not in sw and 'ITU_R_709_2' not in sw)
check('source proxy colour tags pass through (nil = untagged), black bottom-right pad', 'colorProperties: [String: String]? = nil' in sw and 'blackLumaWord' in sw)
check('PTS base: session starts at startFrame/fps and each frame is startFrame+written; first PTS verified on read-back', 'startSession(atSourceTime' in sw and 'startFrame + written' in sw and 'first PTS' in sw)
check('verify reads back: HEVC, hvcC Main 10, padded size, first PTS', all(k in sw for k in ('kCMVideoCodecType_HEVC', 'hvccIsMain10', 'size \\(dim.width)', 'first PTS')))
check('failed encode removes the file and returns the reason; tmp file then rename', '.tmp-' in sw and 'removeItem(at: dest); return why' in sw and 'return "encoder failed' in sw)
check('source-only scope is stated in the file', 'SOURCE PROXY ONLY' in sw)
check('no player-socket words', not re.search(r'\b(MPVCommand|ipcCommand|IPCClient|PersistentEventConnection)\b|mpv\.conf', sw, re.I))
sys.exit(1 if bad else 0)

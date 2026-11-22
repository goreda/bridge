#!/usr/bin/env python3
"""arch-196t r3 facade pins (owner paste 2026-11-15 17:36,
phonemsg-01M7FT6RXGN444933PHRAJEV9J; owner complaint 17:32,
phonemsg-01M7FT044J1ZNHNKNQ0EPV6F7M).

Owner contract:
1. Engine > gorav STAYS as an in-window facade switch: the choice persists
   (UserDefaults) and is shown in the HUD; the separate gorav window, its
   NSOpenPanel and its own buttons are deleted from the owner path.
2. NEVER REFUSE, ALWAYS VISIBLE: with gorav selected, every file is first
   offered to gorav; a refusal plays the same file on mpv in the same window
   at once, the HUD shows "gorav: <exact reason> -> mpv" and the reason is
   recorded in the diagnostics collection.
3. The per-file verdict is the engine's own DemuxerPolicy over an ffprobe
   stream inventory (mirroring FFmpegSoftwareDecoder's counting), never a
   filename or container sniff.
These source pins fail if the facade reverts to the probe surface or the
fallback loses its HUD/log line. Run: python3 Tests/GorAVFacade/run.py
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
app = (ROOT / 'Sources/gor/App/AppDelegate.swift').read_text()
offer = (ROOT / 'Sources/gor/Engine/GorAVLocalOffer.swift').read_text()

# 1. probe surface deleted from the owner path
assert 'openGorAVLocalFilm' not in app, 'probe launch path reappeared'
assert 'open local film with gorav' not in app, 'probe menu row reappeared'

# 2. facade switch: persists, HUD-confirmed, never launches a picker/window
sel = app[app.index('func menuPlayerEngine'):app.index('func launchMPV(file:')]
assert 'UserDefaults.standard.set(engine.rawValue, forKey: PlayerEngine.preferenceKey)' in sel
assert 'showMPVOSD("engine: \\(engine.rawValue)"' in sel, 'engine switch lost its HUD confirmation'
assert 'Task' not in sel and 'GorAVPlayerHost' not in sel, 'engine switch launches the harness'

# 3. owner-path per-file offer in launchMPV, dev gate preserved for native87
lm = app[app.index('func launchMPV(file:'):]
assert 'route.active == .gorav && ProcessInfo.processInfo.environment["GOR_ENGINE"] != "gorav"' in lm, \
    'owner-path per-file offer missing from launchMPV'
assert 'goravOfferLocalFile(file: file)' in lm

# 4. fallback: same-window mpv + HUD reason + diagnostics record, never a dialog
_fs = app.index('func goravFallbackToMPV')
fb = app[_fs:app.index('\n    }\n', _fs)]
assert 'showMPVOSD("gorav: \\(reason) -> mpv", force: true)' in fb, 'fallback HUD line lost'
assert 'Diag.mediaRecord("GORAV-FALLBACK' in fb, 'fallback diagnostics record lost'
assert 'NSAlert' not in fb, 'refusal dialog appeared (r3: never a refusal dialog)'
assert 'launchMPVImplementation(file: file)' in fb, 'fallback does not play on mpv'

# 5. stream route carries the same HUD/log contract
sw = app[app.index('func goravAdmitAndOpen'):]
assert sw.count('showMPVOSD("gorav:') >= 2, 'stream fallback/pending HUD lines missing'
assert 'GORAV-FALLBACK stream' in sw

# 6. the offer evaluates the engine's own DemuxerPolicy from probed facts
assert 'import GorAVNativeProbeKit' in offer
assert re.search(r'DemuxerPolicy\(\)\.evaluate\(containerName: f\.containerName,\s*videoCodecName: f\.videoCodec,\s*videoStreamCount: f\.videoStreams,\s*audioStreamCount: f\.audioStreams,\s*otherStreamCount: f\.otherStreams,\s*subtitleStreamCount: f\.subtitleStreams,\s*audioCodecName: f\.audioCodec\)', offer), \
    'offer no longer mirrors the engine DemuxerPolicy call'
assert '"-show_format", "-show_streams", "-of", "json"' in offer, 'ffprobe probe arguments drifted'
assert 'case .reject(let reason):\n            return .refused(reason)' in offer, 'engine refusal reason no longer passed through verbatim'

# 7. probe hard-bounded + off the main thread (A-D successor reading 2026-11-15):
#    a hung ffprobe is SIGKILLed, refuses with a reason and never wedges the open path
assert 'done.wait(timeout: .now() + timeoutSeconds)' in offer and 'kill(p.processIdentifier, SIGKILL)' in offer, \
    'probe lost its hard timeout'
assert 'ffprobe timed out' in offer, 'probe timeout has no fallback reason'
ofr = app[app.index('func goravOfferLocalFile'):app.index('func goravFallbackToMPV')]
assert 'DispatchQueue.global(qos: .userInitiated)' in ofr and 'DispatchQueue.main.async' in ofr, \
    'offer no longer runs off the main thread with a main-thread fallback hop'

print('PASS gorav facade: probe surface deleted, facade switch persists + HUD, per-file offer with')
print('  engine-verdict fallback (HUD "gorav: <reason> -> mpv" + diagnostics record), dev gate kept')

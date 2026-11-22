#!/usr/bin/env python3
"""E-G conditions (1)-(5) for render_shot files: Python model of RenderedShotPlan + text pins. Swift uncompiled; no mpv run."""
import pathlib, sys
root = pathlib.Path(__file__).resolve().parents[2]; S = root / 'Sources/gor'
sw = (S / 'RenderedShotPlan.swift').read_text(); lua = (root / 'Resources/vendor/mpv/scripts/vr180-look.lua').read_text()
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
def make(n, dec, swap=True):
    if n < 256 or n % 2: return None
    h = {d.lower() for d in dec}; sign = swap
    if 'hevc' in h: return (n, 'hevc', sign)
    if 'h264' in h and n * 2 <= 4096: return (n, 'h264', sign)
    return None
check('(1) square eyes, sbs is 2N wide', 'let eyeN: Int' in sw and 'var sbsWidth: Int { canvas.w }' in sw and '(eyeN * 2, eyeN)' in sw)
check('(4) HEVC when the player has it', make(2048, ['h264', 'HEVC'])[1] == 'hevc' and make(4096, ['hevc'])[1] == 'hevc')
check('(4) H.264 only without HEVC and <= 4096 wide, else refuse (never silent)', make(2048, ['h264'])[1] == 'h264' and make(2049 + 1, ['h264']) is None and make(2048, []) is None)
k = (S / 'Stereo3DKernel.swift').read_text(); wr = (S / 'RenderShotWriter.swift').read_text()
check('(2) default swap true = vr180-look vr_swap_eyes 1.0; plan carries the flag', make(1024, ['hevc'])[2] is True and make(1024, ['hevc'], False)[2] is False and 'local vr_swap_eyes = 1.0' in lua)
check('(2) positive ipd, swapEyes passed through to render (E-G 43fc8498)', 'abs(effective)' in sw and 'renderIPDSign' not in sw and 'swapEyes: plan.swapEyes' in wr and 'swapEyes: Bool = false' in k)
check('writer blits on the renderer queue, writes film-time PTS, no audio input', 'renderer.queue' in wr and 'appendOnly' not in wr and 'withPresentationTime: pts' in wr and 'mediaType: .audio' not in wr)
check('writer deletes the partial file on every failure path', 'removeItem(at: out)' in wr and 'throw fail(' in wr and wr.count('throw Failure.') <= 8)
check('(3) vr180 projection, crop 1,1, full source-eye crop; script message exists', 'projectionKind = "vr180"' in sw and 'menuCrop = (x: 1.0, y: 1.0)' in sw and 'sourceEyeCrop = (x: 0.0, y: 0.0, w: 1.0, h: 1.0)' in sw and 'vr180-look-source-eye-crop' in lua and '"flat-2d3d"' in lua)
check('(5) film-time PTS, audio stays on the source track', 'ptsIsFilmTime = true, carriesAudio = false' in sw)
check('file naming', 'render_shot_%05d.mp4' in sw)
# s36: flat output modes (canvas, projection, look setup)
check('(s36) flat canvas follows OutputMode, vr180 stays 2N x N', 'output.isFlat ? output.canvasSize(srcW: srcW, srcH: srcH) : (eyeN * 2, eyeN)' in sw)
check('(s36) flat modes need an even source width; h264 limit checks the canvas width', '!output.isFlat || (srcW >= 2 && srcH >= 2 && srcW % 2 == 0)' in sw and 'hevc.canvas.w <= h264MaxWidth' in sw)
check('(s36) projection: full/half flat-sbs, over_under flat-tb, anaglyph none, vr180 unchanged', '("flat-sbs", a)' in sw and '("flat-tb", a)' in sw and 'case .anaglyph: return nil' in sw and 'case .vr180: return (RenderedShotPlan.projectionKind, 0)' in sw)
check('(s36) flat-sbs / flat-tb are projections vr180-look.lua knows', '"flat-sbs"' in lua and '"flat-tb"' in lua)
check('(s36) writer sizes the file and the render to the plan canvas', 'plan.canvas.w, h2 = plan.canvas.h' in wr and 'AVVideoHeightKey: h2' in wr and 'output: plan.output' in wr)
# review (Darwin API semantics) pins in the writer loop
check('(review) writer bails out of the ready-spin when the writer is not .writing', 'if cancelled() || writer.status != .writing { throw fail(.write) }' in wr)
check('(review) only a .completed reader counts as a full read (nil sample buffer also means a failed reader)', 'guard sr.status == .completed else { throw fail(.open) }' in wr)
check('(review) CVMetalTexture stays alive through the blit that reads its texture', 'withExtendedLifetime(ft, { crop(padded, to: ftex) })' in wr)
mp = (S / 'RenderedShotMPV.swift').read_text()
import re, json
for msg in re.findall(r'"(vr180-look-[a-z-]+)"', mp): check('script message registered in vr180-look.lua: ' + msg, f'register_script_message("{msg}"' in lua)
import re as _re
def decoders(text): return [n for n in ('hevc', 'h264') if _re.search(r'(^|[^A-Za-z0-9_])' + n + r'([^A-Za-z0-9_]|$)', text, _re.I)]
check('probe runs the player with --vd=help (no socket)', '--vd=help' in mp and 'probeDecoders(executable:' in mp and 'readDataToEndOfFile' in mp)
check('model: whole-word decoder names only', decoders('  hevc - HEVC\n  h264 - H.264') == ['hevc', 'h264'] and decoders('hevc_videotoolbox h264_qsv') == [] and decoders('h264 only') == ['h264'])
check('load: start= film time, rebase-start-time=no, audio-file= source', 'start=' in mp and 'rebase-start-time=no' in mp and 'audio-file=' in mp and '"replace", -1' in mp)
co = (S / 'ThreeDRenderCoordinator.swift').read_text(); wi = (S / 'ThreeDWiring.swift').read_text(); ad = (S / 'AppDelegate.swift').read_text()
check('coordinator: eye size = source height even, 256..4096', 'max(256, min(4096, sourceHeight - sourceHeight % 2))' in co)
check('coordinator: render key includes mode, ipd, convergence, eye size, codec, swap', 'p.effectiveIPD' in co and 'p.convergenceM' in co and 'codec.rawValue' in co and 'swap' in co)
check('coordinator: stale or missing key re-renders; failure removes files and says so on the OSD', 'readJSON(side2)?["key"]' in co and 'removeItem(at:side2)' in co and 'revision.commit(token)' in co and 'could not be rendered' in co)
check('coordinator: playhead shot first, one at a time, cancel on mode off', 'first..<min(first + 3' in co and 'revision.invalidate()' in co and 'revision.isCurrent(token)' in co and 'qos: .utility' in co)
check('wiring: closures from cmd/currentTime/currentFilePath and one AppDelegate hook', 'self?.cmd(json)' in wi and 'controller?.currentTime' in wi and ad.count('startThreeDCoordinator()') == 1)
check('no socket-owner names in the new files (no new baseline rows needed)', all(w not in (mp + wr + sw + co + wi) for w in ('ipcCommand', 'IPCClient', 'PersistentEventConnection', 'MPVCommand', 'mpv.conf')))
sys.exit(1 if fails else 0)

co2 = (S / 'ThreeDRenderCoordinator.swift').read_text()
check('virtual screen: thetaH from prefs.thetaH(shotThetaH:aspect: src w/h), screenDeg in render key, depth not rescaled', 'prefs.thetaH(shotThetaH: th, aspect:' in co2 and '\\(p.screenDeg)' in co2 and 'thetaH: th,' not in co2)

co3 = (S / 'ThreeDRenderCoordinator.swift').read_text()
def shot_ready(doc, shot):
    e = next((x for x in doc.get('shots', []) if x.get('shot') == shot), None) if doc else None
    return True if e is None else (e.get('ready') is True and e.get('failed') is not True)
check('render-ready gate model: absent=ok, ready ok, failed or not ready = 2D', shot_ready(None, 0) and shot_ready({'shots': [{'shot': 1, 'ready': True, 'failed': False}]}, 1) and not shot_ready({'shots': [{'shot': 1, 'ready': True, 'failed': True}]}, 1) and not shot_ready({'shots': [{'shot': 1, 'ready': False, 'failed': False}]}, 1) and shot_ready({'shots': []}, 5))
check('coordinator gates tick and schedule on render-ready.json (s8)', 'render-ready.json' in co3 and co3.count('Self.shotReady(') == 2 and '"failed") as? Bool) != true' not in co3 and "(e[\"failed\"] as? Bool) != true" in co3)

co4 = (S / 'ThreeDRenderCoordinator.swift').read_text(); si = (S / 'DepthContainerWriter.swift').read_text().split('// BEGIN relocated DepthShotIndex.swift (195y G2, behavior unchanged)')[1].split('// END relocated DepthShotIndex.swift')[0]  # 195y G2; wi4 = (S / 'ThreeDWiring.swift').read_text(); fp4 = (S / 'FilmPrepareStatus.swift').read_text()
def shot_frames(shots, fps, pts):
    f = round(pts * fps)   # Python round(): half to even, same as the Swift port
    return next(((a, b) for a, b in shots if a <= f <= b), None)
check('model: shotFrames is the shot range regardless of prepared files', shot_frames([[0, 29], [30, 59]], 24.0, 1.3) == (30, 59) and shot_frames([[0, 29]], 24.0, 9.0) is None)
check('shotFrames kept fresh every tick (before the mode-off guard) and handed to the menu', co4.index('shotFrames = mapped') < co4.index('guard prefs.mode != "off"') and 'ThreeDMenu.shared.frameRange = { [weak c] in c?.shotFrames }' in wi4 and 'func shotFrames(pts: Double) -> (Int, Int)?' in si)
check('index cached per cache entry (no per-tick JSON reads)', 'indexCache' in co4 and co4.count('DepthShotIndex(entry:') == 1)
check('saved sbs/vr180 honours the preflight: stays 2D and says why', 'let unavailable = ThreeDPreflight.shared.reason' in co4 and 'unavailable == nil, let pts = mapped' in co4)
check('sbs labelled as vr180 until built (menu title + one OSD line)', 'sbs plays as vr180 for now' in co4 and 'sbs 3d (plays as vr180)' in (S / 'ThreeDMenu.swift').read_text())
check('osd line toggle honoured: coordinator announce and prepare OSD', 'ThreeDSettings.load().osdLine' in co4 and 'gor.3d.osdLine' in fp4)

co5 = (S / 'ThreeDRenderCoordinator.swift').read_text(); wr5 = (S / 'RenderShotWriter.swift').read_text(); fp5 = (S / 'FilmPrepareStatus.swift').read_text(); mn5 = (S / 'ThreeDMenu.swift').read_text()
check('soft surround: prefs.surroundSoft -> writer -> render(surround:), and in the render key with screenDeg', 'surround: prefs.surroundSoft' in co5 and 'surround: surround, outW: n' in wr5 and '\\(p.screenDeg)|\\(p.surroundSoft)' in co5)
check('surround in RenderPrefs.write (optional, soft/off), menu writes it, default soft, contract s4 documents it', 'o["surround"] = v ? "soft" : "off"' in fp5 and 'surroundSoft: s.surround == "soft"' in mn5 and 'surround = "soft"' in mn5 and '"surround": "soft"' in (root / 'tools/depth_analysis/CONTRACT-190v.md').read_text())

#!/usr/bin/env python3
"""s38 pins: generated Swift table == degrade_fsm.py (all 154 pairs), driver text pins, python model of the Swift driver clocks vs degrade_fsm. Swift uncompiled; nothing run on a Mac."""
import pathlib, sys, itertools
root = pathlib.Path(__file__).resolve().parents[2]; S = root / 'Sources/gor'
sys.path.insert(0, str(root / 'tools/depth_analysis')); sys.path.insert(0, str(pathlib.Path(__file__).parent))
import degrade_fsm as F, gen_table
dr = (S / 'ThreeDDegrade.swift').read_text()
tbl = dr.split('// BEGIN relocated ThreeDDegradeTable.swift (195y G2, behavior unchanged)')[1].split('// END relocated ThreeDDegradeTable.swift')[0].strip('\n') + '\n'  # 195y G2: table is a generated span inside ThreeDDegrade.swift; co = (S / 'ThreeDRenderCoordinator.swift').read_text()
bad = 0
def check(n, c):
    global bad; print(('PASS ' if c else 'FAIL ') + n); bad += (not c)
check('Swift table is byte-identical to the regenerated one from degrade_fsm.py', tbl == gen_table.render())
check('table has 7 states x 22 events and the contract constants', len(F.STATES) == 7 and len(F.EVENTS) == 22 and 'lgdHoldMs = 500, shotErrorLimit = 3' in tbl)
# model of ThreeDDegrade.handle/line: total function over all 154 pairs, line format identical
def swift_line(frm, ev):
    t = F._T.get((frm, ev)); to, acts, note = (t.to, t.actions, t.note) if t else (frm, (), 'ignored')
    a = '-' if not acts else '|'.join(acts).replace(' ', '_')
    return f'3dfsm from={frm} ev={ev} to={to} act={a}' + (f' note={note}' if note else '')
check('line format equals degrade_fsm Transition.logline for all 154 pairs', all(swift_line(s, e) == F.handle(s, e).logline(s, e) for s, e in itertools.product(F.STATES, F.EVENTS)))
check('Swift line()/handle() mirror it: joined with |, spaces to _, note only if non-empty, unlisted pair = ignored self-loop', 'joined(separator: "|").replacingOccurrences(of: " ", with: "_")' in dr and 'note: "ignored"' in dr and '"3dfsm from=\\(s.from) ev=\\(s.event) to=\\(s.to) act=\\(acts)"' in dr)
check('no table action names mpv restart / seek / pause playback / audio / recreate (contract invariant)', not any(any(f in a for f in F.FORBIDDEN_ACTION_SUBSTRINGS) for t in F._T.values() for a in t.actions))
check('driver drops forbidden actions before the executor and carries the same forbidden list', 'filter(Self.allowed).forEach(exec)' in dr and all(f'"{f}"' in dr for f in F.FORBIDDEN_ACTION_SUBSTRINGS))
# clocks model: 500 ms hold, 3 strikes
def hold(gap_ms):
    st = 'READY_STEREO'; st = F.handle(st, F.EV_UNCOVERED).to; ev = F.EV_LGD_TIMEOUT if gap_ms >= F.LGD_HOLD_MS else F.EV_LGD_RECOVERED
    return F.handle(st, ev).to
check('model: gap < 500 ms recovers to stereo, >= 500 ms drops to flat (FLAT_DEGRADED)', hold(499) == 'READY_STEREO' and hold(500) == 'FLAT_DEGRADED')
check('Swift clock: (now - holdSince) * 1000 >= lgdHoldMs, hold clock starts only on entering LGD_HOLD', '(now - t) * 1000 >= Double(DegradeTable.lgdHoldMs)' in dr and 's.to == "LGD_HOLD" && s.from != "LGD_HOLD"' in dr)
check('Swift strikes: third failure feeds shot_error_limit, success clears the shot, source change clears all', 'n >= DegradeTable.shotErrorLimit ? "shot_error_limit" : "shot_error"' in dr and 'strikes[shot] = nil' in dr and 'strikes = [:]' in dr)
check('3D <-> 2D never restarts anything: the only executor in the coordinator maps act_osd to the OSD line', 'a.hasPrefix("act_osd(")' in co and co.count('degrade.') >= 6)
check('coordinator hooks: observe(covered:), shotFailed/shotSucceeded, sourceChanged, userMode, probe, thermal via ThermalDutyPolicy', all(x in co for x in ('degrade.observe(covered: fresh', 'degrade.shotFailed(shot)', 'degrade.shotSucceeded(shot)', 'degrade.sourceChanged()', 'degrade.userMode(on:', 'degrade.probe(', 'duty.step(rank:', 'degrade.thermal(trip: true)')))
check('no player-socket words in new code', not any(__import__('re').search(r'\b(MPVCommand|ipcCommand|IPCClient|PersistentEventConnection)\b|mpv\.conf', l, 2) for l in (tbl + dr).split('\n')))
pr = dr.split('// BEGIN relocated ThreeDDegradeProbes.swift (195y G2, behavior unchanged)')[1].split('// END relocated ThreeDDegradeProbes.swift')[0]  # 195y G2; st = (S / 'ThreeDSelfTest.swift').read_text(); kit = (S / 'ThreeDKit.swift').read_text(); dw = (S / 'DepthContainerWriter.swift').read_text()
import re, colorprobe
reh = (root / 'tools/depth_analysis/rehearsal.py').read_text()      # imported text only: rehearsal.py needs torch, which this box lacks
rseq = [getattr(F, n) for n in re.findall(r'fsm\.(EV_[A-Z_]+)', reh[reh.index('def fsm_walk_lines'):reh.index('def render_key_v3')])]
ev = re.search(r'walkEvents = \[(.*?)\]', dr).group(1); evs = re.findall(r'"([a-z_]+)"', ev)
def walk(evs):
    s, out = 'INIT', []
    for e in evs: out.append(swift_line(s, e)); s = F.handle(s, e).to
    return out
check('self-test walk: Swift walkEvents produce exactly rehearsal.fsm_walk_lines (s39 item 12), and ThreeDSelfTest emits them', evs == rseq and len(rseq) == 11 and 'emit(ThreeDDegrade.walkLines())' in st)
check('s39: READY_STEREO thermal_clear / disk_freed resume prepare (regenerated table carries the change)', F.handle('READY_STEREO', F.EV_THERMAL_CLEAR).actions == ('act_prepare_resume', 'act_badge_clear') and '"READY_STEREO|thermal_clear": ("READY_STEREO", ["act_prepare_resume", "act_badge_clear"]' in tbl)
# kit/source/disk event decisions (model of ThreeDDegradeProbe)
def kit_event(missing, verified, failed):
    if missing == ['moge2_vits_*.mlpackage']: return 'moge_licence_off'
    if missing: return 'kit_missing'
    if failed is not None: return 'kit_bad_hash'
    return 'probe_ok' if verified else None
cases = [(['moge2_vits_*.mlpackage'], 0, None), (['x'], 0, None), ([], 0, ['p']), ([], 1, None), ([], 0, None)]
check('model: kit outcomes (MoGe-only missing = licence gate, other missing = kit_missing, failed hash = kit_bad_hash, verified = probe_ok, unverified = undecided)', [kit_event(m, v, f) for m, v, f in cases] == ['moge_licence_off', 'kit_missing', 'kit_bad_hash', 'probe_ok', None])
check('Swift kitEvent mirrors it in the same order (licence, missing, bad hash, verified, else undecided)', pr.index('moge_licence_off') < pr.index('"kit_missing"') < pr.index('"kit_bad_hash"') < pr.index('"probe_ok"') and 'missing == ["moge2_vits_*.mlpackage"]' in pr)
def src_event(transfer, dv, avg, mx):
    if transfer in colorprobe.HDR_TRANSFERS or dv: return 'refuse_hdr'
    if avg > 0 and mx > 0 and abs(mx - avg) / avg > colorprobe.VFR_REL_TOL: return 'refuse_vfr'
check('model vs colorprobe constants: HDR transfers / Dolby Vision -> refuse_hdr, VFR beyond 0.2% -> refuse_vfr, HDR wins over VFR', src_event('smpte2084', False, 24, 24) == 'refuse_hdr' and src_event('bt709', True, 24, 24) == 'refuse_hdr' and src_event('bt709', False, 24, 30) == 'refuse_vfr' and src_event('bt709', False, 24, 24.02) is None and src_event('arib-std-b67', False, 24, 30) == 'refuse_hdr')
check('Swift sourceEvent uses SourceFormat.hdrTransfers / dolbyVision / isVFR (the colorprobe port) in that order', 'SourceFormat.hdrTransfers.contains(f.transfer) || f.dolbyVision { return "refuse_hdr" }' in pr and 'SourceFormat.isVFR(f) { return "refuse_vfr" }' in pr and pr.index('refuse_hdr') < pr.index('refuse_vfr'))
check('ENOSPC: Cocoa 640 or POSIX 28 only; the .dzc writer notes both write catch sites; coordinator feeds disk_full once and disk_freed on 2 GiB headroom', 'code == 640' in pr and 'code == 28' in pr and dw.count('ThreeDDegradeProbe.noteWriteError(error)') == 2 and 'minHeadroomBytes: Int64 = 2 << 30' in pr and 'degrade.disk(full: true)' in co and 'degrade.disk(full: false)' in co)
check('mode toggles only on change and the same refusal is not re-fed (no per-tick log spam)', 'guard prev != on else { return }' in dr and '!(st == "UNAVAILABLE_FLAT" && last == event)' in dr)
check('app_quit via the terminate notification, relaunch when a prepared cache (cuts.json) exists at the first tick', 'NSApplicationWillTerminateNotification' in dr and 'degrade.feed("relaunch")' in co and 'cuts.json' in co)
check('probe order: source refusal first, kit second; kit state read via ThreeDKit.probeState()', co.index('ThreeDDegradeProbe.sourceEvent(film: f)') < co.index('ThreeDDegradeProbe.kitEvent(') and 'static func probeState()' in kit)
gate_src = (S / 'StereoSourceGate.swift').read_text(); spc = (S / 'SourcePixelCrop.swift').read_text(); bsh = (root / 'build.sh').read_text()
check('s42 ffprobe: a missing vendored ffprobe is logged once by the stereo gate (not silent); SourcePixelCrop already falls back to ffmpeg; build.sh ROOTS is NOT changed (ffprobe is optional in the owner vendor, and the sign-leaf list would not sign it)', 'note: "ffprobe-missing"' in gate_src and 'isExecutableFile(atPath: ffprobe())' in gate_src and 'ffprobe is optional in the owner' in spc and "'ffmpeg/bin/ffmpeg','node/node'" in bsh and '*/ffmpeg|ffmpeg|*/gifsicle' in bsh)
sys.exit(1 if bad else 0)

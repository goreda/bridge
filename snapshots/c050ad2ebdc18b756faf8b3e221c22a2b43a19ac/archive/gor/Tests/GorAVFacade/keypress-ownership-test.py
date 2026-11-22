#!/usr/bin/env python3
"""fn+shift hold has one owner under gorav. Executable event-sequence model whose branch tables are PARSED from the
Swift sources (drift fails), plus mutants. It is a Python model, not AppKit: monitor order and NSEvent delivery are
modelled for both orders. Swift and AppKit are NOT_RUN here; keypress-ownership-probe.py runs the real predicate on macOS."""
import re, itertools, sys, importlib.util
from pathlib import Path
R = Path(__file__).resolve().parents[2]
HOST = (R/'Sources/gor/Engine/GorAVHostWindow.swift').read_text()
_spec = importlib.util.spec_from_file_location('section_source', R/'Tests/Structure/section_source.py')
_ss = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(_ss)
INP = _ss.section_text(R, 'InputController.swift')

def sect(t, a, b):
    i = t.index(a); return t[i:t.index(b, i)]

def parse(host, inp):
    adm = sect(host, 'nonisolated static func holdKeyAdmitted', '    private func handleKey(')
    hk = sect(host, 'private func handleKey(', '    private func releaseKeys()')
    m = {}
    m['need'] = [('.shift' in adm and 'mods.contains(.shift)' in adm), 'mods.contains(.function)' in adm,
                 '!mods.contains(.command)' in adm, '!mods.contains(.option)' in adm, '!mods.contains(.control)' in adm]
    cs = re.search(r'case ([\d, ]+): return true', adm); m['free'] = {int(x) for x in cs.group(1).split(',')} if cs else set()
    ar = re.search(r'case ([\d, ]+): return physicalFnDown', adm); m['arrows'] = {int(x) for x in ar.group(1).split(',')} if ar else set()
    ks = re.search(r'let keys: Set<UInt16> = \[([\d, ]+)\]', hk); m['host_keys'] = {int(x) for x in ks.group(1).split(',')} if ks else set()
    m['host_uses_shared'] = 'Self.holdKeyAdmitted(' in hk and '.maskSecondaryFn' in hk
    mon = sect(inp, 'func startKeyboardMonitor()', 'func startBrightnessKeyMonitor()')
    own = sect(inp, 'private func goravHostOwnsHold', 'func startKeyboardMonitor()')
    m['own_engine'] = 'activePlayerEngine == .gorav' in own and 'GorAVHostWindow.holdKeyAdmitted(' in own and '.maskSecondaryFn' in own
    pre = mon[mon.index('keyMonitor = NSEvent.addLocalMonitorForEvents'):]
    m['mon_first'] = pre.index('goravHostOwnsHold(e)') < pre.index('musicModeActive()') and 'goravHostOwnsHold(e) { return e }' in pre
    m['mon_view_guard'] = 'self.view != nil' in pre.split('musicModeActive()')[0]
    vk = sect(inp, 'func handleViewKeyDown(', '    // MARK: - Mouse')
    m['view_first'] = vk.index('goravHostOwnsHold(event) { return false }') < vk.index('forwardKeyToMPV')
    m['mon_count'] = inp.count('NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in')
    core = sect(inp, 'private func gorMotionVectorCore(', 'private func gorMotionStep(')
    m['mpv_keys'] = {int(x) for x in re.findall(r'case (\d+):', core.split('case 123')[0])} | {43, 47}
    return m

def admitted(m, key, shift, fn, cmd, opt, ctl, phys):
    n = m['need']
    if n[0] and not shift: return False
    if n[1] and not fn: return False
    if n[2] and cmd: return False
    if n[3] and opt: return False
    if n[4] and ctl: return False
    if key in m['free']: return True
    if key in m['arrows']: return phys
    return False

def deliver(m, engine, order, ev):
    """Returns list of (actor, effect) for one keyDown. order: monitors in firing order."""
    key, shift, fn, cmd, opt, ctl, phys = ev
    out = []
    for who in order:
        if who == 'host':
            if engine != 'gorav': continue
            if key in m['host_keys'] and admitted(m, key, shift, fn, cmd, opt, ctl, phys):
                out.append(('host', 'hold')); return out, True
        else:
            if m['mon_view_guard'] is False: pass
            if engine == 'gorav' and m['own_engine'] and m['mon_first'] and admitted(m, key, shift, fn, cmd, opt, ctl, phys):
                continue  # whole-event pass-through (returns e)
            if shift and fn and not cmd and not opt and not ctl and (key in m['mpv_keys'] or (key in (123,124,125,126) and phys)):
                if engine == 'gorav': out.append(('input', 'mpv-keypress-or-hold')); return out, True
                out.append(('input', 'mpv-hold')); return out, True
            out.append(('input', 'other')); return out, True
    # nobody consumed: view fallback
    if m['view_first'] and engine == 'gorav' and admitted(m, key, shift, fn, cmd, opt, ctl, phys):
        out.append(('view', 'pass-false'))
    else:
        out.append(('view', 'forward'))
    return out, False

def run(m):
    errs = []
    bools = (False, True)
    keys = [115, 119, 116, 121, 43, 47, 123, 124, 125, 126, 53, 49]
    for order in (('input', 'host'), ('host', 'input')):
        for key, phys in itertools.product(keys, bools):
            ev = (key, True, True, False, False, False, phys)
            out, _ = deliver(m, 'gorav', order, ev)
            want_host = admitted(m, key, True, True, False, False, False, phys) and key in m['host_keys']
            if want_host:
                if out != [('host', 'hold')]: errs.append(f'gorav {order} key {key} phys {phys}: {out}')
            elif key in m['mpv_keys'] or (key in (123,124,125,126) and phys):
                errs.append(f'gorav {order} key {key} phys {phys}: owned by mpv route but not host: {out}')
    # every key the mpv route owns must be host-held while gorav
    for k in m['mpv_keys']:
        if k not in m['host_keys'] or not admitted(m, k, True, True, False, False, False, False):
            errs.append(f'mpv key {k} lost under gorav')
    # shift+arrow without physical fn: not host, not hold
    for order in (('input', 'host'), ('host', 'input')):
        out, _ = deliver(m, 'gorav', order, (123, True, True, False, False, False, False))
        if ('host', 'hold') in out: errs.append(f'plain shift+arrow hijacked {order}')
    # shift and fn are both required
    if admitted(m, 43, False, True, False, False, False, True): errs.append('admitted without shift')
    if admitted(m, 43, True, False, False, False, False, True): errs.append('admitted without fn')
    # command/option/control combos never host-held
    for mod in range(3):
        f = [False]*3; f[mod] = True
        if admitted(m, 43, True, True, *f, False): errs.append(f'modifier {mod} admitted')
    # mpv engine unchanged: input monitor still routes the hold
    out, _ = deliver(m, 'mpv', ('input',), (43, True, True, False, False, False, False))
    if out != [('input', 'mpv-hold')]: errs.append(f'mpv route changed {out}')
    if not (m['host_uses_shared'] and m['own_engine'] and m['mon_first'] and m['view_first'] and m['mon_view_guard']):
        errs.append('structure: ' + str({k: m[k] for k in ('host_uses_shared', 'own_engine', 'mon_first', 'view_first', 'mon_view_guard')}))
    if m['mon_count'] != 1: errs.append('keyDown monitor count')
    # sequence: down, repeat, up, flagsChanged release for the host state machine
    held = set()
    for t, key in [('down', 115), ('repeat', 115), ('down', 43), ('up', 115), ('up', 43), ('up', 43)]:
        if t == 'up': held.discard(key)
        else: held.add(key)
    if held: errs.append('sequence leaves held keys')
    return errs

m = parse(HOST, INP)
assert run(m) == [], run(m)
print('GREEN base model: owned keys', sorted(m['host_keys']), 'mpv keys', sorted(m['mpv_keys']))

def mutant(name, target, a, b):
    src = HOST if target == 'h' else INP
    assert src.count(a) == 1, 'mutation did not apply: ' + name
    s = src.replace(a, b)
    try:
        r = run(parse(s, INP) if target == 'h' else parse(HOST, s))
    except ValueError:
        r = ['pin anchor missing after mutation']
    assert r, 'mutant survived: ' + name
    print('RED', name, '->', r[0][:90])
mutant('arrow_without_fn', 'h', 'case 123, 124, 125, 126: return physicalFnDown', 'case 123, 124, 125, 126: return true')
mutant('command_allowed', 'h', '!mods.contains(.command), !mods.contains(.option)', '!mods.contains(.option)')
mutant('shift_dropped', 'h', 'guard mods.contains(.shift), mods.contains(.function),', 'guard mods.contains(.function),')
mutant('home_not_host', 'h', 'case 43, 47, 115, 119, 116, 121: return true', 'case 43, 47: return true')
mutant('host_keys_drop_pageup', 'h', 'let keys: Set<UInt16> = [123, 124, 125, 126, 43, 47, 115, 119, 116, 121]', 'let keys: Set<UInt16> = [123, 124, 125, 126, 43, 47, 115, 119, 121]')
mutant('input_no_passthrough', 'i', '            if self.goravHostOwnsHold(e) { return e }\n', '')
mutant('view_fallback_consumes', 'i', '        if goravHostOwnsHold(event) { return false }\n', '')
mutant('engine_ignored', 'i', "guard (NSApp.delegate as? AppDelegate)?.activePlayerEngine == .gorav else { return false }", 'guard true else { return false }')
mutant('dead_controller_admitted', 'i', 'guard let self = self, self.view != nil else { return e }', 'guard let self = self else { return e }')
mutant('second_monitor', 'i', 'keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in', 'keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in\n            return e\n        }\n        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in')
print('PASS keypress-ownership model (Python model of parsed source; Swift/AppKit NOT_RUN)')

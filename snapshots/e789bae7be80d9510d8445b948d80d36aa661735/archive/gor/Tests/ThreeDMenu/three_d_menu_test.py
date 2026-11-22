#!/usr/bin/env python3
"""191b B4 pins (Swift uncompiled, Linux only): the one store-driven 3d menu. The pre-191b pins (menu-side defaults,
RenderPrefs.write in the menu, numeric submenus) were retired by the 191b owner order; the store (E-G) owns state and defaults.
Contract keys live in the ledger: Tests/MenuStructure/required-items.json."""
import pathlib, re, sys
root = pathlib.Path(__file__).resolve().parents[2]; S = root / 'Sources/gor'
m = (S / 'ThreeDMenu.swift').read_text(); km = (S / 'ThreeDKeymap.swift').read_text(); f = (S / 'FilmPrepareStatus.swift').read_text(); ad = (S / 'AppDelegate.swift').read_text()
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
def covers(ranges, a, b): return b >= a and any(len(r) == 2 and r[0] <= a and b <= r[1] for r in ranges)
check('model: inside one prepared range', covers([[0, 99], [200, 299]], 10, 20) and not covers([[0, 99], [200, 299]], 90, 210) and not covers([], 0, 0))
check('Swift availability uses the same rule', 'r[0] <= first' in f.replace('$0[0] <= first', 'r[0] <= first') and 'last <= $0[1]' in f)
check('B1: the menu holds NO defaults (the store owns them: head/blink/crossEye false, ipd 0, strength 1, screenDepth 1.5, screenSize 75, surround soft, quality auto, osdLine true)',
      'ThreeDSettings' not in m and 'UserDefaults' not in m and 'RenderPrefs.write' not in m)
check('B4: one "3d" menu with a disabled status line first', 'NSMenuItem(title: "3d"' in m and 'status.tag = -1' in m and 'status.isEnabled = false' in m)
check('B4: rows come from the one keymap table and carry its key equivalents',
      'ThreeDKeymap.rows.first { $0.act == act }' in m and 'keyEquivalent: r.chord?.key' in m and 'i.representedObject = act.rawValue' in m)
check('B4: every row is a store dispatch through the single rowTapped -> dispatch(act) path',
      '@objc func rowTapped(_ i: NSMenuItem)' in m and 'Self.dispatch(act)' in m and 'static func dispatch(_ act: ThreeDKeymap.Act)' in m)
_nocomment = lambda s: '\n'.join(re.sub(r'//.*', '', ln) for ln in s.splitlines())
_display = m[:m.index('static func statusTitle')] + m[m.index('func validateMenuItem'):]  # statusTitle() is a display read helper
check('B4: store state is read only in dispatch (the write path E-G sanctioned: read-add-dispatch steps), validateMenuItem and the statusTitle display helper',
      'ThreeDStore.shared.snapshot' not in _nocomment(m[:m.index('static func dispatch')])
      and 'ThreeDStore.shared.snapshot' not in _nocomment(_display[_display.index('// MARK: - install'):_display.index('func validateMenuItem')]))
check('B4: state visible - status line shows "3D: <Output> · <Source>" and per-row checkmarks; the status item refreshes every menu open via NSMenuDelegate (a nil-action item gets no validateMenuItem)',
      'static func statusTitle() -> String' in m and '"3D: " + ThreeDInfo.outputLabel(cur.output)' in m and 'ThreeDInfo.sourceLabel(cur.source.format)' in m
      and 'i.title = Self.statusTitle()' in m and m.count('i.state =') >= 10
      and 'func menuNeedsUpdate(_ menu: NSMenu)' in m and 'status.title = Self.statusTitle()' in m and 'm.delegate = self' in m)
check('B4: section headers View/Film is/Depth/Screen/Size (VR180)/Eyes/Surround/Quality are disabled non-dispatch items; separators only after 3D On/Off and after Film is',
      all('header("%s")' % h in m for h in ['View','Film is','Depth','Screen','Size (VR180)','Eyes','Surround','Quality'])
      and 'func header(_ title: String)' in m and 'h.tag = -2' in m and 'h.isEnabled = false' in m and m.count('.separator()') == 2)
check('B4: Auto row shows the detected source', '"Auto (" + detectedSource()' in m)
check('B4: unbuilt quality tiers are hidden, not labelled', 'i.isHidden = ThreeDRunnerRegistry.runner == nil' in m and 'not implemented' not in m)
check('B4: Shift+V row means View VR180 / back to Off', 'store.snapshot.current.output == .vr180 ? .off : .vr180' in m)
check('B4: no numeric submenus and no Cmd+Ctrl+Opt source shortcuts remain (the keymap has no command chords)',
      'sub(' not in m and 'command: true' not in km)
check('B4: live steps read the number, add the step, dispatch (strength/screenSize/ipd additive, screenDepth scaled), each clamped',
      'stepped(' in m and 'scaled(' in m and m.count('range.lowerBound') >= 2 and m.count('range.upperBound') >= 2)
check('single AppDelegate hook', ad.count('ThreeDMenu.shared.install(in: videoMenu)') == 1)
co = (S / 'ThreeDRenderCoordinator.swift').read_text()
check('FSM probe skips films the stereo gate routes away from depth (no preparing badge for an already-3D file); source refusal still precedes the kit outcome',
      'StereoSourceGate.shared.route(for: f)?.route == .depth' in co and co.index('ThreeDDegradeProbe.sourceEvent(film: f)') < co.index('ThreeDDegradeProbe.kitEvent('))
sys.exit(1 if fails else 0)

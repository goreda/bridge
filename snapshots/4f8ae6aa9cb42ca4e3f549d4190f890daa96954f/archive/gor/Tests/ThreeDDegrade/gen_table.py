#!/usr/bin/env python3
"""Emits the body of the DegradeTable span (195y G2: relocated inside Sources/gor/gor/ThreeD.swift (ThreeDDegrade.swift section)) from tools/depth_analysis/degrade_fsm.py (CONTRACT-190v s38). The pin test regenerates and compares."""
import pathlib, sys
root = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / 'tools/depth_analysis'))
import degrade_fsm as F
def q(s): return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'
def render():
    o = ['// GENERATED from tools/depth_analysis/degrade_fsm.py by Tests/ThreeDDegrade/gen_table.py (CONTRACT-190v s38). Do not edit by hand; the pin test regenerates and diffs.',
         '// Pure data: (state, event) -> next state, action strings, note. Unlisted pairs are logged "ignored" self-loops (DegradeTable.handle).',
         '// Not compiled or run on a Mac.', '', 'enum DegradeTable {',
         f'    static let lgdHoldMs = {F.LGD_HOLD_MS}, shotErrorLimit = {F.SHOT_ERROR_LIMIT}',
         '    static let states: [String] = [' + ', '.join(q(s) for s in F.STATES) + ']',
         '    static let events: [String] = [' + ', '.join(q(e) for e in F.EVENTS) + ']',
         '    /// "state|event" -> (to, actions, note)',
         '    static let rules: [String: (to: String, actions: [String], note: String)] = [']
    for (s, e), t in sorted(F._T.items()):
        o.append(f'        {q(s + "|" + e)}: ({q(t.to)}, [' + ', '.join(q(a) for a in t.actions) + f'], {q(t.note)}),')
    o += ['    ]', '}', '']
    return '\n'.join(o)
if __name__ == '__main__': sys.stdout.write(render())

#!/usr/bin/env python3
"""Check the product keypress IPC boundary and generate its native Swift test.

The native test runs the exact product send expression with the real MPVCommand
builder. It does not emulate NSEvent routing, focus ownership, or an mpv process.
"""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=ROOT)
parser.add_argument('--structural-only', action='store_true')
args = parser.parse_args()
source = (args.root / 'Sources/gor/Player/Input.swift').read_text()
builder = (args.root / 'Sources/gor/Engine/MPVCommand.swift').read_text()
start = source.index('    private func forwardKeyToMPV(')
end = source.index('\n    private func mpvKeyName(', start)
forward = source[start:end]
expression = 'ipcCommand(MPVCommand.make(["keypress", mpvKey]))'
assert expression in forward, 'keypress must use the product JSON builder'
assert 'replacingOccurrences' not in forward, 'manual partial escaping returned'
assert 'guard !mpvKey.isEmpty else { return }' in forward
assert '"cycle","pause"' in forward, 'plain Space pause route changed'
start = builder.index('enum MPVCommand {')
end = builder.index('\n}\n', start) + 2
product_builder = builder[start:end]
assert 'JSONSerialization.data(withJSONObject: ["command": args])' in product_builder

# Independent framing witness: the former encoder cannot serialize this input.
try:
    json.loads('{"command":["keypress","a\x01b"]}')
except json.JSONDecodeError:
    pass
else:
    raise AssertionError('legacy control-character witness no longer rejects')
print('PASS product forwarding boundary, builder identity, legacy failure witness')
if args.structural_only:
    print('NOT RUN native Swift: structural checks are not runtime proof')
    raise SystemExit(0)

main = r'''
var count = 0
func check(_ mpvKey: String) {
    var frames: [String] = []
    func ipcCommand(_ line: String) { frames.append(line) }
    SEND_EXPRESSION
    precondition(frames.count == 1)
    let line = frames[0]
    precondition(!line.contains("\n") && !line.contains("\r"))
    let decoded = try! JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
    precondition(decoded.count == 1)
    precondition((decoded["command"] as! [String]) == ["keypress", mpvKey])
    count += 1
}
for scalar in UInt32(0)...UInt32(31) { check("a" + String(UnicodeScalar(scalar)!) + "b") }
for key in ["a", "Meta+g", "Shift+B", "Ctrl+Alt+LEFT", "\\", "\"", "\t", "\n", "\r", "İ", "🎬", "a\u{2028}b"] { check(key) }
print("PASS native product keypress serialization: \(count) roundtrips")
'''.replace('SEND_EXPRESSION', expression)
with tempfile.TemporaryDirectory() as work:
    test = Path(work) / 'main.swift'
    test.write_text('import Foundation\n' + product_builder + '\n' + main)
    subprocess.run(['swift', str(test)], check=True)

#!/usr/bin/env python3
"""A027 exact-source audio-channel command escaping witness.

Default mode typechecks and executes the actual method plus MPVCommand with
recording input/transport types. --wiring-only makes no Swift behavior claim.
The full AppKit host build remains a separate gate.
"""
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / 'Sources/gor/UI/MenuActions.swift').read_text()
commands = (ROOT / 'Sources/gor/Engine/MPVCommand.swift').read_text()

def balanced(text, declaration):
    start = text.index(declaration)
    opening = text.index('{', start)
    end, depth = opening + 1, 1
    while depth and end < len(text):
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    assert depth == 0
    return text[start:end]

method = balanced(source, '@objc func menuAudioChannels(')
serializer = balanced(commands, 'enum MPVCommand {')
assert 'guard let value = sender.representedObject as? String else { return }' in method
assert 'AudioMenuState.channelLayout = value' in method
assert re.search(r'cmd\(MPVCommand\.make\(\["set_property",\s*"audio-channels",\s*value\]\)\)', method)
assert method.count('cmd(') == 1
print('PASS source binding: string guard, state assignment, single JSON serializer')
if '--wiring-only' in sys.argv:
    print('Swift behavior NOT RUN (--wiring-only)')
    sys.exit(0)
compiler = shutil.which('swiftc')
if not compiler:
    print('BLOCKED: swiftc unavailable; behavior NOT RUN', file=sys.stderr)
    sys.exit(2)
program = '''import Foundation
''' + serializer + '''
struct NSMenuItem { var representedObject: Any? }
enum AudioMenuState { static var channelLayout = "auto-safe" }
final class Menu {
    var lines: [String] = []
    func cmd(_ line: String) { precondition(AudioMenuState.channelLayout == expectedAtSend); lines.append(line) }
    var expectedAtSend = ""
''' + method.replace('@objc ', '', 1) + '''
}
let menu = Menu()
let values = ["auto-safe", "stereo", "5.1", "", "quote\\\"value", "back\\\\slash", "line\\nbreak", "tab\\tvalue", "nul\\0value", "Türkçe 🎵"]
for value in values {
    let before = menu.lines.count
    menu.expectedAtSend = value
    menu.menuAudioChannels(NSMenuItem(representedObject: value))
    precondition(menu.lines.count == before + 1)
    precondition(AudioMenuState.channelLayout == value)
    let line = menu.lines.last!
    precondition(!line.contains("\\n") && !line.contains("\\r"))
    let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
    precondition(object.count == 1)
    precondition(object["command"] as? [String] == ["set_property", "audio-channels", value])
}
let count = menu.lines.count
let state = AudioMenuState.channelLayout
let invalidValues: [Any?] = [nil, 12, ["stereo"]]
for invalid in invalidValues {
    menu.menuAudioChannels(NSMenuItem(representedObject: invalid))
    precondition(menu.lines.count == count && AudioMenuState.channelLayout == state)
}
print("PASS exact-source Swift: ten escaping values and three refused non-string inputs")
'''
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    (root / 'main.swift').write_text(program)
    subprocess.run([compiler, '-typecheck', str(root / 'main.swift')], check=True)
    subprocess.run([compiler, str(root / 'main.swift'), '-o', str(root / 'test')], check=True)
    subprocess.run([str(root / 'test')], check=True)
    # Every adverse body compiles before runtime rejection counts.
    raw = r'cmd("{\"command\":[\"set_property\",\"audio-channels\",\"\(value)\"]}")'
    mutants={
      'actual-old-unescaped-body': ('cmd(MPVCommand.make(["set_property", "audio-channels", value]))',raw),
      'wrong-property': ('["set_property", "audio-channels", value]','["set_property", "volume", value]'),
      'send-before-state': ('AudioMenuState.channelLayout = value\n        cmd(MPVCommand.make(["set_property", "audio-channels", value]))','cmd(MPVCommand.make(["set_property", "audio-channels", value]))\n        AudioMenuState.channelLayout = value'),
      'omit-state': ('AudioMenuState.channelLayout = value','_ = value'),
    }
    for name,(before,after) in mutants.items():
        assert before in program,name
        (root/'main.swift').write_text(program.replace(before,after,1))
        subprocess.run([compiler,str(root/'main.swift'),'-o',str(root/'mutant')],check=True,capture_output=True)
        result=subprocess.run([str(root/'mutant')],capture_output=True)
        assert result.returncode != 0,'SURVIVED '+name
        print('KILLED compiled runtime mutant '+name)
print('AppKit full-host typecheck/build NOT RUN by this isolated witness')

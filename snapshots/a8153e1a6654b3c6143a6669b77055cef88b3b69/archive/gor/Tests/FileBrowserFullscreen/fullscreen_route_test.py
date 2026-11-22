#!/usr/bin/env python3
"""Source-bound fullscreen route contract; does not simulate AppKit events."""
from pathlib import Path
import json
import re
import sys

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]

def method(source, declaration, following):
    start = source.index(declaration)
    end = source.index(following, start + len(declaration))
    return source[start:end]

def verify(browser, menu):
    scroll = browser[browser.index('class RowSnapScrollView:'):]
    click = method(scroll, '    override func mouseDown(with event: NSEvent)', '\n    override func mouseDragged(')
    assert 'if event.clickCount == 2 {' in click
    assert click.count('?.menuFullscreen()') == 1, 'double-click must use the existing menu owner'
    assert 'ipcCommand' not in browser, 'FileBrowser must not speak mpv IPC'
    assert re.search(r'menuFullscreen\(\)\s*\n\s*return\s*\n\s*}\s*\n\s*super.mouseDown\(with: event\)', click), 'keep consume-double / pass-single lifecycle'
    fullscreen = method(menu, '    @objc func menuFullscreen()', '\n    @objc func menuOntop()')
    literal = re.search(r'cmd\(#"(.*?)"#\)', fullscreen)
    assert literal and json.loads(literal.group(1)) == {'command': ['cycle', 'fullscreen']}, 'existing owner command changed'
    cmd = re.search(r'func cmd\(_ json: String\)\s*\{(.*?)\}', menu)
    assert cmd and 'controller?.ipcCommand(json)' in cmd.group(1), 'menu owner no longer preserves IPC destination'

browser = (ROOT / 'Sources/gor/Media/FileBrowser.swift').read_text()
menu = (ROOT / 'Sources/gor/UI/MenuActions.swift').read_text()
verify(browser, menu)
mutants = [
    browser.replace('?.menuFullscreen()', '?.menuOntop()'),
    browser.replace('if event.clickCount == 2 {', 'if event.clickCount == 1 {'),
    browser.replace('super.mouseDown(with: event)', 'super.mouseUp(with: event)'),
    browser.replace('?.menuFullscreen()', '?.controller?.ipcCommand("fullscreen")'),
]
for i, mutant in enumerate(mutants, 1):
    assert mutant != browser
    try:
        verify(mutant, menu)
    except AssertionError:
        continue
    raise AssertionError(f'mutant {i} survived')
print('PASS FileBrowser fullscreen source contract; 4/4 mutants rejected')
print('Scope: source-bound menu destination, payload and click lifecycle; native AppKit event execution not run')

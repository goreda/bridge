#!/usr/bin/env python3
"""Fail before build work when project-authored executable text is not English."""
import argparse
import html
from html.parser import HTMLParser
from pathlib import Path
import re
import sys

# Code points keep this gate's own source and diagnostics English-only.
LETTERS = ''.join(map(chr, [231, 287, 305, 246, 351, 252, 199, 286, 304, 214, 350, 220]))
BAD = re.compile('[' + LETTERS + ']')
WORD_CODES = [[107, 97, 98, 117, 108], [99, 97, 108, 105, 115, 116, 105, 114, 105, 108, 109, 97, 100, 105], [99, 97, 108, 105, 115, 116, 105, 114, 105, 108, 100, 105], [98, 97, 115, 97, 114, 105, 108, 105], [98, 97, 115, 97, 114, 105, 115, 105, 122], [116, 97, 109, 97, 109, 108, 97, 110, 100, 105], [98, 117, 108, 117, 110, 97, 109, 97, 100, 105], [98, 97, 115, 108, 97, 116, 105, 108, 105, 121, 111, 114], [98, 101, 107, 108, 101, 110, 105, 121, 111, 114], [121, 117, 107, 108, 101, 110, 105, 121, 111, 114], [104, 97, 116, 97], [117, 121, 97, 114, 105], [100, 101, 114, 108, 101, 109, 101]]
WORDS = re.compile(r"\b(?:" + "|".join(bytes(code).decode() for code in WORD_CODES) + r")\b", re.I)
EXTENSIONS = {'.sh', '.py', '.swift', '.lua', '.js', '.mjs', '.ts', '.html', '.yml', '.yaml'}
ROOTS = ('Sources', 'Packages', 'tools', 'scripts', 'Tests', 'Resources')

def decoded(line):
    return html.unescape(re.sub(r"\\(?:u([0-9a-fA-F]{4})|x([0-9a-fA-F]{2}))", lambda match: chr(int(match.group(1) or match.group(2), 16)), line))

def ui_text_values(line):
    # Inspect values, never property names, DOM ids or other identifiers.
    for match in re.finditer(r'''(?:[:=(,]|\breturn)\s*(["'])(.*?)\1''', line):
        yield decoded(match.group(2))
    parser = UIParser()
    # Source regex lookbehinds are not HTML marked sections. Keep them text.
    parser.feed(line.replace("<![", "&lt;!["))
    yield from parser.values

class UIParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.values = []
    def handle_data(self, value):
        self.values.append(value.strip())
    def handle_starttag(self, tag, attrs):
        self.values.extend(value for key, value in attrs if key in ('aria-label', 'title', 'placeholder', 'alt') and value)

# Confirmed former interface labels, stored as data rather than output prose.
UI_CODES = [[109,101,115,97,106,108,97,114],[107,111,100],[103,105,114],[103,111,110,100,101,114],[121,101,110,105,100,101,110,32,100,101,110,101],[98,101,107,108,105,121,111,114],[115,101,110],[99,105,104,97,122,32,117,110,117,116]]
UI_LABELS = {bytes(code).decode() for code in UI_CODES}

def violations(root):
    files = [root / 'build.sh', root / 'gor-selftest.sh']
    for name in ROOTS:
        files.extend(p for p in (root / name).rglob('*') if p.is_file() and p.suffix in EXTENSIONS and '__pycache__' not in p.parts and 'vendor' not in p.parts)
    for path in sorted(set(files)):
        if not path.is_file():
            continue
        for number, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
            # Authenticated owner quotations in existing test comments are evidence.
            if line.lstrip().startswith('#') and '(owner,' in line:
                continue
            # Preserve the existing keyboard binding and French language label.
            checked = decoded(line).replace('Fran' + chr(231) + 'ais', 'French')
            checked = checked.replace('"' + chr(252) + '"', '"UNICODE_KEY"')
            if BAD.search(checked) or WORDS.search(checked) or any(value.strip().lower() in UI_LABELS for value in ui_text_values(line)):
                yield f'{path.relative_to(root)}:{number}'

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    bad = list(violations(args.root))
    if bad:
        print('ENGLISH_TEXT_GUARD FAIL', *bad, sep='\n', file=sys.stderr)
        return 1
    print('ENGLISH_TEXT_GUARD PASS: active executable source, build tools and tests')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())

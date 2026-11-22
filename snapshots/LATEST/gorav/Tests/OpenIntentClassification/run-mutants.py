#!/usr/bin/env python3
"""Compiled mutations must fail assertions, never count compiler errors."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'Sources/GorAVPlaybackCore/OpenIntentClassification.swift').read_text()
mutations = [
    ('font-as-media', '"woff2": kind = .font', '"woff2": kind = .media'),
    ('subtitle-as-media', '"sub": kind = .subtitle', '"sub": kind = .media'),
    ('torrent-as-media', 'case "torrent": kind = .torrent', 'case "torrent": kind = .media'),
    ('image-as-media', '"ico", "heic", "heif", "avif": kind = .image', '"ico", "heic", "heif", "avif": kind = .media'),
    ('no-extension-case-fold', '.pathExtension.lowercased()', '.pathExtension'),
    ('no-local-authority-check', 'return .refused(.nonlocalFileURL)', 'return local(url.path)'),
    ('decoded-literal-path', 'return local(input)', 'return local(input.removingPercentEncoding ?? input)'),
    ('double-decoded-file-url', 'return local(url.path)', 'return local(url.path.removingPercentEncoding ?? url.path)'),
    ('remote-bypasses-router', 'return .routed(OpenURLRouter.route(input))', 'return local(input)')
]
with tempfile.TemporaryDirectory() as directory:
    for name, before, after in mutations:
        if source.count(before) != 1:
            raise SystemExit('mutation anchor not unique: ' + name)
        path = Path(directory) / (name + '.swift')
        path.write_text(source.replace(before, after))
        env = dict(os.environ, INTENT_SOURCE=str(path))
        result = subprocess.run([str(root / 'Tests/OpenIntentClassification/run-portable.sh')],
                                env=env, capture_output=True, text=True)
        assertion_failed = 'FAIL classification case ' in result.stdout
        if result.returncode != 1 or not assertion_failed or result.stderr:
            print(result.stdout, result.stderr)
            raise SystemExit('NOT assertion-killed: ' + name)
        print('ASSERTION-KILLED ' + name)
print(str(len(mutations)) + '/' + str(len(mutations)) + ' compiled mutants rejected')

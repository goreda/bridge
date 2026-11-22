#!/usr/bin/env python3
"""Compile actual current cursor decision; never count a Python mirror as native proof."""
from pathlib import Path
import os,subprocess,tempfile
root=Path(__file__).resolve().parents[2]
source=(root/'Sources/gor/Player/PPController.swift').read_text()
harness=(Path(__file__).with_name('main.swift')).read_text()
start=harness.index('    enum CursorHideDecision');end=harness.index('\n}\n',start)
assert harness[start:end] in source
adapter=source[source.index('    private func checkCursorHide()'):source.index('    enum CursorHideDecision')]
assert 'win!.isVisible && win!.isOnActiveSpace' in adapter
assert 'CGDisplayHideCursor' in adapter and 'CGDisplayShowCursor' in adapter
with tempfile.TemporaryDirectory(prefix='gor-cursor-decision-') as d:
 binary=Path(d)/'test';subprocess.run([os.environ.get('SWIFTC','swiftc'),str(Path(__file__).with_name('main.swift')),'-o',str(binary)],check=True);subprocess.run([str(binary)],check=True)

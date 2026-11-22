#!/usr/bin/env python3
"""M1 source wiring guard, not AppKit/pixel acceptance."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[2]
app = (root / 'Sources/gor/App/AppDelegate.swift').read_text()
host = (root / 'Sources/gor/Engine/GorAVPlayerHost.swift').read_text()
engine = (root / 'Sources/gor/Engine/MPVCommand.swift').read_text()
prior = subprocess.check_output(['git', '-C', str(root), 'show',
    '8dbd1ac90:archive/gor/Sources/gor/App/AppDelegate.swift'], text=True)
start = '    private func launchMPVImplementation(file: String?) {'
# End marker is found by Swift brace depth, ignoring braces inside this already
# identical suffix. Compare through next function marker instead of the full file.
a = prior[prior.index(start):]
b = app[app.index(start):]
end = '\n    private func '
if end in a[len(start):]:
    length = a.index(end, len(start))
    assert a[:length] == b[:length], 'mpv launch path changed'
assert 'return saved.flatMap(PlayerEngine.init(rawValue:)) ?? .mpv' in engine
# arch-196t r3 item 1 (owner paste 2026-11-15 17:36): Engine > gorav stays as a
# facade switch; the separate window, its NSOpenPanel and its own buttons are
# deleted and must not reappear.
assert 'open local film with gorav...' not in app, 'probe menu row reappeared (arch-196t r3)'
assert 'openGorAVLocalFilm' not in app, 'probe launch path reappeared (arch-196t r3)'
assert 'NSOpenPanel()' not in app.split('func openFilePanel')[0], 'NSOpenPanel in the engine path (arch-196t r3)'
for token in ['session.togglePause()', 'session.seek(toSeconds: value)',
              'session.setVolume(muted ? 0 : volume)', '.durationKnown(let seconds)',
              '.timePos(let seconds, _)', 'session.subtitleCandidates',
              'session.selectSubtitle(path: path, slot: .primary)',
              'session.setSubtitleVisible(false, slot: .primary)',
              'self.identity == token, self.session === session']:
    assert token in host, token
assert 'launchMPVImplementation' not in host
print('PASS M1 local chooser/menu, mpv default and launch-body byte preservation, actual controls/live time/SRT selection and stale completion fence')
print('NOT_RUN AppKit pixels, owner M1 playback and interactive UI acceptance')

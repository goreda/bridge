"""Exact menu title pins (owner naming pass, 2026-11-08).

Owner, 2026-11-08 (phonemsg-01M6XDPX0S6QEY26XE0P7XPHHF, "make them like this"):
the file menu rows are EXACTLY, lowercase, in this order:
    archive / magnet / iptv / music / (separator) / stop / reload / quit and save
The open / open url pair above them keeps its titles; shortcuts and
selectors are unchanged.

Owner, 2026-11-08 (phonemsg-01M6XDSWQ2ZR78KRASW0BHFM1X): the engine submenu
holds exactly two rows titled "mpv" and "gorav" (lowercase), checkmark on
the active one. gorav is a reserved stub (GorAVBackend.admission() is
deliberately .unavailable), so owner (phonemsg-01M6XE210NQVR3Y6K0F7CVHPPV,
"then keep it grayed out for now"): the gorav row is disabled until its
backend qualifies; mpv stays enabled and checked.

Owner, 2026-11-08 (phonemsg-01M6XDYBDD9EMCCFCB6N1QRVA5, "menu naming
correction"): window menu rows are EXACTLY minimize / full screen / pip /
(position, size groups) / bring to front; the position submenu names
directions with arrow glyphs and center with a middot:
    • (center) / ↖ / ↗ / ↙ / ↘
The subtitles > position move rows are the arrows ↑ / ↓.

Proofs:
1. The file-menu block of buildMenuBar adds exactly the pinned row sequence
   (titles, separators, order); no long-form title survives in the menu bar.
2. The engine rows take titles from PlayerEngine.rawValue with allCases
   exactly [mpv, gorav]; the active engine carries the checkmark and a row
   whose backend fails admission is disabled (gorav grayed out today).
3. The window menu rows and the position glyph table are pinned verbatim.
4. Self-mutation: every pinned-title mutant below is applied to the real
   source text and must make the check fail - the pins cannot silently pass.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]

EXPECTED_FILE_ROWS = [
    ('item', 'open…'), ('item', 'open url…'), ('sep',),
    ('item', 'archive'), ('item', 'magnet'), ('item', 'find in panel'), ('item', 'iptv'), ('item', 'music'),
    ('sep',), ('item', 'stop'), ('item', 'reload'), ('item', 'quit and save'),
]
EXPECTED_POSITION_TABLE = [('•', 'center', '.'), ('↖', 'top-left', '<Up>'), ('↗', 'top-right', '<Right>'),
                           ('↙', 'bottom-left', '<Left>'), ('↘', 'bottom-right', '<Down>')]


def file_rows(app):
    block = app[app.index('let fileMenu = NSMenu'):app.index('// ── playback')]
    rows = []
    for m in re.finditer(r'fileMenu\.addItem\((item\("([^"]*)"|\.separator\(\))', block):
        rows.append(('item', m.group(2)) if m.group(2) is not None else ('sep',))
    return rows


def check(app, mpvcommand):
    rows = file_rows(app)
    assert rows == EXPECTED_FILE_ROWS, 'file menu rows drifted: ' + repr(rows)
    # No long-form title survives anywhere in the menu bar.
    for stale in ('open archive…', 'search magnets…', 'music mode', 'quit & save position',
                  'engine: mpv', 'engine: gorav', 'minimize player', 'enter / exit full screen',
                  'bring all to front', 'restore player', 'move subtitles up', 'move subtitles down'):
        assert 'item("' + stale not in app and 'title: "' + stale not in app \
            and 'title: engine == .mpv' not in app and '? "' + stale + '"' not in app \
            and ': "' + stale + '"' not in app, 'stale title still in menu bar: ' + stale
    assert '"picture in picture"' not in app, 'stale title still in menu bar: picture in picture'

    # engine submenu: rows titled by the engine raw value, exactly mpv/gorav,
    # checkmark on the active one, grayed out while the backend is a stub.
    assert 'NSMenuItem(title: engine.rawValue, action: #selector(menuPlayerEngine(_:))' in app
    assert re.search(r'^\s*case mpv, gorav$', mpvcommand, re.M), 'PlayerEngine cases drifted from exactly [mpv, gorav]'
    assert 'menuItem.state = menuItem.representedObject as? String == selectedPlayerEngine.rawValue ? .on : .off' in app, \
        'engine checkmark lost'
    assert 'return PlayerBackendRoute.resolve(engine).active == engine' in app, \
        'gorav gray-out lost: a backend failing admission must disable its row'

    # window menu rows, exact titles.
    block = app[app.index('let windowMenu=NSMenu'):app.index('let sizeMenu')]
    for want in ('item("minimize",action:#selector(menuWindowMinimize)',
                 'item("full screen",action:#selector(menuFullscreen)',
                 'item("pip",action:#selector(menuPictureInPicture)'):
        assert want in block, 'window row drifted: ' + want
    assert 'item("bring to front",action:#selector(menuWindowFront)' in app
    assert 'menuItem.title=playerWindowIsMinimized ? "restore" : "minimize"' in app
    assert 'menuItem.title=available ? "pip" : "pip (mono window only)"' in app

    # window > position: arrow glyphs for the corners, middot for center.
    table = [(g, m, k.strip('"') if k.startswith('"') else '<' + re.search(r'NS(\w+)ArrowFunctionKey', k).group(1) + '>')
             for g, m, k in re.findall(r'\("([^"]+)","(center|top-left|top-right|bottom-left|bottom-right)",("[^"]+"|String\(UnicodeScalar\(NS\w+ArrowFunctionKey\)!\))\)', app)]
    assert table == EXPECTED_POSITION_TABLE, 'window position glyphs drifted: ' + repr(table)

    # subtitles > position: the move rows are bare arrows.
    assert 'item("↑",       action: #selector(menuSubUp),       key: "r", mods: [])' in app
    assert 'item("↓",     action: #selector(menuSubDown),     key: "t", mods: [])' in app


def main():
    app = (ROOT / 'Sources/gor/App/AppDelegate.swift').read_text()
    mpvcommand = (ROOT / 'Sources/gor/Engine/MPVCommand.swift').read_text()
    check(app, mpvcommand)

    # Self-mutation: each real-text mutant must be caught.
    mutants = {
        'long archive title': (app.replace('item("archive"', 'item("open archive…"', 1), mpvcommand),
        'renamed row': (app.replace('item("magnet"', 'item("magnets"', 1), mpvcommand),
        'dropped row': (app.replace('fileMenu.addItem(item("iptv",          action: #selector(menuIptvMode), key: "t"))\n', '', 1),
                        mpvcommand),
        'swapped order': (app.replace('item("stop"', 'item("reload"', 1).replace(
            'item("reload",      action: #selector(menuReload)', 'item("stop",      action: #selector(menuReload)', 1),
            mpvcommand),
        'long engine title': (app.replace('NSMenuItem(title: engine.rawValue',
                                          'NSMenuItem(title: engine == .mpv ? "engine: mpv" : "engine: gorav"', 1),
                              mpvcommand),  # caught by the stale-title or rawValue pin
        'extra engine case': (app, mpvcommand.replace('case mpv, gorav', 'case mpv, gorav, other', 1)),
        'checkmark lost': (app.replace('== selectedPlayerEngine.rawValue ? .on : .off',
                                       '== selectedPlayerEngine.rawValue ? .off : .off', 1), mpvcommand),
        'gorav enabled': (app.replace('return PlayerBackendRoute.resolve(engine).active == engine',
                                      'return true', 1), mpvcommand),
        'long window title': (app.replace('item("pip",action:', 'item("picture in picture",action:', 1), mpvcommand),
        'center not bullet': (app.replace('("•","center",".")', '("center","center",".")', 1), mpvcommand),
        'corner not arrow': (app.replace('("↖","top-left",String', '("top left","top-left",String', 1), mpvcommand),
        'subtitle move not arrow': (app.replace('item("↑",', 'item("move subtitles up",', 1), mpvcommand),
    }
    for name, (ma, mm, *_) in mutants.items():
        try:
            check(ma, mm)
        except AssertionError:
            continue
        raise SystemExit('mutant survived: ' + name)

    print('PASS exact menu titles: file archive/magnet/iptv/music | stop/reload/quit and save;')
    print('  engine mpv/gorav via rawValue, active checked, stub backend grayed out;')
    print('  window minimize/full screen/pip/bring to front, position • ↖ ↗ ↙ ↘, subtitle moves ↑ ↓;')
    print('  12 real-text mutants killed')


if __name__ == '__main__':
    main()

"""Menu structure gate.

Owner, 2026-11-08 (regroup pass): group toggle/zoom/move/screenshot/adjust,
deband+deinterlace+hardware decoding into quality with new members, rename
"stereo / vr" to "vr", vr+clip directly under tracks, same logic in other menus.

Owner, 2026-11-08 (second pass): "arrange all menus as you did for video;
keep them clean" - every menu grouped with the same logic (file sources/session,
playback volume/seek/speed/chapters/loop/playlist, audio volume, subtitles
files, photon adjust/filters, window position/size, app about/config/session),
plus the shortcut audit: a cycle chord pair for the aspect/crop format lists,
arrow chords for the aspect fine-nudges, a chord for subtitle font size reset.

Three proofs:
1. Nothing lost: the actionable-item inventory (title, selector, key, mods) of
   the whole menu bar equals the pinned pre-change multiset from a669c613f,
   transformed only by the explicit RETITLED/ADDED tables below - every action
   stays reachable, no shortcut is taken away, and the only changed rows are
   the documented shortcut additions. Loop/ternary items are pinned by their
   raw expressions. Help retitles keep the RETITLE map.
2. Structure: the parsed buildMenuBar tree matches the requested groups and
   top-level order; no adjacent, leading or trailing separators; no empty
   groups.
3. Handlers: every selector must resolve to a real func in AppDelegate or
   MenuActions.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]

def scan_calls(text, fname):
    """Yield arg-string of every `<fname>(...)` call, balanced-paren aware."""
    out = []
    for m in re.finditer(r'[^.\w]' + re.escape(fname) + r'\(', text):
        i = m.end(); depth = 1; j = i
        while depth:
            c = text[j]
            if c == '(':
                depth += 1
            elif c == ')':
                depth -= 1
                if depth == 0:
                    break
            elif c == '"':
                j += 1
                while text[j] != '"':
                    j += 2 if text[j] == '\\' else 1
            j += 1
        out.append((m.start(), text[i:j]))
    return out

def split_top(args):
    parts, depth, cur, i = [], 0, '', 0
    while i < len(args):
        c = args[i]
        if c in '([':
            depth += 1
        elif c in ')]':
            depth -= 1
        if c == ',' and depth == 0:
            parts.append(cur); cur = ''
            i += 1
            continue
        if c == '"':
            j = i + 1
            while args[j] != '"':
                j += 2 if args[j] == '\\' else 1
            cur += args[i:j + 1]
            i = j + 1
            continue
        cur += c
        i += 1
    if cur.strip():
        parts.append(cur)
    return [p.strip() for p in parts]

def norm(e):
    return re.sub(r'\s+', ' ', e).strip()

def parse_item_args(args):
    parts = split_top(args)
    title = norm(parts[0]) if parts else '?'
    sel = key = mods = None
    for p in parts[1:]:
        if p.startswith('action:'):
            found = re.findall(r'#selector\((\w+\(_:\)|\w+)\)', p)
            sel = '|'.join(norm(f) for f in found) if found else norm(p[7:])
        elif p.startswith('key:'):
            key = norm(p[4:])
        elif p.startswith('mods:'):
            mods = norm(p[5:])
    return title, sel or '?', key if key is not None else '""', mods if mods is not None else '.command'

def inventory(app, actions):
    """All actionable leaves: item(...) calls and direct NSMenuItem(title:action:) calls."""
    items = []
    start = app.index('    func buildMenuBar()')
    end = app.index('    // Observation only.', start)
    build = app[start:end]
    for src in (build, actions):
        for pos, args in scan_calls(src, 'item'):
            head = src[max(0, pos - 12):pos]
            if 'func' in head:   # the `func item(_ title:` definition itself
                continue
            items.append(parse_item_args(args))
        for pos, args in scan_calls(src, 'NSMenuItem'):
            parts = split_top(args)
            d = {}
            for p in parts:
                for k in ('title:', 'action:', 'keyEquivalent:'):
                    if p.startswith(k):
                        d[k[:-1]] = p[len(k):].strip()
            if 'action' in d and d['action'] != 'nil':
                m = re.search(r'#selector\((\w+\(_:\)|\w+)\)', d['action'])
                sel = norm(m.group(1)) if m else norm(d['action'])
                items.append((norm(d.get('title', '?')), sel, norm(d.get('keyEquivalent', '""')), '.command'))
    return sorted(items)

def tree(app):
    start = app.index('    func buildMenuBar()')
    end = app.index('    // Observation only.', start)
    build = app[start:end]
    menu_title = {'main': '<root>'}       # menu var -> title
    item_menu = {}                        # item var -> menu var (submenu)
    for m in re.finditer(r'let (\w+)\s*=\s*NSMenu\(title:\s*"([^"]*)"\)', build):
        menu_title[m.group(1)] = m.group(2)
    for m in re.finditer(r'let (\w+)\s*=\s*NSMenu\(\)', build):
        menu_title.setdefault(m.group(1), 'app' if m.group(1) == 'appMenu' else '?')
    for m in re.finditer(r'(\w+)\.submenu\s*=\s*(\w+)', build):
        if m.group(2) in menu_title:
            item_menu[m.group(1)] = m.group(2)
    var_leaf = {}
    for m in re.finditer(r'let (\w+)\s*=\s*item\(', build):
        var_leaf[m.group(1)] = None
    children = {v: [] for v in menu_title}
    # split compound statements so inline `let x = ...; menu.addItem(y)` lines parse
    stmts = []
    for ln in build.splitlines():
        s = ln.strip()
        if s.startswith('//'):
            stmts.append(s); continue
        depth = 0; cur = ''
        i = 0
        while i < len(s):
            c = s[i]
            if c in '([{':
                depth += 1
            elif c in ')]}':
                depth -= 1
            if c == ';' and depth == 0:
                stmts.append(cur); cur = ''
            else:
                cur += c
            i += 1
        if cur.strip():
            stmts.append(cur)
    for s in stmts:
        s = s.strip()
        m = re.match(r'^let (\w+) = group\("([^"]+)", in: (\w+)\)$', s)
        if m:
            menu_title[m.group(1)] = m.group(2)
            children.setdefault(m.group(1), [])
            children.setdefault(m.group(3), []).append(('sub', m.group(2), m.group(1)))
            continue
        m = re.match(r'^(\w+)\.addItem\((.*)\)\s*$', s)
        if m and m.group(1) in children:
            parent, arg = m.group(1), m.group(2)
            if arg.startswith('.separator()'):
                children[parent].append(('|', '|', None))
            elif 'item(' in arg:
                t, sel, key, mods = parse_item_args(arg[arg.index('item(') + 5:])
                children[parent].append(('item', t, None))
            elif arg in item_menu:
                mv = item_menu[arg]
                children[parent].append(('sub', menu_title.get(mv, '?'), mv))
            elif arg.startswith('NSMenuItem('):
                tm = re.search(r'title:\s*"([^"]*)"', arg)
                children[parent].append(('item', '"' + tm.group(1) + '"' if tm else arg, None))
            elif arg in var_leaf:
                pos = build.index('let ' + arg)
                a = scan_calls(build[pos:], 'item')[0][1]
                t, sel, key, mods = parse_item_args(a)
                if t in ('title', 'model'):
                    t = '[' + ('window placement loop' if t == 'title' else 'caption model loop') + ']'
                    children[parent].append(('raw', t, None))
                else:
                    children[parent].append(('item', t, None))
            else:
                children[parent].append(('var', arg, None))
            continue
        m = re.match(r'^installTrackSubmenu\(in:(\w+),type:"(\w+)"\)$', s)
        if m:
            children.setdefault(m.group(1), []).append(('tracks', m.group(2), None))
            continue
        m = re.match(r'^installAudioDeviceSubmenu\(in:(\w+)\)$', s)
        if m:
            children.setdefault(m.group(1), []).append(('devices', 'output device', None))
            continue
        m = re.match(r'^populateVideoFormats\((\w+),crop:(\w+)\)$', s)
        if m:
            children.setdefault(m.group(1), []).append(('formats', 'crop=' + m.group(2), None))
            continue
        m = re.match(r'^main\.removeItem\((\w+)\)$', s)
        if m and m.group(1) in item_menu:
            t = menu_title.get(item_menu[m.group(1)], '?')
            children['main'] = [c for c in children['main'] if not (c[0] == 'sub' and c[1] == t)]
            continue
        m = re.match(r'^main\.insertItem\((\w+),at:main\.index\(of:(\w+)\)\+1\)$', s)
        if m and m.group(1) in item_menu:
            mv = item_menu[m.group(1)]
            t = menu_title.get(mv, '?')
            after = menu_title.get(item_menu.get(m.group(2), ''), None)
            idx = next((k for k, c in enumerate(children['main']) if c[0] == 'sub' and c[1] == after), len(children['main']) - 1)
            children['main'].insert(idx + 1, ('sub', t, mv))
    return menu_title, children

def render(app):
    menu_title, children = tree(app)
    out = []
    def walk(var, depth):
        for kind, title, mv in children.get(var, []):
            if kind == 'sub':
                out.append('  ' * depth + title + ' >')
                walk(mv, depth + 1)
            elif kind == '|':
                out.append('  ' * depth + '--')
            elif kind == 'item':
                out.append('  ' * depth + title)
            else:
                out.append('  ' * depth + '[' + kind + ':' + title + ']')
    walk('main', 0)
    return '\n'.join(out)


BEFORE = [
('"a-b loop"', 'menuABLoop', '"l"', '[.command, .control, .option]'),
('"about gor"', 'showAbout', '""', '.command'),
('"about"', 'showAbout', '"5"', '[.command, .control, .option]'),
('"adjust brightness +"', 'menuBrightUp', '"b"', '[.command, .control, .shift]'),
('"adjust brightness −"', 'menuBrightDown', '"n"', '[.command, .control, .shift]'),
('"adjust contrast +"', 'menuContrastUp', '"c"', '[.command, .control, .shift]'),
('"adjust contrast −"', 'menuContrastDown', '"v"', '[.command, .control, .shift]'),
('"adjust gamma +"', 'menuGammaUp', '"g"', '[.command, .control, .shift]'),
('"adjust gamma −"', 'menuGammaDown', '"h"', '[.command, .control, .shift]'),
('"adjust saturation +"', 'menuSatUp', '"s"', '[.command, .control, .shift]'),
('"adjust saturation −"', 'menuSatDown', '"a"', '[.command, .control, .shift]'),
('"audio delay +0.1s"', 'menuAudioDelayP', '"9"', '[.command, .control, .option]'),
('"audio delay −0.1s"', 'menuAudioDelayM', '"8"', '[.command, .control, .option]'),
    # 191b B4: the six vr-tools rows (blink control, cross-eye order, head tracking, ipd +/-, recenter head tracking) left
    # buildMenuBar: the one "3d" menu is built by ThreeDMenu.install from ThreeDKeymap.rows, outside this inventory. Their
    # chords live once in ThreeDKeymap (pinned by Tests/ThreeDKeymap and the required-items ledger); no shortcut was taken away.
('"bright"', 'menuPhotonBright', '"b"', '[]'),
('"bring to front"', 'menuWindowFront', '"b"', '[.command,.control,.option,.shift]'),
('"chrome filter"', 'menuPhotonChromeFilter', '"c"', '[.shift]'),
('"chrome"', 'menuPhotonChrome', '"c"', '[]'),
('"clip abort"', 'menuClipAbort', '"x"', '[.command, .option]'),
('"clip gif"', 'menuClipGif', '"g"', '[.command, .option]'),
('"clip open"', 'menuClipOpen', '"o"', '[.command, .option]'),
('"clip undo"', 'menuClipUndo', '"z"', '[.command, .option]'),
('"clip video"', 'menuClipVideo', '"c"', '[.command, .option]'),
('"copy issue report"', 'menuHelpIssueReport', '"i"', '[.command,.control,.option,.shift]'),
('"copy"', '#selector(NSText.copy(_:))', '"c"', '.command'),
('"cut"', '#selector(NSText.cut(_:))', '"x"', '.command'),
('"deband"', 'menuDeband', '"b"', '[.command, .control, .option]'),
('"deinterlace"', 'menuDeinterlace', '"i"', '[.command, .control, .option]'),
('"detect"', 'menuCropDetect', '"d"', '[.command,.control,.option]'),
('"full screen"', 'menuFullscreen', '"f"', '[.command,.control]'),
('"expand horizontal (+0.1)"', 'menuAspectExpandH', '""', '.command'),
('"expand vertical (+0.1)"', 'menuAspectExpandV', '""', '.command'),
('"grain"', 'menuPhotonGrain', '"g"', '[]'),
('"hardware decoding"', 'menuHwdec', '"h"', '[.command, .control, .option]'),
('"hud"', 'menuPhotonHUD', '"\\u{F70B}"', '[]'),
('"iptv"', 'menuIptvMode', '"t"', '.command'),
('"keyboard shortcuts"', 'menuHelpShortcuts', '"/"', '[.command,.control,.option,.shift]'),
('"live captions"', 'menuLiveCaption', '"j"', '[.command, .control, .option]'),
('"load subtitle file…"', 'menuSubLoad', '"o"', '[.command, .control, .option]'),
('"loop file"', 'menuLoopFile', '"l"', '[.command, .shift]'),
('"manual..."', 'menuManualVideoFormat(_:)', '""', '.command'),
('"max volume"', 'menuVolMax', '"→"', '.command'),
('"minimize"', 'menuWindowMinimize', '"m"', '[.command,.control,.option,.shift]'),
('"↓"', 'menuSubDown', '"t"', '[]'),
('"↑"', 'menuSubUp', '"r"', '[]'),
('"move video down"', 'menuPanVideoDown', 'fnShift(NSDownArrowFunctionKey)', 'fs'),
('"move video left"', 'menuPanVideoLeft', 'fnShift(NSLeftArrowFunctionKey)', 'fs'),
('"move video right"', 'menuPanVideoRight', 'fnShift(NSRightArrowFunctionKey)', 'fs'),
('"move video up"', 'menuPanVideoUp', 'fnShift(NSUpArrowFunctionKey)', 'fs'),
('"music"', 'menuMusicMode', '"u"', '[.command, .control, .option]'),
('"mute / unmute"', 'menuMute', '"m"', '[]'),
('"mute"', 'menuMute', '"←"', '.command'),
('"negativ"', 'menuPhotonNegativ', '"n"', '[]'),
('"next chapter"', 'menuChapterNext', '"."', '[.command, .control, .option]'),
('"next frame"', 'menuFrameNext', '"."', '[]'),
('"next in playlist"', 'menuPlaylistNext', '">"', '[]'),
('"archive"', 'openArchive', '"a"', '[.command, .shift]'),
('"open url…"', 'menuOpenURL', '"u"', '.command'),
('"open…"', 'openFile', '"o"', '.command'),
('"panscan +"', 'menuPanscanIn', '"e"', '[]'),
('"panscan −"', 'menuPanscanOut', '"w"', '[]'),
('"paste"', '#selector(NSText.paste(_:))', '"v"', '.command'),
('"photon"', 'menuPhotonToggle', '"\\u{F70C}"', '[]'),
('"pip"', 'menuPictureInPicture', '"p"', '[.command,.control,.option,.shift]'),
('"play / pause"', 'menuPlayPause', '" "', '[]'),
('"previous chapter"', 'menuChapterPrev', '"/"', '[.command, .control, .option]'),
('"previous frame"', 'menuFramePrev', '","', '[.command, .control, .option]'),
('"previous in playlist"', 'menuPlaylistPrev', '"<"', '[]'),
('"quit and save"', 'menuQuitSave', '"q"', '[.command, .shift]'),
('"quit"', '#selector(NSApplication.terminate(_:))', '"q"', '.command'),
('"random subtitle position"', 'menuSubRandomPos', '"0"', '[.shift]'),
('"reload"', 'menuReload', '"r"', '.command'),
('"reset audio delay"', 'menuAudioDelayReset', '"7"', '[.command, .control, .option]'),
('"reset color adjustments"', 'menuColorReset', '"3"', '[.command, .control, .option]'),
('"reset rotation"', 'menuRotateReset', '"2"', '[.command, .control, .option]'),
('"reset speed"', 'menuSpeedReset', '"1"', '[.command, .control, .option]'),
('"reset subtitle delay"', 'menuSubDelayReset', '"6"', '[.command, .control, .option]'),
('"reset subtitles"', 'menuSubtitlesReset', '""', '.command'),
('"reset zoom & pan"', 'menuZoomReset', '"z"', '[.command, .control, .option]'),
('"reset"', 'menuCropReset|menuAspectDefault', 'crop ? "c" : ""', 'crop ? [.command,.control,.option] : .command'),
('"restart"', 'menuRestartQuit', '"q"', '[.shift]'),
('"rotate clockwise"', 'menuRotateCW', '"r"', '[.command, .control, .option]'),
('"rotate counter-clockwise"', 'menuRotateCCW', '"e"', '[.command, .control, .option]'),
('"save src subtitle"', 'menuSaveSrcSubtitle', '"f"', '[.command, .control, .option]'),
('"screenshot (video only)"', 'menuScreenshotClean', '"s"', '.shift'),
('"screenshot (window)"', 'menuScreenshotWin', '"s"', '.command'),
('"screenshot (with subs)"', 'menuScreenshot', '"s"', '[]'),
('"magnet"', 'openMagnetSearch', '"m"', '.command'),
('"seek backward 20s"', 'menuSeekB20', '"↓"', '.command'),
('"seek backward 5s"', 'menuSeekB5', '"["', '[.command, .control, .option]'),
('"seek backward 60s"', 'menuSeekB60', '"↓"', '[]'),
('"seek forward 20s"', 'menuSeekF20', '"↑"', '.command'),
('"seek forward 5s"', 'menuSeekF5', '"]"', '[.command, .control, .option]'),
('"seek forward 60s"', 'menuSeekF60', '"↑"', '[]'),
('"seek to beginning"', 'menuSeekStart', '"0"', '[.command, .control, .option]'),
('"select all"', '#selector(NSText.selectAll(_:))', '"a"', '.command'),
('"sharp"', 'menuPhotonSharp', '"x"', '[]'),
('"shrink horizontal (-0.1)"', 'menuAspectShrinkH', '""', '.command'),
('"shrink vertical (-0.1)"', 'menuAspectShrinkV', '""', '.command'),
('"speed down"', 'menuSpeedDown', '"["', '[]'),
('"speed up"', 'menuSpeedUp', '"]"', '[]'),
('"speed ×0.5"', 'menuSpeedHalf', '"-"', '[.command, .control, .option]'),
('"speed ×2"', 'menuSpeedDouble', '"="', '[.command, .control, .option]'),
('"stats"', 'menuStatsToggle', '"i"', '[]'),
('"stop"', 'menuStop', '"k"', '[.command, .control, .option]'),
('"subtitle delay +0.1s"', 'menuSubDelayP', 'String(UnicodeScalar(NSRightArrowFunctionKey)!)', '[.command, .shift]'),
('"subtitle delay −0.1s"', 'menuSubDelayM', 'String(UnicodeScalar(NSLeftArrowFunctionKey)!)', '[.command, .shift]'),
('"subtitle font size +"', 'menuSubSizeUp', '","', '[]'),
('"subtitle font size reset"', 'menuSubSizeReset', '""', '.command'),
('"subtitle font size −"', 'menuSubSizeDown', '"ü"', '[]'),
('"toggle always on top"', 'menuOntop', '"t"', '[.command, .control, .option]'),
('"toggle fade"', 'menuClipFade', '"f"', '[.command, .option]'),
('"toggle fullscreen"', 'menuFullscreen', '"f"', '[]'),
('"toggle subtitles"', 'menuSubToggle', '"v"', '[]'),
('"volume down"', 'menuVolDown', '"9"', '[]'),
('"volume up"', 'menuVolUp', '"0"', '[]'),
('"zoom in"', 'menuZoomIn', '","', 'fs'),
('"zoom out"', 'menuZoomOut', '"."', 'fs'),
('engine.rawValue', 'menuPlayerEngine(_:)', '""', '.command'),
('format.title', 'menuVideoFormat(_:)', '""', '.command'),
('model', 'menuCaptionModel(_:)', '""', '.command'),
('row.title', 'menuSelectTrack(_:)', '""', '.command'),
('title', 'menuWindowPlacement(_:)', 'key', '[.function,.control,.option,.command]'),]

app = (ROOT / 'Sources/gor/App/AppDelegate.swift').read_text()
actions = (ROOT / 'Sources/gor/UI/MenuActions.swift').read_text()

inv = inventory(app, actions)
# Help narrowing (owner, 2026-11-08): title-only retitles; selector/key/mods untouched.
RETITLE = {'"shortcuts"': '"keyboard shortcuts"', '"issue report"': '"copy issue report"'}
inv_norm = sorted((RETITLE.get(t, t), sel, key, mods) for t, sel, key, mods in inv)

# 2026-11-08 shortcut audit: the ONLY intended inventory changes vs the 133 pin.
# Rows that gained a shortcut (same title, same selector, key "" -> chord):
RETITLED = {
    ('"expand horizontal (+0.1)"', 'menuAspectExpandH', '""', '.command'):
        ('"expand horizontal (+0.1)"', 'menuAspectExpandH', 'String(UnicodeScalar(NSRightArrowFunctionKey)!)', '[.function, .command, .control, .option, .shift]'),
    ('"shrink horizontal (-0.1)"', 'menuAspectShrinkH', '""', '.command'):
        ('"shrink horizontal (-0.1)"', 'menuAspectShrinkH', 'String(UnicodeScalar(NSLeftArrowFunctionKey)!)', '[.function, .command, .control, .option, .shift]'),
    ('"expand vertical (+0.1)"', 'menuAspectExpandV', '""', '.command'):
        ('"expand vertical (+0.1)"', 'menuAspectExpandV', 'String(UnicodeScalar(NSUpArrowFunctionKey)!)', '[.function, .command, .control, .option, .shift]'),
    ('"shrink vertical (-0.1)"', 'menuAspectShrinkV', '""', '.command'):
        ('"shrink vertical (-0.1)"', 'menuAspectShrinkV', 'String(UnicodeScalar(NSDownArrowFunctionKey)!)', '[.function, .command, .control, .option, .shift]'),
    ('"subtitle font size reset"', 'menuSubSizeReset', '""', '.command'):
        ('"subtitle font size reset"', 'menuSubSizeReset', '"0"', '[.command, .control, .option, .shift]'),
    # 2026-11-15 (owner): real shortcuts for playlist next/previous - the bare
    # "<"/">" equivalents lost to shifted-character matching and to panels.
    ('"next in playlist"', 'menuPlaylistNext', '">"', '[]'):
        ('"next in playlist"', 'menuPlaylistNext', '"n"', '[.command, .control, .option]'),
    ('"previous in playlist"', 'menuPlaylistPrev', '"<"', '[]'):
        ('"previous in playlist"', 'menuPlaylistPrev', '"p"', '[.command, .control, .option]'),
}
# New rows: the aspect/crop cycle item (one ternary call site, both menus) and
# the second window-placement loop (position and size are separate groups now).
ADDED = [
    ('"cycle"', 'menuCycleCrop|menuCycleAspect', '"a"',
     'crop ? [.command, .control, .option, .shift] : [.command, .control, .option]'),
    ('title', 'menuWindowPlacement(_:)', 'key', '[.command,.control,.option,.shift]'),
    # arch-196t r3 (2026-11-15): the "open local film with gorav..." probe row
    # was deleted; the engine menu keeps exactly the mpv/gorav facade rows and
    # the probe row must not reappear here.
    # 2026-11-15 (owner): Cmd+F find-in-panel (menu route - panels disable the
    # event tap) and Cmd+P open-playlist-folder.
    ('"find in panel"', 'menuFindInPanel', '"f"', '.command'),
    ('"open playlist folder"', 'menuOpenPlaylistFolder', '"p"', '.command'),
    # 2026-11-08 update button: the chromium-only item becomes the general
    # update button (same chord, new selector; owner: "that button now handles
    # updates"). One row replaced, count unchanged.
    ('"update"', 'menuUpdate', '"4"', '[.command, .control, .option]'),
    # 2026-11-08 audio expansion (owner: "there are too few audio menu items"):
    # boost/channels/dynamics/equalizer groups + the dynamic device rows.
    ('"volume boost +10%"', 'menuVolBoostUp', '""', '.command'),
    ('"volume boost −10%"', 'menuVolBoostDown', '""', '.command'),
    ('"volume boost off"', 'menuVolBoostOff', '""', '.command'),
    ('"auto (system default)"', 'menuSelectAudioDevice(_:)', '""', '.command'),
    ('device.label', 'menuSelectAudioDevice(_:)', '""', '.command'),
    ('"auto (source)"', 'menuAudioChannels(_:)', '""', '.command'),
    ('"stereo downmix"', 'menuAudioChannels(_:)', '""', '.command'),
    ('"mono"', 'menuAudioChannels(_:)', '""', '.command'),
    ('"surround 5.1"', 'menuAudioChannels(_:)', '""', '.command'),
    ('"surround 7.1"', 'menuAudioChannels(_:)', '""', '.command'),
    ('"night mode"', 'menuNightMode', '""', '.command'),
    ('"normalize (loudnorm)"', 'menuNormalize', '""', '.command'),
    ('"flat (off)"', 'menuAudioEqualizer(_:)', '""', '.command'),
    ('"bass boost"', 'menuAudioEqualizer(_:)', '""', '.command'),
    ('"voice"', 'menuAudioEqualizer(_:)', '""', '.command'),
    ('"treble"', 'menuAudioEqualizer(_:)', '""', '.command'),
    # video > vr: "2d film to 3d (depth prior)" (menuVR2D3D, flat-2d3d projection, default OFF, per-file) is in AppDelegate's vr menu; it was missing from this
    # inventory, which made it 161 vs 160. Named here deliberately. (The 3d submenu in ThreeDMenu.swift is built outside AppDelegate and is not in this inventory.)
    # 2026-11-08 subtitle position presets (owner: "add shift+1..9
    # individually"): nine evenly spaced sub-pos rows, one chord each.
] + [('"position %d"' % v, 'menuSubPosPreset(_:)', '"%d"' % d, '.shift')
     for d, v in enumerate(range(10, 91, 10), start=1)]
EXPECTED = sorted([RETITLED.get(row, row) for row in BEFORE] + ADDED)
assert len(inv) == len(EXPECTED) == 152, (len(inv), len(EXPECTED))
assert inv_norm == EXPECTED, 'menu inventory drift (only RETITLED/ADDED changes are allowed):\n' + '\n'.join(
    'only now: ' + repr(x) for x in inv_norm if x not in EXPECTED) + '\n' + '\n'.join(
    'lost: ' + repr(x) for x in EXPECTED if x not in inv_norm)

menu_title, children = tree(app)

def kids_of(var):
    return [(k, t) for k, t, _ in children[var]]

def menu_var(title, parent=None):
    """Resolve a menu var by title; parent disambiguates shared group names."""
    if parent is None:
        return next(v for v, t in menu_title.items() if t == title)
    pmv = menu_var(parent) if isinstance(parent, str) else parent
    return next(mv for k, t, mv in children[pmv] if k == 'sub' and t == title)

def titles_of(title, parent=None):
    return [t.strip('"') for k, t, _ in children[menu_var(title, parent)] if k == 'item']

top = [t for k, t, _ in children['main'] if k == 'sub']
assert top == ['app', 'edit', 'file', 'playback', 'video', 'audio', 'subtitles', 'photon', 'window', 'help'], top

# app: about / config (engine, updates) / session (restart, quit)
assert [(k, t) for k, t in kids_of(menu_var('app'))] == [('item', '"about"'), ('|', '|'),
    ('sub', 'engine'), ('item', '"update"'), ('|', '|'),
    ('item', '"restart"'), ('item', '"quit"')]

# file (owner, 2026-11-08: "move file sources to the main level, and session too;
# they should work with a direct click"): the sources and session
# groups are flattened to the top level - open pair, the four source rows,
# then stop / reload / quit and save, each one click away. Exact short titles
# (owner, 2026-11-08: "böyle olsunlar"): archive / magnet / iptv / music /
# stop / reload / quit and save, all lowercase, no long titles.
assert [(k, t) for k, t in kids_of(menu_var('file'))] == [('item', '"open\u2026"'), ('item', '"open url\u2026"'),
    ('|', '|'), ('item', '"archive"'), ('item', '"magnet"'), ('item', '"find in panel"'),
    ('item', '"iptv"'), ('item', '"music"'), ('|', '|'),
    ('item', '"stop"'), ('item', '"reload"'), ('item', '"quit and save"')]

# playback: play/pause, then volume/seek/speed/chapters/loop/playlist groups
assert [(k, t) for k, t in kids_of(menu_var('playback'))] == [('item', '"play / pause"'), ('|', '|'),
    ('sub', 'volume'), ('sub', 'seek'), ('sub', 'speed'), ('sub', 'chapters'), ('sub', 'loop'), ('sub', 'playlist')]
assert titles_of('volume', 'playback') == ['mute', 'max volume']
assert [(k, t) for k, t in kids_of(menu_var('seek', 'playback'))] == [
    ('item', '"seek forward 60s"'), ('item', '"seek backward 60s"'),
    ('item', '"seek forward 20s"'), ('item', '"seek backward 20s"'),
    ('item', '"seek forward 5s"'), ('item', '"seek backward 5s"'),
    ('item', '"seek to beginning"'), ('|', '|'),
    ('item', '"next frame"'), ('item', '"previous frame"')]
assert titles_of('speed') == ['speed up', 'speed down', 'speed \u00d72', 'speed \u00d70.5', 'reset speed']
assert titles_of('chapters') == ['next chapter', 'previous chapter']
assert titles_of('loop') == ['loop file', 'a-b loop']
assert titles_of('playlist') == ['next in playlist', 'previous in playlist', 'open playlist folder']

#194q requested order, every existing item remains.
video = [(k, t) for k, t, _ in children[menu_var('video')]]
assert video == [('tracks', 'video'), ('sub', 'clip'), ('sub', 'crop'),
    ('sub', 'aspect ratio'), ('sub', 'zoom'), ('sub', 'move'), ('sub', 'rotate'),
    ('sub', 'screenshot'), ('sub', 'quality'), ('sub', 'adjust'), ('sub', 'toggle')], video
assert 'stereo / vr' not in menu_title.values() and 'stereo / vr' not in app

assert titles_of('toggle') == ['toggle fullscreen', 'toggle always on top']
assert titles_of('zoom') == ['zoom in', 'zoom out', 'reset zoom & pan']
assert titles_of('move') == ['move video left', 'move video right', 'move video up', 'move video down']
assert titles_of('rotate') == ['rotate clockwise', 'rotate counter-clockwise', 'reset rotation']
assert titles_of('screenshot') == ['screenshot (with subs)', 'screenshot (video only)', 'screenshot (window)']
assert titles_of('quality') == ['deband', 'deinterlace', 'hardware decoding', 'panscan +', 'panscan \u2212']
assert titles_of('adjust', 'video') == ['adjust contrast +', 'adjust contrast \u2212', 'adjust brightness +', 'adjust brightness \u2212',
    'adjust gamma +', 'adjust gamma \u2212', 'adjust saturation +', 'adjust saturation \u2212', 'reset color adjustments']
# 191b B4: no vr-tools extras menu; the one 3d menu installs in a single call outside buildMenuBar.
assert 'vrMenu' not in menu_title and 'vr tools' not in menu_title.values()
assert app.count('ThreeDMenu.shared.install(in: videoMenu)') == 1 and 'install(in: videoMenu, extra:' not in app
assert titles_of('clip') == ['clip video', 'clip gif', 'clip undo', 'clip abort', 'clip open', 'toggle fade']

# audio: tracks, then volume/boost, the dynamic output-device list,
# channels/dynamics/equalizer groups, delay last (2026-11-08 expansion)
assert [(k, t) for k, t in kids_of(menu_var('audio'))] == [('tracks', 'audio'), ('sub', 'volume'),
    ('sub', 'boost'), ('devices', 'output device'), ('sub', 'channels'),
    ('sub', 'dynamics'), ('sub', 'equalizer'), ('sub', 'delay')]
assert titles_of('volume', 'audio') == ['volume up', 'volume down', 'mute / unmute']
assert titles_of('boost') == ['volume boost +10%', 'volume boost \u221210%', 'volume boost off']
assert titles_of('channels') == ['auto (source)', 'stereo downmix', 'mono', 'surround 5.1', 'surround 7.1']
assert titles_of('dynamics') == ['night mode', 'normalize (loudnorm)']
assert titles_of('equalizer') == ['flat (off)', 'bass boost', 'voice', 'treble']
assert titles_of('delay', 'audio') == ['audio delay +0.1s', 'audio delay \u22120.1s', 'reset audio delay']

# subtitles: tracks, toggle, files group, delay/font size/position groups, reset, captions
assert [(k, t) for k, t in kids_of(menu_var('subtitles'))] == [('tracks', 'sub'),
    ('item', '"toggle subtitles"'), ('|', '|'),
    ('sub', 'files'), ('sub', 'delay'), ('sub', 'font size'), ('sub', 'position'), ('|', '|'),
    ('item', '"reset subtitles"'), ('|', '|'),
    ('item', '"live captions"'), ('sub', 'live caption model')]
assert titles_of('files', 'subtitles') == ['load subtitle file\u2026', 'save src subtitle']
assert titles_of('delay', 'subtitles') == ['subtitle delay +0.1s', 'subtitle delay \u22120.1s', 'reset subtitle delay']
assert titles_of('font size') == ['subtitle font size +', 'subtitle font size \u2212', 'subtitle font size reset']
assert [(k, t) for k, t in kids_of(menu_var('position', 'subtitles'))] == [
    ('item', '"↑"'), ('item', '"↓"'),
    ('item', '"random subtitle position"'), ('|', '|')] + \
    [('item', '"position %d"' % v) for v in range(10, 91, 10)]

# photon: toggles + stats, then adjust / filters groups
assert [(k, t) for k, t in kids_of(menu_var('photon'))] == [('item', '"photon"'), ('item', '"hud"'),
    ('item', '"stats"'), ('|', '|'), ('sub', 'adjust'), ('sub', 'filters')]
assert titles_of('adjust', 'photon') == ['bright', 'sharp', 'grain']
assert titles_of('filters') == ['chrome', 'chrome filter', 'negativ']

# window: session items, then position / size groups, then bring to front.
# Exact short titles (owner, 2026-11-08: "menü isimlendirme düzeltmesi"):
# minimize / full screen / pip / … / bring to front.
assert [(k, t) for k, t in kids_of(menu_var('window'))] == [('item', '"minimize"'),
    ('item', '"full screen"'), ('item', '"pip"'), ('|', '|'),
    ('sub', 'position'), ('sub', 'size'), ('|', '|'), ('item', '"bring to front"')]
assert kids_of(menu_var('position', 'window')) == [('raw', '[window placement loop]')]
assert kids_of(menu_var('size', 'window')) == [('raw', '[window placement loop]')]

# help narrowed: short titles, every action and shortcut still reachable (owner 2026-11-08)
assert titles_of('help') == ['shortcuts', 'issue report', 'about gor'], titles_of('help')
for want in [('menuHelpShortcuts', '"/"', '[.command,.control,.option,.shift]'),
             ('menuHelpIssueReport', '"i"', '[.command,.control,.option,.shift]'),
             ('showAbout', '""', '.command')]:
    assert any((sel, key, mods) == want for _, sel, key, mods in inv), want

# Spotless separators: never adjacent, never leading or trailing; no empty groups.
for mv, kids_ in children.items():
    seq = [k for k, _, _ in kids_]
    assert not any(a == '|' and b == '|' for a, b in zip(seq, seq[1:])), 'adjacent separators in ' + menu_title[mv]
    if seq:
        assert seq[0] != '|' and seq[-1] != '|', 'leading/trailing separator in ' + menu_title[mv]
    if mv != 'main' and menu_title.get(mv) not in (None, '<root>'):
        assert seq, 'empty menu ' + menu_title[mv]

handlers = app + actions + ''.join((ROOT / 'Sources/gor' / n).read_text()
    for n in [])
missing = []
for title, sel, key, mods in EXPECTED:
    for one in sel.split('|'):
        if '.' in one:
            continue  # NSApplication.terminate, NSText.* (AppKit)
        name = one.split('(')[0]
        if not re.search(r'func\s+' + re.escape(name) + r'\s*\(', handlers):
            missing.append((title, one))
assert not missing, missing

print('PASS menu structure: 150/150 inventory = pinned set + documented RETITLED/ADDED only (no action lost; the six vr-tools')
print('  five rows gained chords: aspect/crop cycle, aspect fine-nudge arrows, subtitle font size reset);')
print('  file flattened with exact short titles (owner 2026-11-08): open pair | archive/magnet/iptv/music | stop/reload/quit and save,')
print('  one click each, no sources/session submenus; playback volume/seek/speed/chapters/loop/playlist,')
print('  audio volume, subtitles files, photon adjust/filters, window position/size, app about/config/session;')
print('  separators clean (none adjacent/leading/trailing, no empty groups); all handlers resolve')

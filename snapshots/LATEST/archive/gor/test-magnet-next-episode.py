#!/usr/bin/env python3
"""Item: after a picked series episode plays to its end, the reopened
magnet search bar offers the next episode (s03e03 -> s03e04).

The magnet panel and its controller are discarded on every pick
(close -> stop -> magnetBrowser = nil) and rebuilt on the next Cmd+M, so
the armed advance lives in the AppDelegate-owned MagnetEpisodeTracker:
bound to the picked query snapshot and to the one media the pick started
(torrent stream on port 2222 whose started source is AppDelegate's
lastMagnetURL). A new query or any other media starting first
invalidates it; only the adopted media reaching its own EOF arms it.

Structural checks on the wiring plus a Python port of the tag matcher
and of the tracker state machine (replicated logic), including the real
pick -> close -> stop -> nil -> stream -> EOF -> new panel sequence. The
real Swift types are compiled and executed through the same sequence by
test-magnet-episode-swift.py.

Linux: RUN. Mac/AppKit: NOT_RUN.
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
MB = os.path.join(HERE, "Sources", "gor", "MagnetBrowser.swift")
AD = os.path.join(HERE, "Sources", "gor", "AppDelegate.swift")
PP = os.path.join(HERE, "Sources", "gor", "PPController.swift")

fails = []
def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + (" - " + detail if detail else ""))
    if not ok:
        fails.append(name)

mb = open(MB, encoding="utf-8").read()
ad = open(AD, encoding="utf-8").read()
pp = open(PP, encoding="utf-8").read()

check("MagnetSeriesQuery defined", "enum MagnetSeriesQuery" in mb)
enum = mb[mb.index("enum MagnetSeriesQuery"):]
enum = enum[:enum.index("\n}")]
check("series logic is import-free (no regex/Foundation)",
      "NSRegularExpression" not in enum and "import " not in enum)
check("tracker defined", "struct MagnetEpisodeTracker" in mb)
check("arm carries the picked query snapshot and source",
      "struct Armed { let query: String; let source: String; var adopted = false }" in mb)
check("adoption gated on the torrent stream predicate",
      "static func isTorrentStream(_ path: String) -> Bool" in mb
      and 'url.scheme == "http" && url.port == 2222' in mb)
check("adoption gated on the started source", "startedSource == a.source" in mb)
check("only the adopted media finishing arms the advance", "advanceQuery = a.query" in mb)
check("tracker lives on AppDelegate",
      "var magnetEpisodeTracker = MagnetEpisodeTracker()" in ad)
check("pick arms the tracker before the panel closes",
      "app.magnetEpisodeTracker.pick(query: queryText, source: magnet)" in mb)
check("panel keeps no arm state of its own",
      "armedPick" not in mb and "advanceQuery = nil\n        armedPick" not in mb)
check("controller stop no longer clears the arm", "noteStopped" not in mb)
check("open prefills from the tracker",
      "field.stringValue = (NSApp.delegate as? AppDelegate)?.magnetEpisodeTracker.prefill(fallback: queryText) ?? queryText" in mb)
check("commit consumes the advance on the tracker",
      "app.magnetEpisodeTracker.noteQueryCommitted()" in mb)
check("player media starts reach the tracker with the started source",
      "app.magnetEpisodeTracker.noteMediaStarted(path: path, startedSource: app.lastMagnetURL)" in pp)
check("player EOF edge notifies the tracker with the path",
      "app.magnetEpisodeTracker.notePlaybackFinished(path: path)" in pp)
check("IPTV poll-EOF gate unchanged", "if currentTime < 5.0 {" in pp
      and "iptvModeController?.handlePollEOF(currentTime: currentTime)" in pp)

TAG = re.compile(r"\bs(\d{2})e(\d{2})\b", re.IGNORECASE)
def next_episode(query):
    m = TAG.search(query)
    if not m:
        return None
    n = int(m.group(2))
    if n >= 99:
        return None
    return query[:m.start(2)] + "%02d" % (n + 1) + query[m.end(2):]

cases = [
    ("The Lord of the Rings The Rings of Power s03e03 2160p",
     "The Lord of the Rings The Rings of Power s03e04 2160p"),
    ("Some Show S03E09 2160p", "Some Show S03E10 2160p"),
    ("Some Show s03e03", "Some Show s03e04"),
    ("Some Show s03e03 e04", "Some Show s03e04 e04"),
    ("Some Show s0303 2160p", None),
    ("a documentary 2160p", None),
    ("Some Show s03e99 2160p", None),
    ("xs03e03 title", None),
    ("title 2024 2160p", None),
]
for q, want in cases:
    got = next_episode(q)
    check("next_episode(%r)" % q, got == want, "got=%r want=%r" % (got, want))

STREAM = "http://127.0.0.1:2222/stream/0"

class Tracker:
    # Port of MagnetEpisodeTracker.
    def __init__(self):
        self.armed = None            # [query snapshot, source, adopted]
        self.advanceQuery = None
    def pick(self, query, source):
        self.armed = [query, source, False]
    def media_started(self, path, started_source):
        if self.armed is None or path is None:
            return
        if not (path.startswith("http://127.0.0.1:2222/")
                and started_source == self.armed[1] and not self.armed[2]):
            self.armed = None
            return
        self.armed[2] = True
    def playback_finished(self, path):
        if (self.armed and self.armed[2] and path
                and path.startswith("http://127.0.0.1:2222/")):
            self.advanceQuery = self.armed[0]
            self.armed = None
    def query_committed(self):
        self.advanceQuery = None
        self.armed = None
    def prefill(self, fallback):
        if self.advanceQuery is not None:
            return next_episode(self.advanceQuery) or fallback
        return fallback

t = Tracker()
last_magnet = ""
# The real sequence: pick arms the tracker BEFORE the panel closes.
t.pick("Some Show s03e03 2160p", "magnet:?xt=urn:btih:aaa")
# close -> controller stop -> magnetBrowser = nil: none touch the tracker.
# streamWithWebTorrent records the started source, then the stream loads.
last_magnet = "magnet:?xt=urn:btih:aaa"
t.media_started(STREAM, last_magnet)
t.playback_finished(STREAM)
# Next Cmd+M builds a FRESH panel (queryText ""), prefilled from the tracker.
check("close -> stop -> nil -> stream -> EOF -> new panel advances",
      t.prefill("") == "Some Show s03e04 2160p")
t.query_committed()
check("committed prefill is consumed", t.prefill("") == "")

t = Tracker()
last_magnet = "magnet:?xt=urn:btih:aaa"
t.pick("Some Show s03e03 2160p", last_magnet)
t.media_started("/movies/film-b.mkv", last_magnet)
t.playback_finished("/movies/film-b.mkv")
check("pick, other media, its EOF: no advance", t.prefill("") == "")

t = Tracker()
last_magnet = "magnet:?xt=urn:btih:aaa"
t.pick("Some Show s03e03 2160p", last_magnet)
t.query_committed()
t.playback_finished(STREAM)
check("new query before the old pick's EOF: no advance", t.prefill("") == "")

t = Tracker()
last_magnet = "magnet:?xt=urn:btih:aaa"
t.pick("Some Show s03e03 2160p", last_magnet)
t.media_started(None, last_magnet)
t.media_started(STREAM, last_magnet)
t.playback_finished(STREAM)
check("the empty-path gap between media keeps the arm",
      t.prefill("") == "Some Show s03e04 2160p")

t = Tracker()
last_magnet = "magnet:?xt=urn:btih:aaa"
t.pick("Some Show s03e03 2160p", last_magnet)
t.media_started(STREAM, last_magnet)
t.media_started("http://127.0.0.1:2222/stream/1", last_magnet)
t.playback_finished("http://127.0.0.1:2222/stream/1")
check("a second stream after adoption invalidates the arm", t.prefill("") == "")

t = Tracker()
last_magnet = "magnet:?xt=urn:btih:aaa"
t.pick("Some Show s03e03 2160p", last_magnet)
t.media_started(STREAM, "magnet:?xt=urn:btih:OTHER")
t.playback_finished(STREAM)
check("a stream whose started source is not the pick invalidates",
      t.prefill("") == "")

t = Tracker()
t.playback_finished(STREAM)
check("EOF without a pick arms nothing", t.prefill("") == "")

t = Tracker()
last_magnet = "magnet:?xt=urn:btih:aaa"
t.pick("a documentary 2160p", last_magnet)
t.media_started(STREAM, last_magnet)
t.playback_finished(STREAM)
check("non-series query never advances", t.prefill("") == "")

print(("%d check(s) failed" % len(fails)) if fails else "all checks passed")
sys.exit(1 if fails else 0)

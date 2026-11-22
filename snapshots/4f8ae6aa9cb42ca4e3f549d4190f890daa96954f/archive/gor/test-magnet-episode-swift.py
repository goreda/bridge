#!/usr/bin/env python3
"""Compile and execute the actual MagnetSeriesQuery and MagnetEpisodeTracker
Swift sources with swiftc, through the real lifecycle sequence:
pick -> close -> stop -> magnetBrowser = nil -> stream -> EOF -> new panel.
Not AppKit: the tracker needs Foundation only (URLComponents), provided by
the harness exactly like test-vr-recognition-swift.py does.

When no swiftc is available (the Linux sandbox), the real-code execution
is reported NOT_RUN and the python port in test-magnet-next-episode.py
carries the Linux coverage.
"""
from pathlib import Path
import os, shutil, subprocess, sys, tempfile

r = Path(__file__).resolve().parent
src = (r / "Sources/gor/MagnetBrowser.swift").read_text()

def extract(start_marker):
    block = src[src.index(start_marker):]
    return block[:block.index("\n}")] + "\n}\n"

series = extract("enum MagnetSeriesQuery")
if "import " in series or "NSRegularExpression" in series or "Foundation" in series:
    print("FAIL MagnetSeriesQuery must stay import-free for this harness")
    sys.exit(1)
tracker = extract("struct MagnetEpisodeTracker")
if "NSApp" in tracker or "AppDelegate" in tracker:
    print("FAIL MagnetEpisodeTracker must stay free of app singletons for this harness")
    sys.exit(1)

swift = os.environ.get("SWIFTC", "swiftc")
if shutil.which(swift) is None:
    print("NOT_RUN: swiftc unavailable on this host; run test-magnet-episode-swift.py on a Mac or any host with swiftc.")
    sys.exit(0)

pre = "import Foundation\n"
post = '''
func expect(_ q: String, _ want: String?) {
    let got = MagnetSeriesQuery.nextEpisode(q)
    precondition(got == want, "nextEpisode(\\(q)) = \\(String(describing: got)), want \\(String(describing: want))")
}
expect("The Lord of the Rings The Rings of Power s03e03 2160p", "The Lord of the Rings The Rings of Power s03e04 2160p")
expect("Some Show S03E09 2160p", "Some Show S03E10 2160p")
expect("Some Show s03e03", "Some Show s03e04")
expect("Some Show s03e03 e04", "Some Show s03e04 e04")
expect("Some Show s0303 2160p", nil)
expect("a documentary 2160p", nil)
expect("Some Show s03e99 2160p", nil)
expect("xs03e03 title", nil)
expect("title 2024 2160p", nil)
expect("s00e00", "s00e01")
precondition(!MagnetEpisodeTracker.isTorrentStream("/movies/film-b.mkv"))
precondition(!MagnetEpisodeTracker.isTorrentStream("http://127.0.0.1:8080/x"))
precondition(MagnetEpisodeTracker.isTorrentStream("http://127.0.0.1:2222/stream/0"))

let stream = "http://127.0.0.1:2222/stream/0"
let magnet = "magnet:?xt=urn:btih:aaa"

// The real lifecycle: the pick arms the tracker BEFORE the panel closes;
// close -> stop -> magnetBrowser = nil never touch it; a fresh panel then
// prefills from it with an empty fallback.
var t = MagnetEpisodeTracker()
t.pick(query: "Some Show s03e03 2160p", source: magnet)
t.noteMediaStarted(path: stream, startedSource: magnet)
t.notePlaybackFinished(path: stream)
precondition(t.prefill(fallback: "") == "Some Show s03e04 2160p")
t.noteQueryCommitted()
precondition(t.prefill(fallback: "") == "")

t = MagnetEpisodeTracker()
t.pick(query: "Some Show s03e03 2160p", source: magnet)
t.noteMediaStarted(path: "/movies/film-b.mkv", startedSource: magnet)
t.notePlaybackFinished(path: "/movies/film-b.mkv")
precondition(t.prefill(fallback: "") == "")

t = MagnetEpisodeTracker()
t.pick(query: "Some Show s03e03 2160p", source: magnet)
t.noteQueryCommitted()
t.notePlaybackFinished(path: stream)
precondition(t.prefill(fallback: "") == "")

t = MagnetEpisodeTracker()
t.pick(query: "Some Show s03e03 2160p", source: magnet)
t.noteMediaStarted(path: nil, startedSource: magnet)
t.noteMediaStarted(path: stream, startedSource: magnet)
t.notePlaybackFinished(path: stream)
precondition(t.prefill(fallback: "") == "Some Show s03e04 2160p")

t = MagnetEpisodeTracker()
t.pick(query: "Some Show s03e03 2160p", source: magnet)
t.noteMediaStarted(path: stream, startedSource: magnet)
t.noteMediaStarted(path: "http://127.0.0.1:2222/stream/1", startedSource: magnet)
t.notePlaybackFinished(path: "http://127.0.0.1:2222/stream/1")
precondition(t.prefill(fallback: "") == "")

t = MagnetEpisodeTracker()
t.pick(query: "Some Show s03e03 2160p", source: magnet)
t.noteMediaStarted(path: stream, startedSource: "magnet:?xt=urn:btih:OTHER")
t.notePlaybackFinished(path: stream)
precondition(t.prefill(fallback: "") == "")

t = MagnetEpisodeTracker()
t.notePlaybackFinished(path: stream)
precondition(t.prefill(fallback: "") == "")

t = MagnetEpisodeTracker()
t.pick(query: "a documentary 2160p", source: magnet)
t.noteMediaStarted(path: stream, startedSource: magnet)
t.notePlaybackFinished(path: stream)
precondition(t.prefill(fallback: "") == "")

print("actual Swift MagnetSeriesQuery + MagnetEpisodeTracker: matcher, predicate, real pick->close->stop->nil->stream->EOF->new-panel sequence and invalidation paths PASS")
'''
with tempfile.TemporaryDirectory() as d:
    p = Path(d) / "main.swift"
    p.write_text(pre + series + tracker + post)
    subprocess.run([swift, "-swift-version", "5", str(p), "-o", d + "/check"], check=True)
    subprocess.run([d + "/check"], check=True)
print("actual Swift sources executed; no AppKit involved.")

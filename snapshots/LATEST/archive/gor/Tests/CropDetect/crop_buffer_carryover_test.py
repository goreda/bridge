#!/usr/bin/env python3
"""199az delta piece: no buffer carry-over across files. lastSeekableEnd (and lastVideoTrackID) are
zeroed on every file transition - mpv path change and start-file via resetCropForOpening, and the
embedded acceptEmbedded new-file path - so a previous long file's buffer end can never become the next
file's scannedEnd (which would suppress the buffer-growth restart until the new file buffers past the
old file's end). Static anchors on PPController.swift; behaviour check is a Python mirror with a
negative control showing the bug the fix kills."""
import pathlib, sys
PP = (pathlib.Path(__file__).resolve().parents[2] / 'Sources/gor/Player/PPController.swift').read_text()
fails = []
def check(n, ok):
    print(("ok   " if ok else "FAIL ") + n)
    if not ok: fails.append(n)
reset = PP.split("private func resetCropForOpening() {", 1)[1].split("\n    }", 1)[0]
check("file transition zeroes the buffer end and track id (start-file and mpv path change)",
      "lastSeekableEnd = 0; lastVideoTrackID = 0" in reset)
emb = PP.split("if let source,source.path != currentFilePath {", 1)[1].split("if let time=state.timePos", 1)[0]
check("the embedded new-file path zeroes them too", "lastSeekableEnd=0;lastVideoTrackID=0" in emb)
check("the monotonic update is the only other write (lastSeekableEnd never shrinks mid-file)",
      PP.count("lastSeekableEnd = end") == 1 and "if end > lastSeekableEnd { lastSeekableEnd = end }" in PP)
# mirror
class Buffer:
    def __init__(self):
        self.seek_end = 0.0; self.entries = {}; self.current = ""; self.crop = None; self.restarts = []
    def open(self, path):
        self.current = path; self.seek_end = 0.0          # the fix: zeroed on a file transition
    def poll(self, end):
        if end > self.seek_end: self.seek_end = end
        p = self.entries.get(self.current)
        if p and self.crop is None and end > p[1] + 2:
            self.restarts.append(self.current); self.entries.pop(self.current)
    def indecisive(self):
        n = self.entries[self.current][0] if self.current in self.entries else 0
        self.entries[self.current] = (n + 1, self.seek_end)
b = Buffer()
b.open("A"); b.poll(900); b.indecisive()                  # long file A buffered to 900s, search armed
b.open("B"); b.poll(120); b.indecisive()                  # new file B: its own buffer is 120s
check("mirror: B's first entry records B's own scanned end (120s), not A's 900s", b.entries["B"] == (1, 120))
b.poll(200)                                               # B's buffer grows to 200s
check("mirror: growth past B's scanned range restarts B's search", b.restarts == ["B"])
b2 = Buffer()
b2.open("A"); b2.poll(900); b2.indecisive()
b2.current = "B"                                          # the bug: no zeroing on the transition
b2.poll(120); b2.indecisive(); b2.poll(200)
check("mirror: the carried-over value would have suppressed the restart (the bug this fix kills)",
      b2.entries["B"] == (1, 900) and b2.restarts == [])
print("PASS" if not fails else "FAIL"); sys.exit(1 if fails else 0)

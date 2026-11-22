# Clock decision and seek-anchor parity

Base: `ohal/gorav` at `796837de9a1fb59fd217d66852784127d56a8a88`.

Run from the repository root with Python 3 and Swift 6.1.2:

```sh
python3 Tests/parity/run-clock-parity.py --source Sources/GorAVPlaybackCore/PlaybackCore.swift
```

The runner verifies the complete production file's SHA256, extracts four unchanged
public timing declarations, compiles them with the Swift harness and checks the
fixed JSON vectors. It does not copy a replacement timing implementation into
the tests. A source change requires explicit pin review rather than silently
using a stale model.

The 24 decision vectors cover late/early half-duration boundaries, due frames,
and capped waits at three durations. Five anchor vectors cover a nonzero wall
origin, a media offset, forward seek, backward seek and nonzero media origin.
Binary-exact fractions avoid floating-point boundary ambiguity.

These are Linux Swift timing-model tests. They do not execute FramePump or the
complete package, compare against an mpv executable, or establish native display,
audio, HDR, margins or full-product parity. The synthetic JSON has no external
media or license dependency. Package.swift and all production files stay unchanged.

# Geometry transition regressions

Run with Python 3, Swift 5.10+ and lupa available:

    python Tests/GeometryTransitions/run.py
    python Tests/GeometryTransitions/modes.py
    python Tests/GeometryTransitions/lua.py
    python Tests/GeometryTransitions/negative.py

Set SWIFTC to the compiler path if it is not on PATH. negative.py also needs a C compiler.

- run.py extracts the shipped fullscreen tracking, refit and user-resize methods, compiles them with production GorFit.swift, and replaces unavailable AppKit/AX boundaries with spies. It checks 324 combinations of aspect, mode label and screen, final aspect within integer-pixel rounding, screen bounds, latest deferred intent, no app geometry write during fullscreen/native exit, no duplicate saved-frame restore, unchanged toggle no-op, and stable sizes after mixed round-trips.
- modes.py executes the shipped normal/SBS/TB/VR mode and aspect handlers with production StereoMenuGeometry. It checks 160 mixed/repeated selections plus cropped-stereo mode-off. The downstream refit is a spy; run.py tests that refit separately.
- lua.py runs the shipped script in Lua, drives its real callbacks and timers, and checks cancellation, retargeting, explicit-fit authority over delayed aspect following, and negative-coordinate emission.
- negative.py executes the shipped Swift clampGeometry with a negative visible-frame offset and the exact mpv v0.41.0 C geometry parser/apply excerpts. It proves '+-N' is an absolute negative offset, not a malformed geometry. A bare '-N' is opposite-edge anchoring and is not a safe replacement.

No test here is a native macOS application build or a native motion/pixel capture. Fixed-screen fullscreen can have unused space when its aspect differs from uncropped content. A mode/aspect changed while fullscreen can still show mpv's native saved-frame restoration before the single deferred latest-aspect fit. The tests do not certify absence of that intermediate native frame or of all transient bars.

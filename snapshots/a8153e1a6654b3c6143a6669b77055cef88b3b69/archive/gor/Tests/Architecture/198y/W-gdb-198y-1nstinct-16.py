"""S2-adapted lab guard: lexical ownership only; native compile/runtime NOT_RUN."""
from station_guard import main

CONFIG = {'id': 'W-gdb-198y-1nstinct-16', 'filename': 'OverlaySpaceGate.swift', 'station': 'GorPlatformMac', 'required_types': ['OverlaySpaceGate'], 'required_tokens': ['OverlaySpaceGate', 'Decision', 'sym', 'symbolReport', 'b', 'spaces', 'activeSpace', 'moveWindow', 'largestWindowID', 'log', 'mpvOnScreen', 'observeSpaceChange'], 'required_extensions': []}

if __name__ == '__main__':
    main(CONFIG)

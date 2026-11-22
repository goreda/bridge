"""S2-adapted lab guard: lexical ownership only; native compile/runtime NOT_RUN."""
from station_guard import main

CONFIG = {'id': 'W-gdb-198y-1nstinct-19', 'filename': 'PanelFocusTraversal.swift', 'station': 'GorPlatformMac', 'required_types': ['NoActivate', 'PanelFocusTraversal', 'PanelKeyOwnership'], 'required_tokens': ['NoActivate', 'requested', 'userInteraction', 'PanelFocusTraversal', 'first', 'PanelKeyOwnership', 'register', 'unregister', 'mayKeyPlayerWindow'], 'required_extensions': []}

if __name__ == '__main__':
    main(CONFIG)

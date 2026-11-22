"""S2-adapted lab guard: lexical ownership only; native compile/runtime NOT_RUN."""
from station_guard import main

CONFIG = {'id': 'W-gdb-198y-1nstinct-18', 'filename': 'PanelFocus.swift', 'station': 'GorPlatformMac', 'required_types': ['GORInputPanel'], 'required_tokens': ['GORInputPanel', 'registerKeyOwnership', 'releaseKeyOwnership', 'logFocus', 'rememberFocus', 'firstEditable', 'restorePanelFocus', 'closeAllForQuit'], 'required_extensions': []}

if __name__ == '__main__':
    main(CONFIG)

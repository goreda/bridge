"""S2-adapted lab guard: lexical ownership only; native compile/runtime NOT_RUN."""
from station_guard import main

CONFIG = {'id': 'W-gdb-198y-1nstinct-11', 'filename': 'LookToolsRoute.swift', 'station': 'GorEffectsModel', 'required_types': ['SourceFormatChoice', 'LookToolsRoute', 'SingleSwitchRoute'], 'required_tokens': ['SourceFormatChoice', 'filmID', 'get', 'output', 'off', 'lastOutput', 'raw', 'source', 'kind', 'LookToolsRoute', 'toolsActive', 'toolsActiveJSON'], 'required_extensions': [('VR180Controller', 'resetTestVRProperty', ()), ('VR180Controller', 'refreshToolsActive', ()), ('VR180Controller', 'releaseProjectionLock', ()), ('VR180Controller', 'resetFilmView', (('smooth', ('Bool',)),)), ('VR180Controller', 'resetOrientation', ()), ('VR180Controller', 'singleSwitchPlan', ()), ('VR180Controller', 'applySingleSwitch', ())]}

if __name__ == '__main__':
    main(CONFIG)

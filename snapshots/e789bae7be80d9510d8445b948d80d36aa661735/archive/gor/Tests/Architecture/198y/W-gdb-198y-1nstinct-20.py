"""S2-adapted lab guard: lexical ownership only; native compile/runtime NOT_RUN."""
from station_guard import main

CONFIG = {'id': 'W-gdb-198y-1nstinct-20', 'filename': 'PhotonFont.swift', 'station': 'GorEffectsModel', 'required_types': ['PhotonFont', 'LayoutEngine'], 'required_tokens': ['PhotonFont', 'capH100', 'chromeLayoutScale', 'setChromeLayoutScale', 'chromeValue', 'isInReversedFontSubdir', 'loadFromURL', 'invalidateCache', 'promotePendingMapping', 'applyAxisMapping', 'buildAutoMapping', 'clearAxisMapping'], 'required_extensions': [('Double', 'clamped', (('_', ('Double',)), ('_', ('Double',)))), ('Comparable', 'clamped', (('to', ('ClosedRange', '<', 'Self', '>')),)), ('CATextLayer', 'setForegroundIfChanged', (('_', ('CGColor',)),))]}

if __name__ == '__main__':
    main(CONFIG)

"""S2-adapted lab guard: lexical ownership only; native compile/runtime NOT_RUN."""
from station_guard import main

CONFIG = {'id': 'W-gdb-198y-1nstinct-13', 'filename': 'MegaStreamManager.swift', 'station': 'GorSources', 'required_types': ['LineAccumulator', 'ByteLineAccumulator', 'RelayReadyOnce'], 'required_tokens': ['LineAccumulator', 'append', 'ByteLineAccumulator', 'RelayReadyOnce', 'showMegaOSD', 'isTransferItCDN', 'streamMega', 'stopMegaRelay'], 'required_extensions': [('AppDelegate', 'showMegaOSD', (('_', ('String',)),)), ('AppDelegate', 'isTransferItCDN', (('_', ('String',)),)), ('AppDelegate', 'streamMega', (('shareLink', ('String',)), ('nodeKeyField', ('String',)), ('folderKeyFragment', ('String',)), ('title', ('String',)), ('startPos', ('Double', '?')), ('subtitleURLs', ('[', 'String', ']')))), ('AppDelegate', 'stopMegaRelay', ())]}

if __name__ == '__main__':
    main(CONFIG)

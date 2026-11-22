"""S2-adapted lab guard: lexical ownership only; native compile/runtime NOT_RUN."""
from station_guard import main

CONFIG = {'id': 'W-gdb-198y-1nstinct-01', 'filename': 'AdaptiveColor.swift', 'station': 'GorEffectsModel', 'required_types': [], 'required_tokens': [], 'required_extensions': [('SpineUI', 'applyAdaptiveColor', (('_', ('NSColor',)),)), ('SidebarUI', 'applyAdaptiveColor', (('_', ('NSColor',)),)), ('PPController', 'setupAdaptiveColor', ()), ('MusicPanel', 'applyAdaptiveColor', (('_', ('NSColor',)),)), ('MusicPanel', 'applyColorRecursive', (('_', ('NSView',)), ('color', ('NSColor',))))]}

if __name__ == '__main__':
    main(CONFIG)

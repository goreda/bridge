"""S2-adapted lab guard: lexical ownership only; native compile/runtime NOT_RUN."""
from station_guard import main

CONFIG = {'id': 'W-gdb-198y-1nstinct-15', 'filename': 'MusicPanel.swift', 'station': 'GorUI', 'required_types': ['DraggableScrollView', 'MusicPanel', 'MusicTopBar', 'MusicBotBar', 'MusicListView', 'MusicSectionButton', 'MusicRowView', 'MusicBtn', 'AddMenuView', 'AddMenuRow'], 'required_tokens': ['DraggableScrollView', 'MusicPanel', 'Screen', 'bind', 'updateScrollProgress', 'push', 'replaceTop', 'goBack', 'render', 'addLocalLibrary', 'previewCover', 'clearPreviewCover'], 'required_extensions': [('MusicPanel', 'control', (('_', ('NSControl',)), ('textView', ('NSTextView',)), ('doCommandBy', ('Selector',))))]}

if __name__ == '__main__':
    main(CONFIG)

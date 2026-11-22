"""S2-adapted lab guard: lexical ownership only; native compile/runtime NOT_RUN."""
from station_guard import main

CONFIG = {'id': 'W-gdb-198y-1nstinct-14', 'filename': 'MusicController.swift', 'station': 'GorUI', 'required_types': ['MusicItem', 'TrackItem', 'PlaylistEntry', 'Playlist', 'QueueItem', 'MusicController'], 'required_tokens': ['MusicItem', 'TrackItem', 'PlaylistEntry', 'Playlist', 'QueueItem', 'MusicController', 'start', 'stop', 'detachForQuit', 'search', 'play', 'playTrack'], 'required_extensions': []}

if __name__ == '__main__':
    main(CONFIG)

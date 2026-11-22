"""S2-adapted lab guard: lexical ownership only; native compile/runtime NOT_RUN."""
from station_guard import main

CONFIG = {'id': 'W-gdb-198y-1nstinct-02', 'filename': 'ArchiveBrowser.swift', 'station': 'GorSources', 'required_types': ['ArchiveConfig', 'ArchiveTitle', 'ArchiveOrgItem', 'ArchiveFile', 'ArchiveTarget', 'ArchiveFavorite', 'ArchiveDeletedEntry', 'ArchiveUserLists', 'ArchiveRowMeta', 'ArchiveError', 'ArchiveBrowserPanel', 'ArchiveTopBar'], 'required_tokens': [], 'required_extensions': []}

if __name__ == '__main__':
    main(CONFIG)

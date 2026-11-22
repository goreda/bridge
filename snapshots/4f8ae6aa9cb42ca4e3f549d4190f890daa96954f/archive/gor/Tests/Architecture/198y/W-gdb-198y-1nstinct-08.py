"""S2-adapted lab guard: lexical ownership only; native compile/runtime NOT_RUN."""
from station_guard import main

CONFIG = {'id': 'W-gdb-198y-1nstinct-08', 'filename': 'GORResources.swift', 'station': 'GorPlatformMac', 'required_types': ['GORResources', 'StagedPathPolicy'], 'required_tokens': ['GORResources', 'realDirectory', 'releaseDir', 'bundledDir', 'externalDir', 'conventionalDir', 'vendor', 'fonts', 'vendorRootPath', 'vendorPath', 'fontsPath', 'StagedPathPolicy'], 'required_extensions': []}

if __name__ == '__main__':
    main(CONFIG)

"""S2-adapted lab guard: lexical ownership only; native compile/runtime NOT_RUN."""
from station_guard import main

CONFIG = {'id': 'W-gdb-198y-1nstinct-06', 'filename': 'Diag.swift', 'station': 'GorCore', 'required_types': ['ThreadCpuDiag', 'MainThreadDiag'], 'required_tokens': ['ThreadCpuDiag', 'start', 'stop', 'rotateIfFull', 'cpuSeconds', 'processCPU', 'recordPlaybackDecode', 'sample', 'append', 'MainThreadDiag', 'count'], 'required_extensions': []}

if __name__ == '__main__':
    main(CONFIG)

#!/usr/bin/env python3
"""Owner disk-safety rule supersedes old destructive startup rotation policy."""

# Platform source acquisition only; exact original units via the shared MARK resolver.
import importlib.util as _plat_iu
from pathlib import Path as _PlatPath
_plat_root=next(p for p in _PlatPath(__file__).resolve().parents if (p/'Tests/Structure/platform_source.py').is_file())
_plat_spec=_plat_iu.spec_from_file_location('platform_source_view',_plat_root/'Tests/Structure/platform_source.py')
_plat_view=_plat_iu.module_from_spec(_plat_spec);_plat_spec.loader.exec_module(_plat_view)
_plat_read=_plat_view.read_source
_plat_bytes=_plat_view.read_bytes
_plat_compile_input=_plat_view.compile_input

# Core pure-move source view; existing assertions and compiler bodies are unchanged.
import importlib.util as _core_iu
from pathlib import Path as _CorePath
_core_root=next(p for p in _CorePath(__file__).resolve().parents if (p/'Tests/Structure/core_source.py').is_file())
_core_spec=_core_iu.spec_from_file_location('core_source_view',_core_root/'Tests/Structure/core_source.py')
_core_view=_core_iu.module_from_spec(_core_spec);_core_spec.loader.exec_module(_core_view)
_core_read=_core_view.read_source
_core_bytes=_core_view.read_bytes
_core_materialize=_core_view.materialize
from pathlib import Path
import subprocess,sys
r=Path(__file__).resolve().parents[2]
s=_plat_read(r/'Sources/gor/GorCore/Diag.swift')
rot=s[s.index('private static func rotateIfFull'):s.index('private static func cpuSeconds')]
assert 'moveItem' not in rot and 'removeItem' not in rot
for name in ['Diag.swift','AppDelegate.swift','OverlaySpaceGate.swift']:
 found=sorted((r/'Sources/gor').rglob(name));assert len(found)==1,(name,found)
 text=_plat_read(found[0])
 assert 'SharedDiagnosticRecord.cap' in text
subprocess.run([sys.executable,str(r/'Tests/DiskBudget/shared_diagnostics.py')],check=True)
print('PASS shared diagnostic cap, no legacy startup rotation;8process actual Swift/Lua test replaces old policy model')

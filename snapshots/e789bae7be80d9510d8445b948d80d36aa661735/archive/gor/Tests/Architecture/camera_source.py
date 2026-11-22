"""Test-only exact pre-move source view. Never imported by the app."""
from pathlib import Path
import json
import importlib.util
import re
ROOT=Path(__file__).resolve().parents[2]
SPEC=json.loads((ROOT/'Tests/Architecture/camera-s3-map.json').read_text())
_spec=importlib.util.spec_from_file_location('camera_station_sections',ROOT/'Tests/Structure/section_source.py')
_sections=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(_sections)
_IMPORT_PREFIXES={Path(m['new']).name:m['prefix'] for m in SPEC['moves'] if m.get('prefix')}
_IMPORT_PREFIXES.update({name:'import Foundation\n\n' for name in
 ('HeadPose.swift','Pose192d.swift','PoseMeasurementValidity.swift','BinocularGaze.swift','BuildID.swift')})
_IMPORT_PREFIXES['PoseFrameQuality.swift']='import Foundation\nimport CoreVideo\n\n'

def _station_read(path,*args,**kwargs):
 name=Path(path).name
 if name in {'OverlaySpaceGate.swift', 'PanelFocusTraversal.swift', 'PanelFocus.swift', 'QuitChildKiller.swift'}:
  spec=importlib.util.spec_from_file_location('camera_platform_source',ROOT/'Tests/Structure/platform_source.py')
  module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
  return module.unit_text(name,ROOT)
 if name in {'SubtitlePreferences.swift', 'LiveCaptionController.swift', 'SubtitleView.swift', 'SubtitleSampleGovernor.swift', 'SubtitleTiltGeometry.swift'}:
  spec=importlib.util.spec_from_file_location('camera_subtitles_source',ROOT/'Tests/Structure/subtitles_source.py')
  module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
  return module.unit_text(name,ROOT)
 if name in {'Diag.swift','GeomTrace.swift','GORResources.swift','BuildID.swift','StableCacheKey.swift','SeededRandomNumberGenerator.swift'}:
  spec=importlib.util.spec_from_file_location('camera_core_source',ROOT/'Tests/Structure/core_source.py')
  module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
  return module.unit_text(name,ROOT)
 text=_sections.section_text_exact(ROOT,name)
 prefix=_IMPORT_PREFIXES.get(name)
 if prefix and not text.startswith(prefix):
  # A station may lift duplicate import lines, but not conditional-compilation
  # directives or other source bytes. Restore only this known unit's imports.
  pattern=''.join('(?:'+re.escape(line)+')?' if line.startswith('import ') else re.escape(line)
                  for line in prefix.splitlines(keepends=True))
  match=re.match(pattern,text)
  if not match:raise KeyError('unit import prefix changed: '+name)
  text=prefix+text[match.end():]
 return text

def materialize(path,destination):
 text=read_source(path)
 if 'import Foundation' not in text:text='import Foundation\n'+text
 destination=Path(destination);destination.write_text(text);return destination

def read_source(path,*args,**kwargs):
 path=Path(path)
 try:rel=str(path.relative_to(ROOT/'Sources/gor'))
 except ValueError:return path.read_text(*args,**kwargs)
 if rel=='GorCaptureModel/ScreenCaptureEngine.swift':rel='ScreenCaptureEngine.swift'
 moves=[m for m in SPEC['moves'] if m['old']==rel]
 if not moves:return _station_read(path,*args,**kwargs)
 if 'start' not in moves[0]:return _station_read(ROOT/'Sources/gor'/moves[0]['new'],*args,**kwargs)
 current=ROOT/'Sources/gor/Camera/ScreenCaptureEngine.swift' if rel=='ScreenCaptureEngine.swift' else path
 text=_station_read(current,*args,**kwargs)
 for m in reversed(moves):
  body=_station_read(ROOT/'Sources/gor'/m['new'],*args,**kwargs);assert body.startswith(m['prefix']);body=body[len(m['prefix']):]
  if m['end'] is None:text+=body
  else:
   pos=text.index(m['end']);text=text[:pos]+body+text[pos:]
 return text

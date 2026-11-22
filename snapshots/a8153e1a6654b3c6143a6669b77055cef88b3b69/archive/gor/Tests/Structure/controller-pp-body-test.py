#!/usr/bin/env python3
"""PP historical rebuild resolves moved Controller body without cutting imports twice."""
import importlib.util,pathlib,tempfile,shutil,json
R=pathlib.Path(__file__).resolve().parents[2]
def load(p):
 s=importlib.util.spec_from_file_location('pp_split',p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
m=load(R/'Tests/Structure/pp_split.py');assert len(m.CONTROLLER_PINS)==2
for name in m.CONTROLLER_PINS:assert m.controller_body(R,name)
m.text(R,'PPController_Features.swift');print('PASS PP historical rebuilt hash through exact Controller section body')
for kind in ['stale','missing','wronghost']:
 with tempfile.TemporaryDirectory() as td:
  d=pathlib.Path(td);shutil.copytree(R/'Tests/Structure',d/'Tests/Structure',ignore=shutil.ignore_patterns('__pycache__'));(d/'Sources/gor/Player').mkdir(parents=True);host=d/'Sources/gor/Player/Input.swift';shutil.copy2(R/'Sources/gor/Player/Input.swift',host)
  if kind=='stale':host.write_text(host.read_text().replace('final class DragDropHandler','final class DragDropHandlerChanged',1))
  elif kind=='missing':host.unlink()
  else:host.rename(host.with_name('WrongHost.swift'));host.write_text('// decoy\n')
  try:load(d/'Tests/Structure/pp_split.py').controller_body(d,'DragDropHandler.swift')
  except (AssertionError,KeyError,FileNotFoundError):print('PASS moved PP body mutant RED',kind)
  else:raise AssertionError('mutant survived '+kind)

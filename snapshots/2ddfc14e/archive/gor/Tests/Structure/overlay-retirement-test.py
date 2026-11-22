#!/usr/bin/env python3
"""Exercise the actual shipped migration on a dirty baseline source overlay."""
from pathlib import Path
import importlib.util,json,shutil,tempfile
R=Path(__file__).resolve().parents[2];D=R/'Tests/Structure'
spec=importlib.util.spec_from_file_location('retirement',D/'retire-overlay.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
HISTORICAL_SESSION='import Foundation\n\n/// Per-launch diagnostic ownership. New raw logs are archived and retired as\n/// one session; old shared paths are never adopted, truncated or removed.\nenum SessionLogPaths {\n    static let names: Set<String> = ["gor_diag.log","gor_direct.log","gor_sample.txt","gor_mpv_sample.txt","wt_full.log","photon-grain-size.log","photon-grain-doc.log","gor-quit-debug.log"]\n    static let root: URL = {\n        let fm = FileManager.default\n        let supplied = ProcessInfo.processInfo.arguments.first(where: {$0.hasPrefix("--gor-log-session=")}).map {String($0.dropFirst("--gor-log-session=".count))}\n        let url = supplied.map {URL(fileURLWithPath:$0,isDirectory:true)} ?? fm.temporaryDirectory.appendingPathComponent("gor-log-session-"+UUID().uuidString,isDirectory:true)\n        do {\n            if supplied == nil {\n                try fm.createDirectory(at:url,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])\n                try Data("gor-log-session-v1".utf8).write(to:url.appendingPathComponent(".owner"),options:.withoutOverwriting)\n            }\n            let attrs = try fm.attributesOfItem(atPath:url.path)\n            let markerAttrs = try fm.attributesOfItem(atPath:url.appendingPathComponent(".owner").path)\n            guard url.lastPathComponent.hasPrefix("gor-log-session-"),attrs[.type] as? FileAttributeType == .typeDirectory,\n                  markerAttrs[.type] as? FileAttributeType == .typeRegular,\n                  try String(contentsOf:url.appendingPathComponent(".owner"),encoding:.utf8)=="gor-log-session-v1" else {return URL(fileURLWithPath:"/dev/null")}\n            let pointer=fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/gor/active-log-session.json")\n            try fm.createDirectory(at:pointer.deletingLastPathComponent(),withIntermediateDirectories:true)\n            try JSONSerialization.data(withJSONObject:["root":url.path]).write(to:pointer,options:.atomic)\n            return url\n        } catch {return URL(fileURLWithPath:"/dev/null")}\n    }()\n    static func path(_ original:String)->String {\n        let name=URL(fileURLWithPath:original).lastPathComponent\n        return names.contains(name) ? root.appendingPathComponent(name).path : original\n    }\n}\n'
old=json.loads((D/'overlay-old-sources.json').read_text());manifest=json.loads((D/'retirements.json').read_text())
def setup(base):
 p=base/'project';b=p/'.gor-backups';e=base/'gor-bbu';p.mkdir();shutil.copytree(R/'Sources',p/'Sources');shutil.copytree(D,p/'Tests/Structure')
 for rel,text in old.items():(p/rel).parent.mkdir(parents=True,exist_ok=True) or (p/rel).write_text(text)
 prior=b/'261114-115823-pre-update';prior.mkdir(parents=True);(prior/'changes.txt').write_text('')
 (p/'Sources/gor/UnlistedLocal.swift').write_text('// untouched local source\n')
 return p,b,e
with tempfile.TemporaryDirectory() as td:
 root=Path(td);p,b,e=setup(root/'good') if False else (None,None,None)
 # Create separate fixtures for every fail-closed boundary.
 for mode in ('dirty','replacement','symlink','missing-backup','historical-success','success'):
  old=json.loads((D/'overlay-old-sources.json').read_text())
  base=root/mode;base.mkdir();p,b,e=setup(base);first=manifest['entries'][0];rel=first['path'];target=p/rel
  if mode=='historical-success':
   old['Sources/gor/SessionLogPaths.swift']=HISTORICAL_SESSION
   (p/'Sources/gor/SessionLogPaths.swift').parent.mkdir(parents=True,exist_ok=True) or (p/'Sources/gor/SessionLogPaths.swift').write_text(HISTORICAL_SESSION)
  if mode=='dirty':target.write_text(target.read_text()+'// local edit\n')
  if mode=='replacement':dest=next(iter(first['replacements']));(p/dest).write_text('// mismatch\n')
  if mode=='symlink':target.rename(base/'original');target.symlink_to(base/'original')
  if mode=='missing-backup':(b/'261114-115823-pre-update/changes.txt').rename(base/'changes.txt')
  if mode not in ('success','historical-success'):
   try:m.retire(p,b,e);raise AssertionError('mutation accepted '+mode)
   except RuntimeError:pass
   assert all((p/n).exists() for n in old);assert not e.exists();continue
  backup=m.retire(p,b,e);assert all(not(p/n).exists() for n in old)
  assert (p/'Sources/gor/UnlistedLocal.swift').is_file();assert m.retire(p,b,e) is None
  rows=[line.split('\t') for line in (backup/'changes.txt').read_text().splitlines()]
  for kind,n in rows:
   if kind in ('deleted','changed'):shutil.copy2(backup/n,p/n)
  assert all((p/n).read_text()==text for n,text in old.items())
print('PASS actual dirty-overlay migration:%d absorbed sources moved, coherent rollback and idempotence; local edits/replacement mismatch/symlink/missing backup fail before mutation; unrelated source preserved'%len(old))

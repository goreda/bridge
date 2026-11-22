from pathlib import Path
import json,hashlib
p=Path(__file__).resolve().parents[3]/'Sources/gor/App/AppDelegate.swift';s=p.read_text()
checks=['"photon-hud.lua", "autoload.lua"]','requiredLua.map { "scripts/" + $0 }','guard missing.isEmpty else','try fm.copyItem(at: src, to: tmp)','try fm.createSymbolicLink(at: tmp','if rename(tmp.path, dst.path) != 0','try? fm.moveItem(at: backup, to: dst)','item != "shader" && item != "cache"','--config-dir=\\(configDir)']
for t in checks:assert t in s,t
print(json.dumps({'result':'PASS','source_guards':len(checks),'source_sha256':hashlib.sha256(s.encode()).hexdigest(),'scope':'Source presence checks only, not FileManager execution or installed config selection'},indent=2))

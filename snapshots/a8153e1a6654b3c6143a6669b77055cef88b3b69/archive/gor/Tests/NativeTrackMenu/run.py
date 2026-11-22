from pathlib import Path
import os,subprocess,tempfile
r=Path(__file__).resolve().parents[2];s=(r/'Sources/gor/UI/MenuActions.swift').read_text();a=s.index('struct NativeTrackRow {');b=s.index('extension AppDelegate {',a);actual=s[a:b]
code='import Foundation\n'+actual+'''
let tracks:[[String:Any]]=[
 ["id":1,"type":"video","codec":"h264","selected":true],
 ["id":2,"type":"audio","title":"Commentary","lang":"en","codec":"aac","default":true,"selected":false],
 ["id":3,"type":"audio","lang":"tr","codec":"ac3","selected":true],
 ["id":7,"type":"sub","title":"English","lang":"en","codec":"srt","external":true,"selected":true]]
let a=NativeTrackMenu.rows(tracks,type:"audio")
precondition(a.count==2 && a[1].selected && !a[0].selected)
precondition(a[0].title.contains("Commentary") && a[0].title.contains("en") && a[0].title.contains("aac") && a[0].title.contains("default"))
let sub=NativeTrackMenu.rows(tracks,type:"sub")
precondition(sub.count==2 && !sub[0].selected && sub[1].selected && sub[1].title.contains("external"))
precondition(NativeTrackMenu.rows([],type:"sub")[0].selected)
precondition(NativeTrackMenu.rows([],type:"video").isEmpty)
precondition(NativeTrackMenu.rows(tracks,type:"video").count==1)
precondition(NativeTrackMenu.property("video")=="vid" && NativeTrackMenu.property("audio")=="aid" && NativeTrackMenu.property("sub")=="sid")
print("PASS actual menu builder: all track types, selected flags, title/lang/codec/default/external, subtitle Off, empty/replaced files, direct properties")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(code);subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'check')],check=True);subprocess.run([str(p/'check')],check=True)
a=(r/'Sources/gor/App/AppDelegate.swift').read_text()
for sel in ['menuAudioNext','menuAudioPrev','menuSubNext','menuSubPrev']:assert 'action: #selector('+sel+')' not in a
assert 'live.path==selection["path"]' in s and 'nativeTrackSnapshot()' in s
print('PASS static: cycle menu rows removed, live menu-open rebuild and click file/ID validation wired; native AppKit UI unverified')

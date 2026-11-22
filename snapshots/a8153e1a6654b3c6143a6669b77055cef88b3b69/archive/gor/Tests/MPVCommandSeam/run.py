from pathlib import Path
import subprocess,os,tempfile
root=Path(__file__).resolve().parents[2]
r=root
s=(root/'Sources/gor/Engine/MPVCommand.swift').read_text()
def block(s,n):
 a=s.index(n);i=s.index('{',a);d=1;j=i+1
 while d:d+=(s[j]=='{')-(s[j]=='}');j+=1
 return s[a:j]
prefix='import Foundation\n'+''.join(block(s,n)+'\n' for n in ['enum MPVCommand {','enum PlayerCropSample {','struct PlayerCropPacket {','enum PlayerFitProtocol {'])
tests=(r/'Tests/gorTests/MPVCommandSeamTests.swift').read_text().replace('@testable import gor','')
extra='''
let test=MPVCommandSeamTests(name:"seam",testClosure:{_ in})
test.testMakeKeepsEstablishedBytes()
test.testMakeEscapesInterpolationHazards()
test.testMakeRequestCarriesIdAndCommand()
test.testPreviewPayloadKeepsEstablishedFraming()
let hazard="a\\n\\\"\\\\雪"
let lines=PlayerFitProtocol.previewPayload(geometry:hazard,seekPercent:nil).split(separator:"\\n")
precondition(lines.count==1)
let obj=try! JSONSerialization.jsonObject(with:Data(lines[0].utf8)) as! [String:Any]
precondition((obj["command"] as! [String]).last==hazard)
print("PASS actual A012 enum/fit + four incoming XCTest methods and adversarial framing")
'''
f=Path(tempfile.mkdtemp(prefix='command-seam-'))/'main.swift';f.write_text(prefix+tests+extra)
cc=os.environ.get('SWIFTC','swiftc')
for flags in [[],['-O']]:
 subprocess.run([cc,*flags,str(f),'-o',str(f.parent/'check')],check=True);subprocess.run([str(f.parent/'check')],check=True)

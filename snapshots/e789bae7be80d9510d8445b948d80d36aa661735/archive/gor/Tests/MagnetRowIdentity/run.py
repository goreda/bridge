from pathlib import Path
import json,hashlib,subprocess,os
r=Path(__file__).parent
c=r.parents[1]/'Sources/gor/Media/MagnetBrowser.swift'
newSource=c.read_text()
old='let contentSignature = rows.map { "\\($0.infoHash ?? $0.title)|\\($0.source)|\\($0.title)" }.sorted().joined(separator: "\\n") + "|\\(hiddenCount)"'
new=old.replace('.sorted().joined','.joined')
assert newSource.count(new)==1
s=newSource.replace(new,old)
assert hashlib.sha256(s.encode()).hexdigest()=='754777752836df970c91ede742b908d3c01d7ba68c02f79a9d1e1f78c5d8b536'
# Exact brace-balanced declarations, no source reimplementation.
def decl(text,anchor):
 a=text.index(anchor);start=text.index('{',a);depth=0
 for i in range(start,len(text)):
  if text[i]=='{':depth+=1
  if text[i]=='}':
   depth-=1
   if depth==0:return text[a:i+1]
 raise ValueError(anchor)
types='\n'.join(decl(s,a).replace('fileprivate ','') for a in ['fileprivate struct MagnetResult:', 'fileprivate enum MagnetState:', 'fileprivate struct MagnetVerdict:', 'fileprivate struct ProviderStatus:', 'fileprivate struct SearchResponse:'])
methods='\n'.join(decl(s,a) for a in ['static func sourceRank(', 'static func sortSeeds(', 'static func sortRows(', 'static func poolSize(', 'static func visibleRange(', 'static func maxOffsetY(', 'static func slotAssignments(', 'static func topBySeeds('])
methods=methods.replace('overscan: Int = virtualOverscan','overscan: Int = 3')
# show prefix includes actual row replacement and early-return decision, with AppKit work after
# lastContentSignature replaced by a boundary witness revision increment, not fake AppKit execution.
rows=[]
for variant,source in [('red',s),('green',c.read_text())]:
 a=source.index('    fileprivate func show(_ response:');z=source.index('        lastContentSignature = contentSignature',a)+len('        lastContentSignature = contentSignature')
 prefix=source[a:z].replace('fileprivate func show','func show')
 harness='''import Foundation
'''+types+'\nenum MagnetNative {\n'+methods+'''\n}
final class MagnetResultsPanel {
 static let windowPageSize=1000
 var rows:[MagnetResult]=[],lastShownResponse:SearchResponse?,windowPages=1
 var currentSort="priority",descendingSort=true,lastContentSignature="",lastVerdictSignature=""
 var rowRevision=0,displayed:[String]=[]
 func updateVerdictLabelsInPlace(){}
 func setStatus(_ value:String){}
'''+prefix+'''
 rowRevision+=1;displayed=rows.map{$0.magnetUri!}
 }
}
'''
 (r/(variant+'-extracted.swift')).write_text(harness)
 for lang in ['5','6']:
  for mode in ['Onone','O']:
   q=subprocess.run([os.environ.get('SWIFTC','swiftc'),'-swift-version',lang,'-strict-concurrency=complete','-'+mode,str(r/(variant+'-extracted.swift')),str(r/'Tests.swift'),'-o',str(r/'witness')],capture_output=True,text=True)
   (r/(variant+'-'+lang+'-'+mode+'-compile.log')).write_text(q.stdout+q.stderr);assert not q.returncode,q.stderr
   q=subprocess.run([str(r/'witness')],capture_output=True,text=True);(r/(variant+'-'+lang+'-'+mode+'-run.log')).write_text(q.stdout+q.stderr)
   assert (q.returncode==0)==(variant=='green'),(variant,q.stdout,q.stderr)
   rows.append({'variant':variant,'language':lang,'mode':mode,'compile_exit':0,'run_exit':q.returncode,'stdout':q.stdout});print(variant,lang,mode,q.returncode,q.stdout.strip())
assert 'view.frame = CGRect(x:0,y:CGFloat(rowIndex)*rowHeight' in newSource
assert 'title.identifier = NSUserInterfaceItemIdentifier("\\(rowRevision):\\(rowIndex)")' in newSource
assert 'let row = rows[index]' in newSource
assert 'override var isFlipped: Bool { true }' in newSource
assert 'select?(magnet)' in newSource
(r/'RESULTS.json').write_text(json.dumps(rows,indent=2)+'\n')

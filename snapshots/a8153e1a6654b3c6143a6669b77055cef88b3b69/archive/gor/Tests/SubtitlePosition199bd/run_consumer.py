from pathlib import Path
import subprocess,os
r=Path(__file__).resolve().parent;root=Path(os.environ['SOURCE_DIR']);module=r/'current-module';module.mkdir(exist_ok=True)
subprocess.run([os.environ['SWIFTC'],'-swift-version','5','-emit-module','-emit-library','-module-name','GorAVSubtitles',*[str(p) for p in (root/'Packages/gorav/Sources/GorAVSubtitles').glob('*.swift')],'-o',str(module/'libGorAVSubtitles.so'),'-emit-module-path',str(module/'GorAVSubtitles.swiftmodule')],check=True)
layout=(r/'LayoutProjection.swift').read_text().split('@main struct Tests')[0].replace('struct SubtitleCue {let text:String}','import GorAVSubtitles')
s=(root/'Packages/gorav/Sources/GorAVMetalPresenter/core/MetalPresenter.swift').read_text();a=s.index('    public func consumeSubtitleCues(');b=s.index('\n    }',a)+6;method=s[a:b]
code=layout+'''final class BoundPresenter {
var closed=false;var cueConsumer:SubtitleCueConsumer?=SubtitleCueConsumer(session:7);let view=Layout()
'''+method+'''\n}
@main struct Tests {
static func main(){
let presenter=BoundPresenter();let v=presenter.view
v.subtitleVideoRect={nil};v.subtitlePosition=37
let one=SubtitleCue(index:0,startSeconds:0,endSeconds:1,lines:["first"])
let two=SubtitleCue(index:1,startSeconds:1,endSeconds:2,lines:["new oversized cue"])
let track=SubtitleTrack.Track(format:"srt",cues:[one,two],styles:[],unsupportedOverrides:[],skippedStyles:[],playResX:nil,playResY:nil)
var c=SubtitleController();c.selectPrimary(track);var producer=SubtitleCueProducer(session:7)
let first=producer.sample(session:7,generation:0,filmTime:0,controller:c)!
precondition(presenter.consumeSubtitleCues(first));precondition(v.cueLabel.stringValue=="first" && !v.cueLabel.isHidden)
let old=presenter.cueConsumer!.primary!.identity
v.cueLabel.cell!.measured=1000
precondition(presenter.consumeSubtitleCues(producer.sample(session:7,generation:0,filmTime:1,controller:c)!))
precondition(v.cueLabel.stringValue==two.text && !v.cueLabel.isHidden && presenter.cueConsumer!.primary!.identity != old)
precondition(!v.layoutCueLabels(position:50,apply:true));precondition(!v.setSubtitlePosition(50) && v.subtitlePosition==37)
precondition(presenter.consumeSubtitleCues(producer.sample(session:7,generation:0,filmTime:2,controller:c)!))
precondition(v.cueLabel.isHidden && v.cueLabel.stringValue.isEmpty && presenter.cueConsumer!.primary==nil)
precondition(!presenter.consumeSubtitleCues(first));precondition(v.cueLabel.isHidden)
print("PASS actual current cue producer/controller/consumer + new presenter/view methods: new cue and exact expiry survive layout refusal; accepted position unchanged; stale batch rejected")
}}
'''
p=r/'ConsumerBindingProjection.swift';p.write_text(code)
for opt in ['-Onone','-O']:
 subprocess.run([os.environ['SWIFTC'],'-swift-version','5','-parse-as-library',opt,'-I',str(module),'-L',str(module),'-lGorAVSubtitles',str(p),'-o',str(r/'consumer-binding')],check=True)
 subprocess.run([str(r/'consumer-binding')],env=dict(os.environ,LD_LIBRARY_PATH=str(module)),check=True)

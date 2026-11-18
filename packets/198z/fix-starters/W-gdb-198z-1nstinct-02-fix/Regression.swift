import Foundation
let cue=SubtitleCue(index:1,startSeconds:0,endSeconds:1,lines:["pipe|Unicode I\u{0307}","second line"])
print(SubtitleTrack.stableSidecarID(format:"srt",cues:[cue]))

import Foundation
func check(_ json:String,_ projection:String?,_ stereo:Bool,_ label:String) {
 let r=VRProjectionProbe.parse(Data(json.utf8)); precondition(r.projection==projection && r.stereoSBS==stereo,label);print("PASS "+label+" status="+r.status)
}
check("{}",nil,false,"invalid stream absent")
check("{\"streams\":[{}]}",nil,false,"mono metadata absent remains unknown")
check("{\"streams\":[{\"tags\":{\"stereo_mode\":\"left_right\"}}]}",nil,true,"layout without coverage remains unknown")
check("{\"streams\":[{\"side_data_list\":[{\"side_data_type\":\"Stereo 3D\",\"type\":\"side by side\"},{\"side_data_type\":\"Spherical Mapping\",\"projection\":\"half equirectangular\"}]}]}","vr180",true,"VR180 plus stereo metadata")
check("{\"streams\":[{\"side_data_list\":[{\"side_data_type\":\"Spherical Mapping\",\"projection\":\"rectilinear\"}],\"tags\":{\"stereo_mode\":\"right_left\"}}]}",nil,true,"rectilinear stereo keeps coverage separate")
check("{\"streams\":[{\"side_data_list\":[{\"side_data_type\":\"Spherical Mapping\",\"projection\":\"equirectangular\"}]}]}","vr360-mono",false,"360 coverage is explicit not VR180")
func rule(_ remembered:String?=nil,_ projection:String?=nil,_ stereo:Bool=false,_ name:String="movie.mkv",_ w:Double=1920,_ h:Double=1080,_ kind:String,_ why:String) {
 let c=VRRecognition.choose(remembered:remembered,projection:projection,stereoSBS:stereo,filename:name,width:w,height:h)
 precondition(c.kind==kind && c.reason==why,"recognition rule \(c)");print("PASS recognition \(why) \(name)")
}
rule("mono","vr180",true,"test_vr180.mkv",3840,1920,"mono","remembered")
rule(nil,"vr180",false,"test_sbs.mkv",1920,1080,"vr180","projectionMetadata")
rule(nil,nil,true,"plain.mkv",1920,1080,"flat-sbs","stereoMetadata")
for token in ["vr180","180"] { rule(nil,nil,false,"test_\(token).mkv",1920,1080,"mono","monoNegative") }
for token in ["lr","sbs","hsbs","fsbs"] { rule(nil,nil,false,"test_\(token).mkv",1920,1080,"mono","monoNegative") }
rule(nil,nil,false,"plain.mkv",3840,1920,"mono","monoNegative")
rule(nil,nil,false,"plain.mkv",3840,1080,"mono","monoNegative")
rule(nil,nil,false,"plain.mkv",1920,1080,"mono","monoNegative")
rule(nil,nil,false,"name1800_3dprint.mkv",1920,1080,"mono","monoNegative")

rule(nil,nil,true,"clip.mkv",5760,2880,"flat-sbs","stereoMetadata")
rule(nil,nil,true,"clip.mkv",3840,1080,"flat-sbs","stereoMetadata")
for n in ["a_180x180_3dh.mp4","a_180_lr.mp4","a_180sbs.mp4"] { rule(nil,nil,false,n,1920,1080,"mono","monoNegative") }
check("{\"streams\":[{\"side_data_list\":[{\"side_data_type\":\"Spherical Mapping\",\"projection\":\"tiled equirectangular\",\"bound_left\":1073741824,\"bound_right\":1073741824,\"bound_top\":0,\"bound_bottom\":0}]}]}","vr180",false,"sv3d 180x180 bounds are VR180")
check("{\"streams\":[{\"side_data_list\":[{\"side_data_type\":\"Spherical Mapping\",\"projection\":\"tiled equirectangular\",\"bound_left\":0,\"bound_right\":0}]}]}","unsupported",false,"uncropped tile stays 360")
rule(nil,"unsupported",true,"test_vr180.mkv",3840,1920,"mono","unsupportedProjectionMetadata")

for (projection,stereo,name) in [("flat-sbs",false,"movie.mkv"),("",true,"movie.mkv"),("",false,"movie_HSBS.mkv")] {
 let p:String?=projection.isEmpty ? nil:projection
 let stored=VRRecognition.choose(remembered:"mono",projection:p,stereoSBS:stereo,filename:name,width:3840,height:1080)
 precondition(stored.kind=="mono")
 let session=VRRecognition.choose(remembered:"mono",projection:p,stereoSBS:stereo,filename:name,width:3840,height:1080,manualThisSession:true)
 precondition(session.kind=="mono")
}
print("PASS stored or current-session OFF both dominate SBS evidence")
precondition(VRRecognition.choose(remembered:"flat-tb",projection:"flat-sbs",stereoSBS:true,filename:"x_sbs.mkv",width:3840,height:1080).kind=="flat-tb")
print("PASS saved non-mono projection retains precedence")

for shape in [(3840.0,1080.0),(3840,1200),(7680,2160)] {
 precondition(VRRecognition.choose(remembered:nil,projection:nil,stereoSBS:false,filename:"film.mkv",width:shape.0,height:shape.1).kind=="mono")
}
for tag in ["SBS","HSBS"] {
 precondition(VRRecognition.choose(remembered:nil,projection:nil,stereoSBS:false,filename:"Movie.\(tag).1080p.mkv",width:1920,height:1080).kind=="mono")
}
for metadata in [["STEREO_MODE":"left_right"],["stereo-mode":"side by side"],["projection":"SBS"]] {
 let e=VRRecognition.mpvEvidence(stereoMode:nil,metadata:metadata)
 precondition(VRRecognition.choose(remembered:nil,projection:e.projection,stereoSBS:e.stereoSBS,filename:"film.mkv",width:1920,height:1080).kind=="flat-sbs")
}
print("PASS no-ffprobe: filenames advisory only; explicit container stereo/projection metadata retained")
var cropPixels=[UInt8](repeating:0,count:320*90)
for y in 0..<90 {for eye in 0...1 {for x in 20..<140 {cropPixels[y*320+eye*160+x]=180}}}
let sampledCrop=SBSEyeCrop.sourceCrop(Array(repeating:Data(cropPixels),count:8),width:320,height:90)!
precondition(abs(sampledCrop.x-19.0/160)<1e-9 && abs(sampledCrop.width-122.0/160)<1e-9)
precondition(sampledCrop.y==0 && sampledCrop.height==1)
print("PASS common per-eye horizontal union: preserved one-pixel guards, no seam or repeated vertical crop")

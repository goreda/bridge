"""Exact Swift batch planner + actual FFmpeg raw pixels versus per-frame opens."""
from pathlib import Path
import subprocess, tempfile, json, hashlib
r=Path(__file__).resolve().parents[3]
with tempfile.TemporaryDirectory() as td:
    main=Path(td)/'main.swift'
    main.write_text((r/'Sources/gor/Media/TransferTicketContext.swift').read_text()+'''
let times:[Double]=[0.011,0.130,0.831,0.991,1.4,1.81]
var batches:[[String:Any]]=[];var i=0
while i<times.count {let b=TransferProbeAdmission.cropBatch(times,index:i,frameBytes:320*180*6);batches.append(["times":b,"select":TransferProbeAdmission.cropSelection(b)]);i+=b.count}
assert(TransferProbeAdmission.cropBatch([0,7,8],index:0,frameBytes:1)==[0])
assert(TransferProbeAdmission.cropBatch([0,1,2],index:0,frameBytes:60*1024*1024)==[0])
let data=try! JSONSerialization.data(withJSONObject:batches);print(String(decoding:data,as:UTF8.self))
''')
    plan=json.loads(subprocess.check_output(['swift',str(main)],text=True))
    for pix in ['yuv420p','yuv420p10le','gray']:
        media=Path(td)/f'{pix}.mkv'
        subprocess.run(['ffmpeg','-v','error','-f','lavfi','-i','testsrc2=size=320x180:rate=24:duration=2','-pix_fmt',pix,'-c:v','ffv1',str(media)],check=True)
        rawfmt='gray16le' if pix=='gray' else 'yuv444p16le'; n=320*180*(2 if pix=='gray' else 6)
        for group in plan:
            ts=group['times'];start=ts[0]
            args=['-hide_banner','-loglevel','error','-nostdin','-noautorotate','-hwaccel','none','-threads','2','-ss',str(start),'-i',str(media),'-t',str(ts[-1]-start+0.5),'-map','0:v:0','-an','-sn','-dn','-vf',f"select='{group['select']}',cropdetect=limit=18:round=2:reset=0:skip=0",'-vsync','0','-frames:v',str(len(ts)),'-pix_fmt',rawfmt,'-f','rawvideo','pipe:1']
            batch=subprocess.check_output(['ffmpeg',*args]);assert len(batch)==n*len(ts),(pix,len(batch))
            for i,t in enumerate(ts):
                old=subprocess.check_output(['ffmpeg','-v','error','-noautorotate','-hwaccel','none','-threads','2','-ss',str(t),'-i',str(media),'-map','0:v:0','-an','-sn','-dn','-vf','cropdetect=limit=18:round=2:reset=0:skip=0','-frames:v','1','-pix_fmt',rawfmt,'-f','rawvideo','pipe:1'])
                assert old==batch[i*n:(i+1)*n],(pix,t,hashlib.sha256(old).hexdigest(),hashlib.sha256(batch[i*n:(i+1)*n]).hexdigest())
        print(f'PASS {pix}: six same target frames byte-identical, two container opens instead of six; bounded span/output')

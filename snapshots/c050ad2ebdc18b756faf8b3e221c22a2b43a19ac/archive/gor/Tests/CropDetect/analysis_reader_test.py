#!/usr/bin/env python3
"""Run production WT range pump with in-memory verified-piece adapter and real FFmpeg HTTP readers."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import subprocess,tempfile,shutil,json
r=Path(__file__).resolve().parents[2];s=(r/'Resources/vendor/wt_server/wt_server.mjs').read_text()
floors=s[s.index('const READER_FLOOR_STALL_MS'):s.index('const READER_BUDGET_LOG_MS')]
budget=s[s.index('const READER_BUDGET_LOG_MS'):s.index('let _lastConsumerEvidenceAt')]
pumps=s[s.index('function registerPump('):s.index('// v17.34: piece-count radius')]
handler=s[s.index("      const isAnalysisRequest = req.headers['x-gor-reader']"):s.index('\n    });',s.index("      const isAnalysisRequest = req.headers['x-gor-reader']"))]
with tempfile.TemporaryDirectory() as td:
 t=Path(td);swift=shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc'
 (t/'main.swift').write_text('import Foundation\nlet a=Array(CommandLine.arguments.dropFirst());FileHandle.standardOutput.write(try! JSONSerialization.data(withJSONObject:CropHTTPReader.arguments(a)))')
 relocated=t/'CropHTTPReader.swift';relocated.write_text((lambda _b: _b[_b.index('// BEGIN relocated '+'SourcePixelCrop.swift'+' '):_b.index('// END relocated '+'SourcePixelCrop.swift'+'\n')])((_threed_split().path(r)).read_text()).split('// BEGIN relocated CropHTTPReader.swift (195w 2a, behavior unchanged)\n',1)[1].split('// END relocated CropHTTPReader.swift',1)[0])
 subprocess.run([swift,str(relocated),str(t/'main.swift'),'-o',str(t/'args')],check=True)
 for url in ['/tmp/local.mkv','https://remote.invalid/?gor_stream=1','http://remote.invalid/?gor_stream=1','http://127.0.0.1/plain']:
  a=['-ss','1','-i',url,'-f','null','-'];assert json.loads(subprocess.check_output([str(t/'args')]+a))==a
 src=t/'source.mkv'
 subprocess.run(['ffmpeg','-v','error','-y','-f','lavfi','-i','testsrc2=s=640x360:r=12:d=2','-vf','drawbox=x=0:y=0:w=iw:h=24:color=black:t=fill','-threads','1','-c:v','ffv1',str(src)],check=True)
 js='''import assert from 'node:assert/strict';import fs from 'node:fs';import http from 'node:http';import {spawn} from 'node:child_process';
 const data=fs.readFileSync(process.argv[2]);const pieceLen=65536,fileOffset=0,fileFirst=0,fileLast=Math.floor((data.length-1)/pieceLen),file={length:data.length},mime='video/x-matroska';
 let currentPlayPiece=900,currentWindow={from:880,to:924},_lastRangeStartPiece=899,_lastStreamActivityAt=0,_seekWatch={piece:1},_explicitRangeSeekUntil=Date.now()+100000,_pendingSeekAt=0,_lastWindowForwardAt=0,_lastPumpAbortAt=123;
 const activePumps=new Map();let nextPumpId=0;const WT_PUMP_RECEIPTS=false;const pumpReceipt=()=>{};
 const ring={maxBytes:192*1024*1024,chunks:new Map(),waitedPieces:[],setPlayhead:()=>{},waitForPiece:async p=>{throw Error('fixture piece absent '+p)}};
 for(let p=0;p<=fileLast;p++)ring.chunks.set(p,data.subarray(p*pieceLen,Math.min(data.length,(p+1)*pieceLen)));
 const getRing=()=>ring;const WINDOW_AHEAD_MAX=16,WINDOW_BEHIND=8,LOOKAHEAD=4,MOOV_TAIL_PIECES=2,FULLFILE_PROBE_CAP_PIECES=5,HOLD_MAX_WAITS=1,PIECE_FAIL_THRESHOLD=3;
 const streamSession={begin:()=>1,end:()=>{}};const checkDuplicate=()=> 'duplicate';let authorityCalls=0;
 const updateSlidingWindow=()=>{authorityCalls++},abortPumpsOutsideWindow=()=>{authorityCalls++},_clearRetryPins=()=>{},_cancelOutsideStream=()=>{},_armPostSeekReissue=()=>{},_selectBaseRange=()=>{},_selectHighPriority=()=>{};
 const pieceFailureTracker={isManualSkip:()=>false};const torrent={pieceLength:pieceLen,wires:[]};const _seekOrphans=new Map();
 '''+floors+budget+pumps+'''
 function owner(piece,analysis=false){return {cursorPiece:piece,startPiece:piece,cursorAt:Date.now(),ts:Date.now(),isProbe:false,isAnalysis:analysis,abortController:new AbortController(),response:{destroyed:false}}}
 activePumps.set(100,owner(900));activePumps.set(101,owner(1,true));activePumps.set(102,owner(724,true));
 assert.equal(readerBudgetFloor(900),900);assert.equal(readerRetentionPiece(900),900);
 activePumps.get(101).isAnalysis=false;assert.equal(readerBudgetFloor(900),1);assert.equal(readerRetentionPiece(900),1);activePumps.get(101).isAnalysis=true;
 activePumps.get(101).isProbe=true;assert.equal(readerBudgetFloor(900),900);activePumps.get(101).isProbe=false;
 console.log('PASS competing readers: real production floors ignore analysis1/724 while playback900 advances; unlabelled control reproduces floor1');
 const RAM_CAP_MIN=192*1024*1024;
 const begin=Date.now();await waitForReaderBudget(900,100,new AbortController().signal);assert(Date.now()-begin<100);
 activePumps.get(101).isAnalysis=false;const stop=new AbortController();let finished=false;
 const blocked=waitForReaderBudget(900,100,stop.signal).then(()=>{finished=true});await new Promise(r=>setTimeout(r,100));assert.equal(finished,false);stop.abort();await blocked;activePumps.get(101).isAnalysis=true;
 console.log('PASS actual production async budget: labelled competing reader unblocks play immediately; unlabelled control remains blocked until abort');
 const server=http.createServer(async(req,res)=>{'''+handler+'''
 });await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const url=`http://127.0.0.1:${server.address().port}/?gor_stream=fixture`;
 async function request(start,end){return new Promise((resolve,reject)=>{http.get(url,{headers:{range:`bytes=${start}-${end}`,'x-gor-reader':'analysis'}},res=>{let b=[];assert.equal(res.statusCode,206);res.on('data',d=>b.push(d));res.on('end',()=>resolve(Buffer.concat(b)));res.on('error',reject)}).on('error',reject)})}
 for(const [a,b] of [[10,1000],[pieceLen+5,2*pieceLen+200],[data.length-1024,data.length-1]])assert.deepEqual(await request(a,b),data.subarray(a,b+1));
 assert.equal(currentPlayPiece,900);assert.equal(currentWindow.from,880);assert.equal(_lastRangeStartPiece,899);assert.equal(_seekWatch.piece,1);assert.equal(_lastPumpAbortAt,123);assert.equal(authorityCalls,0);
 function exec(cmd,args){return new Promise((resolve,reject)=>{const p=spawn(cmd,args);let o=[],e=[];p.stdout.on('data',d=>o.push(d));p.stderr.on('data',d=>e.push(d));p.on('close',c=>c===0?resolve([Buffer.concat(o),Buffer.concat(e).toString()]):reject(Error(Buffer.concat(e).toString())));})}
 for(const pix of ['gray16le','yuv444p16le']){
 const a=['-hide_banner','-nostdin','-filter_threads','1','-filter_complex_threads','1','-threads','2','-ss','0.5','-i',url,'-map','0:v:0','-an','-sn','-dn','-vf','cropdetect=limit=18:round=2:reset=0:skip=0','-frames:v','1','-pix_fmt',pix,'-f','rawvideo','pipe:1'];
 // Baseline uses the same real production pump but an unlabelled client; keep
 // test primary pieces in-range so this control reads without a budget wait.
 const before=await exec('ffmpeg',a);const [labelled]=await exec(process.argv[3],a);const b=JSON.parse(labelled.toString());assert(b.includes('X-Gor-Reader: analysis\\r\\n'));
 const after=await exec('ffmpeg',b);assert.equal(before[0].length,after[0].length);assert(before[0].equals(after[0]),'raw pixels differ');assert.deepEqual(before[1].match(/crop=\\d+:\\d+:\\d+:\\d+/g),after[1].match(/crop=\\d+:\\d+:\\d+:\\d+/g));
 console.log('PASS real FFmpeg loopback HTTP exact sample bytes/crop metadata '+pix);
 }
 await new Promise(resolve=>server.close(resolve));console.log('PASS actual range pump: analysis cannot move seek/window/playback frontier or recovery latch; exact206/slice bytes, features unchanged; real swarm/macOS NOT_RUN');
 '''
 (t/'test.mjs').write_text(js)
 subprocess.run(['node',str(t/'test.mjs'),str(src),str(t/'args')],check=True,timeout=70)
assert 'CropHTTPReader.arguments(args)' in (lambda _b: _b[_b.index('// BEGIN relocated '+'SourcePixelCrop.swift'+' '):_b.index('// END relocated '+'SourcePixelCrop.swift'+'\n')])((_threed_split().path(r)).read_text())

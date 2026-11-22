import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {EventEmitter} from 'node:events';
import {execFileSync} from 'node:child_process';
const drive=fs.readFileSync('/tmp/g7-independent/harness/drive.mjs','utf8');
const start=drive.indexOf('let activeReq = null;');
const end=drive.indexOf('// schedule the trace window',start);
assert(start>0&&end>start);
const body=drive.slice(start,end);
function test(b) {
 const res=new EventEmitter();let pauses=0,resumes=0,tick,cleared=0;
 res.statusCode=206;res.pause=()=>pauses++;res.resume=()=>resumes++;
 const req=new EventEmitter();req.end=()=>{};req.destroy=()=>{};
 const context={FILE_LEN:100000000,token:'local-test',BITRATE:9.19e6,log:{write:()=>{}},http:{request:(_o,cb)=>{cb(res);return req;}},setInterval:(cb)=>{tick=cb;return 1;},clearInterval:()=>cleared++};
 vm.createContext(context);vm.runInContext(b+'\nfireRange(0,9000000);',context);
 res.emit('data',Buffer.alloc(1100000));assert.equal(pauses,1,'debits actual 1.1MB chunk');
 tick();assert.equal(resumes,1,'independent tick resumes without another data event');
 res.emit('close');assert.equal(cleared,1,'timer cleared on response close');
}
test(body);console.log('PASS actual fireRange body: variable chunk debit, independent timer resume, close cleanup');
for(const [name,a,b] of [['constant-debit','budget -= chunk.length','budget -= 65536'],['missing-resume','res.resume();','void 0;']]) {
 // Only mutate the resume inside the timer, not the HTTP failure path.
 const mutated=name==='missing-resume'?body.replace('res.resume(); }','void 0; }'):body.replace(a,b);
 assert.notEqual(mutated,body);let killed=false;try{test(mutated);}catch(e){killed=true;console.log('KILLED runtime',name,e.message.split('\n')[0]);}assert(killed);
}
const log='/tmp/g7-independent/fixture.log';
fs.writeFileSync(log,['RSS wt_replay.mjs pid=1 rssMB=674 user=2 sys=1','RSS minimal_seed.mjs pid=2 rssMB=96 user=1 sys=0','RSS wt_replay.mjs pid=1 rssMB=610 user=28.7 sys=1.5','REPLAY:pending=296 connected=96 conns=200 dl=9.1 done=1048576','THROTTLE pause budget=-1','THROTTLE resume-timer budget=2','WINDOW_END readBytes=2097152'].join('\n'));
const parsed=JSON.parse(execFileSync(process.execPath,['/tmp/g7-independent/harness/extract.mjs',log],{encoding:'utf8'}));
assert.equal(parsed.engRssPeakMB,674);assert.equal(parsed.engRssFinalMB,610);assert.equal(parsed.rssPeakByProc['minimal_seed.mjs'],96);assert.equal(parsed.maxConnected,96);assert.equal(parsed.maxConns,200);assert.equal(parsed.maxPending,296);assert.equal(parsed.throttlePauses,1);assert.equal(parsed.throttleResumes,1);assert.equal(parsed.readMB,2);
console.log('PASS actual extractor: sampled peak versus final RSS, per-process peak, 96 connected capacity fields, throttle counts');
console.log('BOUNDARY deterministic local body/extractor regression only. No live peer replay or benchmark rerun.');

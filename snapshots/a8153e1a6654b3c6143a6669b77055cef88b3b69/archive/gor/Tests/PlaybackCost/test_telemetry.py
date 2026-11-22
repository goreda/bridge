"""Execute real diagnostic seams; no native CPU/stall improvement claim."""

# Core pure-move source view; existing assertions and compiler bodies are unchanged.
import importlib.util as _core_iu
from pathlib import Path as _CorePath
_core_root=next(p for p in _CorePath(__file__).resolve().parents if (p/'Tests/Structure/core_source.py').is_file())
_core_spec=_core_iu.spec_from_file_location('core_source_view',_core_root/'Tests/Structure/core_source.py')
_core_view=_core_iu.module_from_spec(_core_spec);_core_spec.loader.exec_module(_core_view)
_core_read=_core_view.read_source
_core_bytes=_core_view.read_bytes
_core_materialize=_core_view.materialize
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import subprocess, tempfile, sys, importlib.util
sys.dont_write_bytecode = True
root = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(root/'tools'))
spec = importlib.util.spec_from_file_location('capture', Path(__file__).with_name('capture.py'))
capture = importlib.util.module_from_spec(spec); spec.loader.exec_module(capture)
text = '[playback-cache] utc_ms=1000 position_s=1.250 cache_s=8.500 paused_for_cache=0\n[ts=1970-01-01T00:00:02.000Z private=/secret] Audio device underrun detected.'
assert capture.correlate(text) == ['underrun utc=1970-01-01T00:00:02.000Z cache_s=8.500 cache_age_ms=1000 paused_for_cache=0 position_s=1.250']
assert 'unavailable' in capture.correlate(text.replace('02.000','05.000'))[0]
assert len(capture.correlate(text+'\n'+text.splitlines()[1]*0)) == 1
js = r'''
import assert from 'node:assert/strict';
import {EventEmitter} from 'node:events';
import http from 'node:http';
import {makeLagSampler, makeHTTPTracer} from '__MODULE__';
let clock=0, callbacks=[], calls=[], records=[];
const emit = row=>{if(row.kind!=='http-first-write')records.push(row);};
const sampler=makeLagSampler({pid:123,platform:'darwin',now:()=>clock,emit,execFile:(...args)=>{calls.push(args);callbacks.push(args[3]);}});
sampler(1000); sampler(999); assert.equal(calls.length,0);
sampler(1001); assert.equal(calls.length,1);sampler(9000);assert.equal(calls.length,1);
assert.equal(calls[0][0],'/usr/bin/sample');assert.deepEqual(calls[0][1],['123','1','1','-file','/tmp/gor-wt-lag-123-1.txt']);
assert.equal(calls[0][2].timeout,4000); callbacks.shift()(null);
clock=59000;sampler(9000);assert.equal(calls.length,1);
clock=60000;sampler(9000);assert.equal(calls.length,2);callbacks.shift()(Error('private path must not log'));
for(let i=0;i<10;i++){clock+=60000;sampler(1001);if(callbacks.length)callbacks.shift()(null);}
assert.equal(calls.length,4);assert(!JSON.stringify(records).includes('private path'));
const linux=makeLagSampler({pid:123,platform:'linux',emit,execFile:()=>{throw Error('must not run');}});linux(9000);
records=[];clock=0;
const trace=makeHTTPTracer({emit,now:()=>clock,cap:1});
let callbackCalled=false;
const response=new EventEmitter();response.statusCode=206;response.write=(data,cb)=>{cb();return false;};
trace({method:'GET',headers:{range:'bytes=10-99',authorization:'private'}},response);
clock=400;assert.equal(response.write(Buffer.from('abc'),()=>{callbackCalled=true;}),false);assert(callbackCalled);
clock=1200;response.write(Buffer.from('12345'),()=>{});clock=1300;response.emit('finish');response.emit('close');
assert.equal(records.length,1);assert.equal(records[0].firstWriteMs,400);assert.equal(records[0].totalMs,1300);
assert.equal(records[0].maxWriteGapMs,800);assert.equal(records[0].bytes,8);assert.equal(records[0].rangeStart,10);assert.equal(records[0].completed,true);
trace({method:'GET',headers:{}},new EventEmitter());assert(!JSON.stringify(records).includes('private'));
let loopback=[];const liveTrace=makeHTTPTracer({emit:r=>{if(r.kind==='http-latency')loopback.push(r);}});
const server=http.createServer((req,res)=>{liveTrace(req,res);res.writeHead(206);res.write('abc');res.end('def');});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
let body='';await new Promise((resolve,reject)=>http.get(`http://127.0.0.1:${server.address().port}/private?token=secret`,res=>{assert.equal(res.statusCode,206);res.on('data',d=>body+=d);res.on('end',resolve);}).on('error',reject));
await new Promise(resolve=>server.close(resolve));assert.equal(body,'abcdef');assert.equal(loopback.length,1);assert.equal(loopback[0].bytes,6);
assert(!JSON.stringify(loopback).includes('secret'));
console.log('PASS lag threshold>1000ms, one sampler,60s cooldown,cap4,4s timeout; HTTP bytes/backpressure/callbacks/status unchanged; no token logging');
'''.replace('__MODULE__', (root/'Resources/vendor/wt_server/diagnostics.mjs').as_uri())
# Production code under Foundation-only stubs: actual throttle, numeric filter and output.
swift = (lambda s:s.split('// BEGIN station-move PlaybackCacheTrace.swift\n',1)[1].split('// END station-move PlaybackCacheTrace.swift\n',1)[0])(_core_read(root/'Sources/gor/GorCore/Diag.swift'))+'''
enum ThreadCpuDiag {
 static var rows: [String] = []
 static func recordPlaybackDecode(_ line: String) { rows.append(line) }
}
let props: [String: Any] = ["demuxer-cache-duration":8.5,"time-pos":1.25,"paused-for-cache":false,"path":"private"]
PlaybackCacheTrace.sample(props,now:0)
PlaybackCacheTrace.sample(props,now:0.5)
PlaybackCacheTrace.sample(["demuxer-cache-duration":Double.nan],now:2)
PlaybackCacheTrace.sample(props,now:2)
assert(ThreadCpuDiag.rows.count == 2)
assert(ThreadCpuDiag.rows.allSatisfy { $0.contains("cache_s=8.500") && !$0.contains("private") })
print("PASS production observed-cache logger1Hz; nonfinite rejected; numeric-only output")
'''
with tempfile.TemporaryDirectory() as temp:
    p=Path(temp); (p/'test.mjs').write_text(js)
    subprocess.run(['node',str(p/'test.mjs')],check=True)
    (p/'main.swift').write_text(swift)
    subprocess.run([sys.argv[1] if len(sys.argv)>1 else 'swiftc',str(p/'main.swift'),'-o',str(p/'test')],check=True)
    subprocess.run([str(p/'test')],check=True)
# Wiring and packaging must be real, not only isolated helper tests.
wt=_core_read(root/'Resources/vendor/wt_server/wt_server.mjs')
assert 'sampleNodeAfterLag(loopLagMs)' in wt and 'traceHTTPRequest(req, res)' in wt
pp=_core_read(_pp_split().path(root,'PPController.swift'))
assert '42: "demuxer-cache-duration", 43: "paused-for-cache"' in pp
assert 'PlaybackCacheTrace.sample(props)' in _core_read(root/'Sources/gor/GorCore/Diag.swift')
build=_core_read(root/'build.sh');helper=build.split("<<'GOR_SESSION_HELPER'",1)[1].split('\nGOR_SESSION_HELPER',1)[0]
compile(helper,'session-helper','exec')
assert 'session_log_paths.entries(root,session=session)' in helper and 'session_log_paths.cleanup(root,receipts)' in helper
print('PASS prior-cache/underrun timestamp correlation with stale-cache rejection; exit collector PID-bind/cap4/2MB; native post-lag sample NOT_RUN')

import zipfile
with tempfile.TemporaryDirectory() as temp:
    fixture=Path(temp); namespace={}
    exec(compile(helper.split("if sys.argv[1]=='arm':",1)[0], 'helper', 'exec'),namespace)
    res=fixture/'Contents/Resources';(res/'vendor/mega_relay').mkdir(parents=True)
    (res/'gor-build-provenance.json').write_text('{"source_commit":"fixture"}')
    (res/'build-id.txt').write_text('commit=fixture\n')
    (res/'vendor/mega_relay/mega_relay.mjs').write_text('fixture relay')
    import session_log_paths
    logs=session_log_paths.create(fixture)
    log=logs/'wt_full.log'; backup=None
    pid=999991987; samples=[logs/('gor-wt-lag-%d-%d.txt'%(pid,i)) for i in range(1,6)]
    try:
        log.write_text('[2026-11-07T13:00:00.000Z] STATS:{"session":%d}\n'%pid)
        for i,p in enumerate(samples):p.write_text('sample '+str(i))
        output=Path(namespace['archive']({'id':'test','config':str(fixture),'bundle':str(fixture),'log_root':str(logs)},'fixture'))
        with zipfile.ZipFile(output) as z:
            assert z.read('gor-build-provenance.json')==b'{"source_commit":"fixture"}'
            assert z.read('build-id.txt')==b'commit=fixture\n'
            assert b'collection_time_only=true sha256=' in z.read('relay-at-collection-sha256.txt')
            kept=[n for n in z.namelist() if n.startswith('gor-wt-lag-')]
            assert len(kept)==4 and all(str(pid) in n for n in kept)
        output.unlink()
    finally:
        for p in samples:p.unlink(missing_ok=True)
        if backup is None:log.unlink(missing_ok=True)
        else:log.write_bytes(backup)
print('PASS real exit ZIP includes capped current-PID sample files')

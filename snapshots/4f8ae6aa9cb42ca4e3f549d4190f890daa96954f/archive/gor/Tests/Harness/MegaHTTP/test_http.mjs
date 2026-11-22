// Execute actual isolated current HTTP handler with invented 16-byte source.
import {readFileSync} from 'node:fs';
import http from 'node:http';
import {Readable,pipeline} from 'node:stream';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const path=new URL('../../../Resources/vendor/mega_relay/mega_relay.mjs',import.meta.url);
const text=readFileSync(path,'utf8');
const lo=text.indexOf('const server = http.createServer('),hi=text.indexOf("server.on('error'",lo);assert.ok(lo>=0&&hi>lo);
const bytes=Buffer.from('0123456789abcdef');let opens=[];
const source={size:bytes.length,open:(start,end)=>{opens.push([start,end]);return Readable.from([bytes.subarray(start,end+1)])}};
const ctx={http,pipeline,source,console:{log(){},error(){}},Number};
vm.createContext(ctx);vm.runInContext(text.slice(lo,hi)+'\nglobalThis.fixtureServer = server;',ctx);
const server=ctx.fixtureServer;await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
function request(method='GET',range){return new Promise((resolve,reject)=>{const req=http.request({host:'127.0.0.1',port:server.address().port,path:'/',method,headers:range?{Range:range}:{}},res=>{const parts=[];res.on('data',part=>parts.push(part));res.on('end',()=>resolve({status:res.statusCode,headers:res.headers,body:Buffer.concat(parts)}));});req.on('error',reject);req.end();});}
const controls=[],characterizations=[];
try{
 let r=await request();assert.equal(r.status,200);assert.deepEqual(r.body,bytes);assert.equal(r.headers['content-length'],'16');controls.push('GET entire source 200, exact synthetic bytes/length');
 const before=opens.length;r=await request('HEAD');assert.equal(r.status,200);assert.equal(r.body.length,0);assert.equal(opens.length,before);controls.push('HEAD 200 headers without source.open');
 r=await request('GET','bytes=3-7');assert.equal(r.status,206);assert.equal(r.body.toString(),'34567');assert.equal(r.headers['content-range'],'bytes 3-7/16');controls.push('closed range 206 exact slice');
 r=await request('GET','bytes=12-');assert.equal(r.status,206);assert.equal(r.body.toString(),'cdef');controls.push('open-ended range to EOF');
 r=await request('HEAD','bytes=0-0');assert.equal(r.status,206);assert.equal(r.body.length,0);assert.equal(r.headers['content-length'],'1');controls.push('HEAD range 206 length without body');
 for(const range of ['bytes=16-','bytes=7-3','garbage','bytes=9007199254740992-']){r=await request('GET',range);assert.equal(r.status,416);assert.equal(r.headers['content-range'],'bytes */16');}
 controls.push('start/end/safe-integer/malformed rejection 416');
 r=await request('POST');assert.equal(r.status,405);controls.push('non GET/HEAD rejected 405');
 for(const range of ['bytes=-4','bytes=0-999','bytes=0-1,4-5']){r=await request('GET',range);assert.equal(r.status,416);characterizations.push({range,observed:'416 rejected by current handler',scope:'actual loopback handler result; desired suffix/clamp/multirange policy not externally verified'});}
 console.log(JSON.stringify({result:'PASS actual current HTTP handler loopback fixtures',controls,characterizations,source_sha256:createHash('sha256').update(text).digest('hex'),scope:'Actual isolated Node HTTP handler and synthetic source on 127.0.0.1 only. No MEGA/provider/download/Swift/mpv/real media or UI execution.'},null,2));
}finally{await new Promise(resolve=>server.close(resolve));}

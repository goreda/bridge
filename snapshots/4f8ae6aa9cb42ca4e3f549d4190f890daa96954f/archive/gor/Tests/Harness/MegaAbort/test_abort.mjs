import {readFileSync} from 'node:fs';
import http from 'node:http';
import {Readable,pipeline} from 'node:stream';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const text=readFileSync(new URL('../../../Resources/vendor/mega_relay/mega_relay.mjs',import.meta.url),'utf8');
const lo=text.indexOf('const server = http.createServer('),hi=text.indexOf("server.on('error'",lo);assert.ok(lo>=0&&hi>lo);
const controls=[];
async function scenario(mode){
 const errors=[],notes=[];let body,opened=0,destroys=0,pauses=0;
 const source={size:1048576,open:()=>{
  opened++;
  body=new Readable({read(){if(this.started)return;this.started=true;if(mode==='failure')setImmediate(()=>this.destroy(new Error('fixture upstream failure')));else if(mode==='clean')this.push(Buffer.alloc(1048576,7)),this.push(null);else this.push(Buffer.alloc(1024,7));},destroy(error,done){destroys++;done(error);}});
  const pause=body.pause.bind(body);body.pause=()=>{pauses++;return pause();};return body;
 }};
 const ctx={http,pipeline,source,console:{log:s=>notes.push(s),error:s=>errors.push(s)},Number};vm.createContext(ctx);vm.runInContext(text.slice(lo,hi)+'\nglobalThis.serverFixture=server;',ctx);
 const server=ctx.serverFixture;const sockets=new Set();server.on('connection',s=>{sockets.add(s);s.on('close',()=>sockets.delete(s));});await new Promise(r=>server.listen(0,'127.0.0.1',r));
 try{
  await new Promise((resolve,reject)=>{
   const timer=setTimeout(()=>reject(new Error('fixture timed out')),2000);
   const done=()=>{clearTimeout(timer);resolve();};
   const req=http.get({host:'127.0.0.1',port:server.address().port,path:'/'},res=>{
    if(mode==='abort')res.once('data',()=>{res.destroy();req.destroy();done();});
    else {res.resume();res.on('end',done);res.on('aborted',done);res.on('error',done);}
   });req.on('error',()=>mode==='failure'?done():reject(new Error('unexpected request error')));
  });
  await new Promise(r=>setTimeout(r,40));
  assert.equal(opened,1);
  if(mode==='abort'){assert.ok(body.destroyed);assert.ok(destroys>=1);assert.ok(pauses>=1);assert.equal(errors.length,0);controls.push('downstream abort destroys/pauses synthetic upstream without ERROR');}
  if(mode==='failure'){assert.ok(body.destroyed);assert.ok(errors.some(s=>s.includes('ERROR:source stream error: fixture upstream failure')));controls.push('genuine upstream error reported on ERROR and destroyed');}
  if(mode==='clean'){assert.equal(errors.length,0);assert.ok(body.readableEnded);controls.push('clean complete response no ERROR');}
 }finally{for(const s of sockets)s.destroy();await new Promise(r=>server.close(r));}
}
await scenario('abort');await scenario('failure');await scenario('clean');
console.log(JSON.stringify({result:'PASS actual current handler abort/error loopback controls',controls,source_sha256:createHash('sha256').update(text).digest('hex'),scope:'Actual isolated Node server/Readable fixtures on 127.0.0.1. No MEGA/provider/real media/backend/Swift/mpv/UI execution.'},null,2));

import test from 'node:test';
import assert from 'node:assert/strict';
import dgram from 'node:dgram';
import {readFileSync} from 'node:fs';
import {enrichSeeds,parseUindex} from '../../../Resources/vendor/magnet_search/magnet_search.mjs';
const hash='a'.repeat(40);
async function fixture(mode,fn){
 const server=dgram.createSocket('udp4');let connections=0,scrapes=0;
 server.on('message',(msg,peer)=>{
  const action=msg.readUInt32BE(8),tx=msg.readUInt32BE(12);
  if(action===0){connections++;if(mode==='silent')return;const out=Buffer.alloc(16);out.writeUInt32BE(0);out.writeUInt32BE(mode==='wrong-connect-tx'?(tx+1)>>>0:tx,4);out.fill(7,8);server.send(out,peer.port,'127.0.0.1');}
  if(action===2){scrapes++;if(mode==='error'){const out=Buffer.alloc(8);out.writeUInt32BE(3);out.writeUInt32BE(tx,4);server.send(out,peer.port,'127.0.0.1');return;}const out=Buffer.alloc(20);out.writeUInt32BE(2);out.writeUInt32BE(mode==='wrong-scrape-tx'?(tx+1)>>>0:tx,4);out.writeUInt32BE(12,8);out.writeUInt32BE(2,12);out.writeUInt32BE(3,16);server.send(out,peer.port,'127.0.0.1');}
 });
 await new Promise(resolve=>server.bind(0,'127.0.0.1',resolve));
 const tracker=`udp://127.0.0.1:${server.address().port}`;
 try{return await fn(tracker,()=>({connections,scrapes}));}finally{await new Promise(resolve=>server.close(resolve));}
}
const row=tracker=>({infoHash:hash,seeds:null,leeches:null,magnetUri:`magnet:?xt=urn:btih:${hash}&tr=${encodeURIComponent(tracker)}`});
test('valid local BEP15 response enriches counts',async()=>fixture('ok',async tr=>{const r=row(tr);await enrichSeeds([r],{timeoutMs:120});assert.equal(r.seeds,12);assert.equal(r.leeches,3);assert.equal(r.swarmSource,'tracker-scrape');}));
for(const mode of ['silent','error','wrong-scrape-tx'])test(`${mode} leaves unknown counts`,async()=>fixture(mode,async tr=>{const r=row(tr);await enrichSeeds([r],{timeoutMs:80});assert.equal(r.seeds,null);assert.equal(r.swarmSource,undefined);}));
test('maxRows skips rows past budget and already populated rows',async()=>fixture('ok',async(tr,counts)=>{const rows=[{...row(tr),seeds:99},row(tr),row(tr)];await enrichSeeds(rows,{maxRows:1,timeoutMs:120});assert.equal(rows[0].seeds,99);assert.equal(rows[1].seeds,12);assert.equal(rows[2].seeds,null);assert.equal(counts().connections,1);}));
test('no UDP tracker does not enrich',async()=>{const r=row('https://tracker.invalid/announce');await enrichSeeds([r],{timeoutMs:20});assert.equal(r.seeds,null);});
test('wrong connect transaction is rejected before scrape',async()=>fixture('wrong-connect-tx',async(tr,counts)=>{const r=row(tr);await enrichSeeds([r],{timeoutMs:120});assert.equal(r.seeds,null);assert.equal(r.swarmSource,undefined);assert.equal(counts().scrapes,0);}));
test('challenge HTML is not a provider listing',()=>{assert.throws(()=>parseUindex('<html><title>Just a moment...</title></html>'),/layout:uindex:table/);assert.throws(()=>parseUindex(''),/layout:uindex:table/);});
test('CLI final parse network triggers are explicit source guards, not executed',()=>{const cli=readFileSync(new URL('../../../Resources/vendor/magnet_search/cli.mjs',import.meta.url),'utf8');assert.ok(cli.includes('if(pending.size===0)'));assert.ok(cli.includes('execFileSync(process.execPath'));assert.ok(cli.includes('await enrichSeeds(merged'));});

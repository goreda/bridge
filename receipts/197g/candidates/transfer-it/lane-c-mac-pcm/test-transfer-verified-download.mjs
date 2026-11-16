import {prepareTransferFile} from './TransferItVerifiedDownload.mjs';
import {randomBytes,createCipheriv,createHash} from 'node:crypto';
import http from 'node:http';import fs from 'node:fs/promises';import os from 'node:os';import path from 'node:path';import assert from 'node:assert/strict';
const data=Buffer.alloc(176444);data.write('RIFF');data.writeUInt32LE(data.length-8,4);data.write('WAVEfmt ',8);data.writeUInt32LE(16,16);data.writeUInt16LE(1,20);data.writeUInt16LE(2,22);data.writeUInt32LE(44100,24);data.writeUInt32LE(176400,28);data.writeUInt16LE(4,32);data.writeUInt16LE(16,34);data.write('data',36);data.writeUInt32LE(176400,40);
for(let i=0;i<44100;i++){data.writeInt16LE((i*97)%60001-30000,44+i*4);data.writeInt16LE((i*193)%60001-30000,46+i*4);}
const vector=JSON.parse(await fs.readFile(new URL('./mac-vectors.json',import.meta.url))).wavAnchor;assert.equal(createHash('sha256').update(data).digest('hex'),vector.sha256);
const key=Buffer.from(vector.fileKeyHex,'hex'),aes=Buffer.from(key.subarray(0,16).map((v,i)=>v^key[i+16]));
const attr=Buffer.from('MEGA'+JSON.stringify({n:'owned.wav'})),pad=Buffer.alloc(Math.ceil(attr.length/16)*16);attr.copy(pad);
const cipher=createCipheriv('aes-128-cbc',aes,Buffer.alloc(16));cipher.setAutoPadding(false);
const node={t:0,h:'OWNEDNODE',s:data.length,k:key.toString('base64url'),a:Buffer.concat([cipher.update(pad),cipher.final()]).toString('base64url')};
let mode='ok',seenFile=0;const tmp=await fs.mkdtemp(path.join(os.tmpdir(),'transfer-owned-'));
const server=http.createServer(async(req,res)=>{
 const url=new URL(req.url,'http://127.0.0.1');
 if(url.pathname==='/cs') {const chunks=[];for await(const c of req)chunks.push(c);const [command]=JSON.parse(Buffer.concat(chunks));res.end(JSON.stringify([command.a==='xi'?{pw:0}:{f:[node]}]));return;}
 assert.equal(req.headers.origin,'https://transfer.it');seenFile++;
 if(mode==='redirect'){res.writeHead(302,{location:'http://example.invalid/private'});res.end();return;}
 if(mode==='loop'){res.writeHead(302,{location:req.url});res.end();return;}
 if(mode==='html'){res.writeHead(200,{'content-type':'text/html'});res.end('<html>landing page</html>');return;}
 if(mode==='slow'){await new Promise(resolve=>setTimeout(resolve,300));if(res.destroyed)return;}
 if(mode==='over'){res.writeHead(200);res.write(data);res.end(Buffer.alloc(1));return;}
 if(mode==='corrupt'){const bad=Buffer.from(data);bad[bad.length-1]^=1;res.writeHead(200,{'content-type':'audio/wav','content-length':bad.length});res.end(bad);return;}
 if(mode==='short'){res.writeHead(200);res.write(data.subarray(0,100));res.end();return;}
 res.writeHead(200,{'content-type':'audio/wav','content-length':data.length});res.end(data);
});
try{
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const opts={link:'https://transfer.it/t/OWNEDHANDLE',filename:'owned.wav',testGateway:`http://127.0.0.1:${server.address().port}/`};
 const output=path.join(tmp,'good.wav');const result=await prepareTransferFile({...opts,output});
 assert.deepEqual(await fs.readFile(output),data);assert.equal(result.sha256,createHash('sha256').update(data).digest('hex'));assert.equal(result.integrity,'node-key-mac');assert.equal((await fs.stat(output)).mode&0o777,0o600);
 console.log(`PASS actual bounded download equals independent integer PCM WAV anchor ${result.bytes}B SHA256 ${result.sha256}; whole-file MAC verified against independent synthetic nodekey`);
 await assert.rejects(prepareTransferFile({...opts,output}),e=>e.kind==='destination_exists');assert.deepEqual(await fs.readFile(output),data);console.log('PASS existing destination preserved');
 for(const [test,kind,changes] of [['corrupt','integrity_mismatch',{}],['cap','file_limit',{byteLimit:100}],['html','not_media',{}],['redirect','insecure_redirect',{}],['loop','redirect_limit',{}],['over','file_limit',{}],['short','size_mismatch',{}],['slow','timeout',{timeoutMs:50}]]){
  mode=test;const destination=path.join(tmp,test+'.wav');await assert.rejects(prepareTransferFile({...opts,output:destination,...changes}),e=>e.kind===kind);await assert.rejects(fs.stat(destination),e=>e.code==='ENOENT');console.log('PASS '+kind+' cleanup');
 }
 mode='slow';const controller=new AbortController();const pending=prepareTransferFile({...opts,output:path.join(tmp,'cancel.wav'),signal:controller.signal});setTimeout(()=>controller.abort(),50);await assert.rejects(pending,e=>e.kind==='cancelled');await assert.rejects(fs.stat(path.join(tmp,'cancel.wav')),e=>e.code==='ENOENT');console.log('PASS inflight cancel cleanup');
 if(process.argv[2]){const destination=path.resolve(process.argv[2]);await fs.mkdir(destination,{recursive:true});await fs.copyFile(output,path.join(destination,'transfer-downloaded.wav'),fs.constants.COPYFILE_EXCL);await fs.writeFile(path.join(destination,'transfer-anchor.pcm'),data.subarray(44),{flag:'wx',mode:0o600});console.log('SAVED controlled download and independent raw PCM anchor for product decoder');}
 console.log('m2-transfer-verified-download: all pass; controlled network only, whole-fileMAC, no live-service claim');
}finally{server.closeAllConnections();await new Promise(resolve=>server.close(resolve));await fs.rm(tmp,{recursive:true,force:true});}

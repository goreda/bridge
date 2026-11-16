import {resolveTransferFile} from './TransferItSource.mjs';
import {randomBytes,createCipheriv} from 'node:crypto';
import http from 'node:http';
import assert from 'node:assert/strict';
const key=randomBytes(32), aes=Buffer.from(key.subarray(0,16).map((v,i)=>v^key[i+16]));
const plaintext=Buffer.from('MEGA'+JSON.stringify({n:'owned.wav'})),padded=Buffer.alloc(Math.ceil(plaintext.length/16)*16);plaintext.copy(padded);
const cipher=createCipheriv('aes-128-cbc',aes,Buffer.alloc(16));cipher.setAutoPadding(false);
const node={t:0,h:'OWNEDNODE',s:176444,k:key.toString('base64url'),a:Buffer.concat([cipher.update(padded),cipher.final()]).toString('base64url')};
let mode='ok';
const server=http.createServer(async(req,res)=>{
 const chunks=[];for await(const chunk of req)chunks.push(chunk);
 const [command]=JSON.parse(Buffer.concat(chunks));
 if(mode==='slow')await new Promise(resolve=>setTimeout(resolve,1000));
 if(mode==='huge'){res.writeHead(200);res.end(' '.repeat(1024*1024+1));return;}
 if(command.a==='xi')res.end(JSON.stringify([{pw:mode==='password'?1:0}]));
 else {assert.equal(command.a,'f');assert.equal(new URL(req.url,'http://127.0.0.1').searchParams.get('x'),'OWNEDHANDLE');
  res.end(JSON.stringify([{f:mode==='duplicate'?[node,node]:mode==='missing'?[]:[mode==='badattrs'?{...node,a:'eHh4'}:node]}]));}
});
try{
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const opts={link:'https://transfer.it/t/OWNEDHANDLE',filename:'owned.wav',testGateway:`http://127.0.0.1:${server.address().port}/`};
 const value=await resolveTransferFile(opts);const actual=new URL(value.url);
 assert.equal(actual.pathname,'/cs/g');assert.equal(actual.searchParams.get('n'),'OWNEDNODE');assert.equal(value.headers.Origin,'https://transfer.it');assert.equal(value.bytes,176444);
 console.log('PASS encrypted-node attribute resolution and exact directfile contract');
 for(const [test,kind] of [['password','password_required'],['duplicate','ambiguous_file'],['missing','missing_file'],['badattrs','bad_metadata'],['huge','metadata_limit']]){
  mode=test;await assert.rejects(resolveTransferFile(opts),error=>error.kind===kind);console.log('PASS '+kind);
 }
 mode='slow';await assert.rejects(resolveTransferFile({...opts,timeoutMs:50}),error=>error.kind==='timeout');console.log('PASS timeout');
 mode='ok';const controller=new AbortController();controller.abort();await assert.rejects(resolveTransferFile({...opts,signal:controller.signal}),error=>error.kind==='cancelled');console.log('PASS cancel');
 console.log('m2-transfer-contract: all pass');
}finally{server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}

// Local plaintext transfer contract fixture for real process->API->MAC->PCM join.
import fs from 'node:fs/promises';import path from 'node:path';import http from 'node:http';import {createCipheriv,createHash} from 'node:crypto';
const root=process.argv[2];await fs.mkdir(root,{recursive:true});
const raw=Buffer.alloc(176400);for(let i=0;i<44100;i++){raw.writeInt16LE((i*97)%60001-30000,i*4);raw.writeInt16LE((i*193)%60001-30000,i*4+2);}
const wav=Buffer.alloc(44+raw.length);wav.write('RIFF');wav.writeUInt32LE(wav.length-8,4);wav.write('WAVEfmt ',8);wav.writeUInt32LE(16,16);wav.writeUInt16LE(1,20);wav.writeUInt16LE(2,22);wav.writeUInt32LE(44100,24);wav.writeUInt32LE(176400,28);wav.writeUInt16LE(4,32);wav.writeUInt16LE(16,34);wav.write('data',36);wav.writeUInt32LE(raw.length,40);raw.copy(wav,44);
const vector=JSON.parse(await fs.readFile(new URL('../transfer-candidate/mac-vectors.json',import.meta.url))).wavAnchor;
if(createHash('sha256').update(wav).digest('hex')!==vector.sha256)throw Error('fixture mismatch');
const key=Buffer.from(vector.fileKeyHex,'hex'),aes=Buffer.from(key.subarray(0,16).map((v,i)=>v^key[i+16]));
const attr=Buffer.from('MEGA'+JSON.stringify({n:'owned.wav'})),pad=Buffer.alloc(Math.ceil(attr.length/16)*16);attr.copy(pad);const cipher=createCipheriv('aes-128-cbc',aes,Buffer.alloc(16));cipher.setAutoPadding(false);
const node={h:'OWNEDNODE',t:0,s:wav.length,k:key.toString('base64url'),a:Buffer.concat([cipher.update(pad),cipher.final()]).toString('base64url')};
const server=http.createServer(async(req,res)=>{try{
 const url=new URL(req.url,'http://127.0.0.1');
 if(url.pathname==='/cs'){let size=0,parts=[];for await(const part of req){size+=part.length;if(size>10000)throw Error('request cap');parts.push(part);}const [cmd]=JSON.parse(Buffer.concat(parts));res.end(JSON.stringify([cmd.a==='xi'?{pw:0}:{f:[node]}]));return;}
 if(url.pathname!=='/cs/g'||url.searchParams.get('n')!=='OWNEDNODE'||req.headers.origin!=='https://transfer.it'){res.writeHead(403);res.end();return;}
 res.writeHead(200,{'content-type':'audio/wav','content-length':wav.length});res.end(wav);
}catch(error){if(req.aborted&&error.code==='ECONNRESET')return;res.destroy();}});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
await fs.writeFile(path.join(root,'anchor.pcm'),raw);await fs.writeFile(path.join(root,'gateway'),`http://127.0.0.1:${server.address().port}/`);
console.log('fixture server ready; integer anchor retained separately');
process.on('SIGTERM',()=>{server.closeAllConnections();server.close(()=>process.exit(0));});

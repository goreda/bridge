// Diagnostic disagreement remains RED. Never use as acceptance by suppressing exit.
import {encrypt} from '../mega-candidate/node_modules/megajs/dist/main.node-es.mjs';
import {Readable} from 'node:stream';import {pipeline} from 'node:stream/promises';import fs from 'node:fs';
let mismatch=0;
for(const v of JSON.parse(fs.readFileSync(new URL('./mac-vectors.json',import.meta.url))).vectors){
 const input=Buffer.alloc(v.size);for(let i=0;i<input.length;i++)input[i]=(i*97)%251;
 const stream=encrypt(Buffer.from(Array.from({length:24},(_,i)=>i)));stream.resume();await pipeline(Readable.from([input]),stream);
 const equal=stream.key.toString('hex')===v.fileKeyHex;
 console.log((equal?'MATCH':'DISAGREEMENT')+' documented batchMAC vs MEGAJS1.3.10 encrypt size='+v.size);if(!equal)mismatch++;
}
console.log('MEGAJS/documented protocol discrepancies='+mismatch+'; no service resolution');process.exit(mismatch?1:0);

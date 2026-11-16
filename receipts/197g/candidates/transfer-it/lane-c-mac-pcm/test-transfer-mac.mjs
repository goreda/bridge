import {plaintextMACVerifier} from './TransferPlainMAC.mjs';
import fs from 'node:fs';import assert from 'node:assert/strict';import {createHash} from 'node:crypto';
const fixture=JSON.parse(fs.readFileSync(new URL('./mac-vectors.json',import.meta.url)));
for(const vector of fixture.vectors){
 const input=Buffer.alloc(vector.size);for(let i=0;i<input.length;i++)input[i]=(i*97)%251;
 assert.equal(createHash('sha256').update(input).digest('hex'),vector.sha256);
 const key=Buffer.from(vector.fileKeyHex,'hex');
 for(const step of [17,4093,65536]){
  const v=plaintextMACVerifier(key);for(let i=0;i<input.length;i+=step)v.update(input.subarray(i,i+step));assert.equal(v.finish(),true,'size='+vector.size+' step='+step);
 }
 if(input.length){const tampered=Buffer.from(input);tampered[tampered.length-1]^=1;const bad=plaintextMACVerifier(key);bad.update(tampered);assert.equal(bad.finish(),false);}
 const wrongKey=Buffer.from(key);wrongKey[31]^=1;const wrong=plaintextMACVerifier(wrongKey);wrong.update(input);assert.equal(wrong.finish(),false);
 console.log('PASS independent Python batch oracle/Node streaming plaintextMAC, size='+vector.size);
}
console.log('transfer-plaintext-mac: all documented-protocol vectors pass; no network or service');

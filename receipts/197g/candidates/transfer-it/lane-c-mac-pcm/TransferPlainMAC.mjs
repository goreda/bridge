// Plaintext MEGA meta-MAC used by transfer.it's direct download contract.
// Independent streaming implementation, bounded to AES-block buffering.
import {createCipheriv,timingSafeEqual} from 'node:crypto';
export function plaintextMACVerifier(fileKey) {
 if(!Buffer.isBuffer(fileKey)||fileKey.length!==32)throw Error('invalid_mac_key');
 const key=Buffer.from(fileKey.subarray(0,16).map((v,i)=>v^fileKey[i+16]));
 const nonce=fileKey.subarray(16,24),iv=Buffer.concat([nonce,nonce]);
 const condense=createCipheriv('aes-128-cbc',key,Buffer.alloc(16));condense.setAutoPadding(false);
 let chunkSize=131072,inChunk=0,partial=Buffer.alloc(0),last,condensed=Buffer.alloc(16),closed=false;
 let chunk=createCipheriv('aes-128-cbc',key,iv);chunk.setAutoPadding(false);
 function write(bytes){const out=chunk.update(bytes);if(out.length)last=Buffer.from(out.subarray(-16));}
 function finishChunk(){
  if(partial.length){const block=Buffer.alloc(16);partial.copy(block);write(block);partial=Buffer.alloc(0);}
  chunk.final();if(!last)throw Error('invalid_mac_state');
  condensed=condense.update(last);chunkSize=Math.min(1048576,chunkSize+131072);inChunk=0;last=undefined;
  chunk=createCipheriv('aes-128-cbc',key,iv);chunk.setAutoPadding(false);
 }
 return Object.freeze({update(data){
  if(closed)throw Error('mac_finished');
  let offset=0;
  while(offset<data.length){
   const take=Math.min(data.length-offset,chunkSize-inChunk),part=data.subarray(offset,offset+take);offset+=take;inChunk+=take;
   const combined=partial.length?Buffer.concat([partial,part]):part;
   const whole=combined.length-combined.length%16;
   if(whole)write(combined.subarray(0,whole));partial=Buffer.from(combined.subarray(whole));
   if(inChunk===chunkSize)finishChunk();
  }
 },finish(){
  if(closed)throw Error('mac_finished');closed=true;
  if(inChunk)finishChunk();condense.final();
  const mac=Buffer.alloc(8);
  mac.writeUInt32BE((condensed.readUInt32BE(0)^condensed.readUInt32BE(4))>>>0,0);
  mac.writeUInt32BE((condensed.readUInt32BE(8)^condensed.readUInt32BE(12))>>>0,4);
  return timingSafeEqual(mac,fileKey.subarray(24,32));
 }});
}

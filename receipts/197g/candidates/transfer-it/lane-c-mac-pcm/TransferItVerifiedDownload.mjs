// Bounded source-byte preparation with whole-file MAC against supplied node key.
// Authenticity of remote metadata and current service behavior remain separate.
import {resolveTransferFile, TransferSourceError} from './TransferItVerifiedSource.mjs';
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
const fail=kind=>{throw new TransferSourceError(kind);};
export async function prepareTransferFile({output,byteLimit=64*1024*1024,timeoutMs=15000,signal,...options}={}) {
 if(!path.isAbsolute(output??'')||!Number.isSafeInteger(byteLimit)||byteLimit<1)fail('invalid_input');
 if(!Number.isFinite(timeoutMs)||timeoutMs<1||timeoutMs>300000)fail('invalid_timeout');
 const controller=new AbortController();let timed=false,created=false,finished=false,handle;
 const abort=()=>controller.abort();signal?.addEventListener('abort',abort,{once:true});if(signal?.aborted)abort();
 const timer=setTimeout(()=>{timed=true;abort();},timeoutMs);
 try {
  const source=await resolveTransferFile({...options,timeoutMs,signal:controller.signal});
  if(source.bytes>byteLimit)fail('file_limit');
  const fixtureOrigin=options.testGateway?new URL(options.testGateway).origin:undefined;
  let target=new URL(source.url),response;
  for(let redirects=0;;redirects++) {
   if(target.username||target.password||(target.protocol!=='https:'&&!(target.protocol==='http:'&&target.hostname==='127.0.0.1'&&target.origin===fixtureOrigin)))fail('insecure_redirect');
   const headers=target.origin===source.headerOrigin?source.headers:{};
   response=await fetch(target,{headers,redirect:'manual',signal:controller.signal});
   if([301,302,303,307,308].includes(response.status)) {
    await response.body?.cancel();if(redirects>=3)fail('redirect_limit');
    const location=response.headers.get('location');if(!location)fail('bad_redirect');
    target=new URL(location,target);continue;
   }
   break;
  }
  if(response.status!==200){await response.body?.cancel();fail('http_status');}
  const length=response.headers.get('content-length');
  if(length!==null&&(!/^\d+$/.test(length)||Number(length)!==source.bytes)){await response.body?.cancel();fail('size_mismatch');}
  if(/(?:text\/html|application\/xhtml)/i.test(response.headers.get('content-type')??'')){await response.body?.cancel();fail('not_media');}
  handle=await fs.promises.open(output,'wx',0o600);created=true;
  let size=0;const hash=createHash('sha256'),verifier=source.createVerifier();
  for await(const chunk of response.body) {
   size+=chunk.length;if(size>byteLimit||size>source.bytes)fail('file_limit');
   if(controller.signal.aborted)fail('cancelled');
   verifier.update(chunk);hash.update(chunk);await handle.writeFile(chunk);
  }
  if(size!==source.bytes)fail('size_mismatch');
  if(!verifier.finish())fail('integrity_mismatch');
  await handle.close();handle=undefined;finished=true;
  return Object.freeze({fileURL:pathToFileURL(output).href,bytes:size,sha256:hash.digest('hex'),integrity:'node-key-mac'});
 }catch(error){
  if(timed)fail('timeout');if(signal?.aborted)fail('cancelled');
  if(error instanceof TransferSourceError)throw error;
  fail(error?.code==='EEXIST'?'destination_exists':'transport');
 }finally{
  clearTimeout(timer);signal?.removeEventListener('abort',abort);abort();await handle?.close();
  if(created&&!finished)await fs.promises.rm(output,{force:true});
 }
}

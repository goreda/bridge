// Shared production dispatch. Test gateway never comes from request JSON.
import fs from 'node:fs/promises';import path from 'node:path';
import {prepareTransferFile} from '../transfer-candidate/TransferItVerifiedDownload.mjs';
import {prepareMegaFile} from '../mega-candidate/MegaVerifiedSource.mjs';
export async function prepareRequestFile(request,{testGateway}={}){
 const stat=await fs.lstat(request);
 if(!stat.isFile()||stat.size>16384||(stat.mode&0o077)!==0)throw Error('request');
 const value=JSON.parse(await fs.readFile(request,'utf8'));
 if(!path.isAbsolute(value.output)||path.dirname(value.output)!==path.dirname(request)||path.basename(value.output)!=='media.bin')throw Error('output');
 if(value.kind==='transfer')return prepareTransferFile({link:value.link,filename:value.filename,output:value.output,timeoutMs:value.timeoutMs,testGateway});
 if(value.kind==='mega'){
  const result=await prepareMegaFile({link:value.link,output:value.output,timeoutMs:value.timeoutMs,testGateway});return {...result,integrity:'megajs-whole-file-mac'};
 }
 throw Error('kind');
}

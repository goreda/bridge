// node prepare-source.mjs PRIVATE_REQUEST_PATH. Stdout is bounded JSON only.
// Deploy beside ../transfer-candidate and ../mega-candidate measured modules.
import fs from 'node:fs/promises';import path from 'node:path';
import {prepareTransferFile} from '../transfer-candidate/TransferItVerifiedDownload.mjs';
import {prepareMegaFile} from '../mega-candidate/MegaVerifiedSource.mjs';
try{
 const request=process.argv[2];const stat=await fs.lstat(request);
 if(!stat.isFile()||stat.size>16384||(stat.mode&0o077)!==0)throw Error('request');
 const value=JSON.parse(await fs.readFile(request,'utf8'));
 if(!path.isAbsolute(value.output)||path.dirname(value.output)!==path.dirname(request)||path.basename(value.output)!=='media.bin')throw Error('output');
 let result;
 if(value.kind==='transfer')result=await prepareTransferFile({link:value.link,filename:value.filename,output:value.output,timeoutMs:value.timeoutMs});
 else if(value.kind==='mega'){result=await prepareMegaFile({link:value.link,output:value.output,timeoutMs:value.timeoutMs});result={...result,integrity:'megajs-whole-file-mac'};}
 else throw Error('kind');
 process.stdout.write(JSON.stringify(result));
}catch{
 // Never print exception text, URL/key/path or external-service body.
 process.stderr.write('source_preparation_refused\n');process.exitCode=1;
}

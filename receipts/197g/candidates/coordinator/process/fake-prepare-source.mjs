// Controlled process-boundary fixture, not a live resolver.
import fs from 'node:fs/promises';import path from 'node:path';import {pathToFileURL} from 'node:url';
const request=process.argv[2],v=JSON.parse(await fs.readFile(request,'utf8'));
const mode=new URL(v.link).pathname.split('/').filter(Boolean).at(-1);
if(mode==='slow'){process.on('SIGTERM',()=>{});setInterval(()=>{},1000);}
else if(mode==='noisy')process.stdout.write('x'.repeat(70000));
else if(mode==='refuse'){process.stderr.write('sensitive_external_message');process.exitCode=1;}
else if(mode==='badjson')process.stdout.write('{}');
else{
 const stat=await fs.stat(request);if((stat.mode&0o777)!==0o600)throw Error('request permissions');
 if(process.argv.some(x=>x.includes('SecretKey')))throw Error('key in argv');
 if(mode==='symlink')await fs.symlink(request,v.output);else await fs.writeFile(v.output,Buffer.alloc(128,42),{flag:'wx',mode:0o600});
 process.stdout.write(JSON.stringify({fileURL:pathToFileURL(mode==='escape'?path.join(path.dirname(v.output),'wrong'):v.output).href,bytes:mode==='wrongsize'?127:128,integrity:v.kind==='mega'?'megajs-whole-file-mac':'node-key-mac'}));
}

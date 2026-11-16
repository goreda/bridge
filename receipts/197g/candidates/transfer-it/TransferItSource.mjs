// Controlled implementation of an unofficial transfer.it contract, not a live
// service claim. Source selection only; caller keeps decode/render ownership.
import { createDecipheriv } from 'node:crypto';
export class TransferSourceError extends Error {
  constructor(kind) { super(kind); this.name='TransferSourceError';this.kind=kind; }
}
const fail = kind => { throw new TransferSourceError(kind); };
function base64(raw) {
  if (typeof raw !== 'string' || !/^[A-Za-z0-9_-]+$/.test(raw)) fail('bad_metadata');
  const bytes=Buffer.from(raw,'base64url');
  if (bytes.toString('base64url')!==raw) fail('bad_metadata');return bytes;
}
function nameOf(node) {
  const key=base64(node.k), attr=base64(node.a);
  if (![16,32].includes(key.length) || !attr.length || attr.length%16) fail('bad_metadata');
  const aes=key.length===16?key:Buffer.from(key.subarray(0,16).map((v,i)=>v^key[i+16]));
  try {
    const decipher=createDecipheriv('aes-128-cbc',aes,Buffer.alloc(16));decipher.setAutoPadding(false);
    const text=Buffer.concat([decipher.update(attr),decipher.final()]).toString('utf8').replace(/\x00+$/,'');
    if (!text.startsWith('MEGA')) fail('bad_metadata');
    const name=JSON.parse(text.slice(4)).n;
    if(typeof name!=='string'||!name||name==='.'||name==='..'||/[\x00-\x1f\x7f/\\]/.test(name)) fail('bad_metadata');return name;
  } catch { fail('bad_metadata'); }
}
export async function resolveTransferFile({link, filename, signal, timeoutMs=15000, testGateway}={}) {
  let page;try{page=new URL(link);}catch{fail('invalid_link');}
  if(page.protocol!=='https:'||page.hostname!=='transfer.it'||page.port||page.username||page.password||page.search||page.hash||!/^\/t\/[A-Za-z0-9_-]+\/?$/.test(page.pathname))fail('invalid_link');
  if(typeof filename!=='string'||!filename||filename.includes('/')||filename.includes('\\')||/[\x00-\x1f\x7f]/.test(filename))fail('invalid_filename');
  if(!Number.isFinite(timeoutMs)||timeoutMs<1||timeoutMs>300000)fail('invalid_timeout');
  const handle=page.pathname.split('/')[2];
  const gateway=new URL(testGateway??'https://bt7.api.mega.co.nz/');
  if(testGateway&&(gateway.protocol!=='http:'||gateway.hostname!=='127.0.0.1'))fail('invalid_fixture_gateway');
  const controller=new AbortController();let timed=false;
  const abort=()=>controller.abort();signal?.addEventListener('abort',abort,{once:true});if(signal?.aborted)controller.abort();
  const timer=setTimeout(()=>{timed=true;controller.abort();},timeoutMs);
  try {
    async function command(value,query={}) {
      const url=new URL('cs',gateway);url.search=new URLSearchParams({id:crypto.randomUUID(),...query});
      const response=await fetch(url,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify([value]),redirect:'error',signal:controller.signal});
      if(response.status!==200)fail('http_status');
      if(Number(response.headers.get('content-length'))>1024*1024)fail('metadata_limit');
      const chunks=[];let size=0;
      for await(const chunk of response.body){size+=chunk.length;if(size>1024*1024){controller.abort();fail('metadata_limit');}chunks.push(chunk);}
      let values;try{values=JSON.parse(Buffer.concat(chunks));}catch{fail('bad_metadata');}
      if(!Array.isArray(values)||values.length!==1)fail('bad_metadata');
      if(typeof values[0]==='number'&&values[0]<0)fail('service_refused');return values[0];
    }
    const info=await command({a:'xi',xh:handle});
    if(!info||typeof info!=='object')fail('bad_metadata');
    if(info.pw)fail('password_required');
    const tree=await command({a:'f',c:1,r:1},{x:handle});
    if(!Array.isArray(tree?.f)||tree.f.length>10000)fail('bad_metadata');
    const matches=[];
    for(const node of tree.f) {
      if(node.t!==0)continue;
      if(!/^[A-Za-z0-9_-]+$/.test(node.h??'')||!Number.isSafeInteger(node.s)||node.s<1)fail('bad_metadata');
      if(nameOf(node)===filename)matches.push(node);
    }
    if(!matches.length)fail('missing_file');if(matches.length!==1)fail('ambiguous_file');
    const direct=new URL('cs/g',gateway);direct.search=new URLSearchParams({x:handle,n:matches[0].h,fn:filename});
    // Sensitive headers are scoped to this API origin; the caller must not
    // forward them blindly through redirects. No integrity claim for bytes.
    return Object.freeze({url:direct.href,bytes:matches[0].s,headerOrigin:gateway.origin,
      headers:Object.freeze({'User-Agent':'Mozilla/5.0',Referer:page.href,Origin:'https://transfer.it'})});
  } catch(error) {
    if(error instanceof TransferSourceError)throw error;
    if(timed)fail('timeout');if(controller.signal.aborted)fail('cancelled');fail('transport');
  } finally {clearTimeout(timer);signal?.removeEventListener('abort',abort);}
}

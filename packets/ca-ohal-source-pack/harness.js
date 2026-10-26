// shared live-test harness: embedded static server + headless chrome over CDP
const http=require('http'),fs=require('fs'),path=require('path'),{spawn}=require('child_process');
const ROOT=path.join(__dirname,'..');
const M={'.html':'text/html','.js':'text/javascript','.ttf':'font/ttf','.png':'image/png','.svg':'image/svg+xml'};
function serve(port){return new Promise(res=>{const s=http.createServer((req,rsp)=>{
  let p=path.join(ROOT,decodeURIComponent(req.url.split('?')[0].split('#')[0])); if(p.endsWith('/'))p+='index.html';
  fs.readFile(p,(e,d)=>{if(e){rsp.writeHead(404);rsp.end('nf');return;}rsp.writeHead(200,{'content-type':M[path.extname(p)]||'application/octet-stream','cache-control':'no-store'});rsp.end(d);});
}).listen(port,()=>res(s));});}
async function launch(port,url,extra){
  const prof=fs.mkdtempSync(require('os').tmpdir()+'/ca2-prof-'); if(!extra||!extra.some(function(a){return a.indexOf('--user-data-dir')===0})) extra=(extra||[]).concat(['--user-data-dir='+prof]); // fresh profile: saved ca2.config in a shared profile silently restores old P and poisons measurements
  const ch=spawn('google-chrome',['--headless=new','--no-sandbox',...((extra||[]).includes('--gpu-ok')?[]:['--disable-gpu']),'--autoplay-policy=no-user-gesture-required','--remote-debugging-port='+port,'--disable-background-timer-throttling','--disable-renderer-backgrounding','--disable-backgrounding-occluded-windows','--window-size=1300,800',...(extra||[]),url],{stdio:'ignore'});
  let tabs=null;
  for(let i=0;i<40;i++){await new Promise(r=>setTimeout(r,500));try{tabs=await (await fetch('http://127.0.0.1:'+port+'/json')).json();if(tabs&&tabs.length)break;}catch(e){}}
  if(!tabs||!tabs.length)throw new Error('chrome debug port never came up');
  const t=tabs.find(x=>x.type==='page'); const ws=new WebSocket(t.webSocketDebuggerUrl); await new Promise(r=>ws.onopen=r);
  let id=0,p={},errs=[]; ws.onmessage=m=>{const d=JSON.parse(m.data); if(d.id&&p[d.id]){p[d.id](d.result);delete p[d.id];} if(d.method==='Runtime.exceptionThrown') errs.push((d.params.exceptionDetails.exception&&d.params.exceptionDetails.exception.description||d.params.exceptionDetails.text||'').slice(0,300));};
  const send=(method,params={})=>new Promise(r=>{p[++id]=r;ws.send(JSON.stringify({id,method,params}));});
  await send('Runtime.enable'); await send('Page.enable');
  const ev=async e=>{const r=await send('Runtime.evaluate',{expression:e,returnByValue:true,awaitPromise:true}); if(r.exceptionDetails) return 'EXC:'+JSON.stringify(r.exceptionDetails).slice(0,400); return r.result.value;};
  return {send,ev,errs,sleep:ms=>new Promise(r=>setTimeout(r,ms)),close:()=>{try{ch.kill()}catch(e){}try{ws.close()}catch(e){}},mouse:(x,y,type='mouseMoved',extra2={})=>send('Input.dispatchMouseEvent',Object.assign({type,x,y},extra2)),
  shot:async p=>{const r=await send('Page.captureScreenshot',{format:'png'});require('fs').writeFileSync(p,Buffer.from(r.data,'base64'));return p}};
}
module.exports={serve,launch};

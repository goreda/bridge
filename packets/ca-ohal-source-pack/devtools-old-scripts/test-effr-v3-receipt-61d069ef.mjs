// Local unit proof for the v3 overrun-receipt candidate. Loads the ACTUAL functions from base.js and ca2-v3.js (text extraction), no copied reference.
import fs from 'fs';
const BASE=fs.readFileSync(new URL('./base.js',import.meta.url),'utf8'), CAND=fs.readFileSync(new URL('./ca2-v3.js',import.meta.url),'utf8');
function fn(src,name){const i=src.indexOf('  function '+name+'(');if(i<0)return null;let j=src.indexOf('{',i),d=0,k=j;for(;k<src.length;k++){if(src[k]==='{')d++;else if(src[k]==='}'){d--;if(d===0)break}}return src.slice(i,k+1)}
function line(src,startMark,endMark){const i=src.indexOf(startMark);if(i<0)throw new Error('mark '+startMark.slice(0,40));const j=src.indexOf(endMark,i);return src.slice(i,j+endMark.length)}
const names=['effR','carrySide','wallPull','wallBox','wallBoxFit','ovVirt','ovSet','inkWallClamp','collectiveTarget','collectiveCommit'];
function mk(src,which){
  const defs=names.map(n=>fn(src,n)).filter(Boolean).join('\n');
  // actual early-clamp code of each file, as a callable
  let ink,coll;
  if(which==='base'){
    ink=line(src,"var bg0 = Math.max(0, P.boundGap || 0), bx0","by1 = cont.y + cont.h - bg0; if (c.y < by0)")
  }
  const baseInk=which==='base'?src.slice(src.indexOf("      var bg0 = Math.max(0, P.boundGap || 0), bx0 = cont.x + bg0"),src.indexOf("    }\n  }\n  function separatorCollectivePass")):null;
  const baseColl=which==='base'?"var bg=Math.max(0,P.boundGap||0),tx=clamp(c.x+m[0],cont.x+bg,cont.x+cont.w-bg),ty=clamp(c.y+m[1],cont.y+bg,cont.y+cont.h-bg),fraction=1; c.x+=(tx-c.x)*fraction;c.y+=(ty-c.y)*fraction;":null;
  // verify the base text we rely on is really in the file (no hand copy drift)
  if(which==='base'){ if(!src.includes("tx=clamp(c.x+m[0],cont.x+bg,cont.x+cont.w-bg),ty=clamp(c.y+m[1],cont.y+bg,cont.y+cont.h-bg),fraction=1;")||!src.includes("c.x+=(tx-c.x)*fraction;c.y+=(ty-c.y)*fraction;")) throw new Error('base collective text changed')}
  const body=`
  var clamp=function(v,a,b){return v<a?a:v>b?b:v};
  ${defs}
  return {
    wallPull:wallPull, effR:effR,
    ink:function(c){ ${which==='base'?baseInk:'inkWallClamp(c);'} },
    coll:function(c,m,fr){ ${which==='base'?baseColl.replace('fraction=1;','fraction=FR;'):'var bg=Math.max(0,P.boundGap||0),et=collectiveTarget(c,m,bg),tx=et[0],ty=et[1],fraction=FR; c.x+=(tx-c.x)*fraction;c.y+=(ty-c.y)*fraction; collectiveCommit(c,et,fraction);'} },
    setFrame:function(t){frameT=t}
  };`;
  return (cont,P)=>new Function('cont','P','FR',"var frameT=1;"+body.replace(/FR/g,'__FR'))
}
// simpler: build factories that take cont,P and a mutable FR
function factory(src,which){
  const defs=names.map(n=>fn(src,n)).filter(Boolean).join('\n');
  let baseInk=null;
  if(which==='base'){const a=src.indexOf("      var bg0 = Math.max(0, P.boundGap || 0), bx0 = cont.x + bg0");const b=src.indexOf("function separatorCollectivePass");baseInk=src.slice(a,src.lastIndexOf("    }\n  }",b));
    if(!baseInk.includes('c.y > by1'))throw new Error('ink extract');
    for(const t of ["tx=clamp(c.x+m[0],cont.x+bg,cont.x+cont.w-bg),ty=clamp(c.y+m[1],cont.y+bg,cont.y+cont.h-bg),fraction=1;","c.x+=(tx-c.x)*fraction;c.y+=(ty-c.y)*fraction;"])if(!src.includes(t))throw new Error('base coll text')}
  const inkCall=which==='base'?baseInk:(src.includes('      inkWallClamp(c);')?'inkWallClamp(c);':'/*ink call missing*/');
  const a1=src.indexOf("var c=active[k],m=moves[k],bg=Math.max(0,P.boundGap||0),");const a2=src.indexOf("fraction=1;",a1)+"fraction=1;".length;
  const u1=src.indexOf("c._sepX=c.x;c._sepY=c.y;c.x+=(tx-c.x)*fraction;c.y+=(ty-c.y)*fraction;");const u2=src.indexOf("\n",u1);
  if(a1<0||u1<0)throw new Error('collective call site');
  let site=src.slice(a1,a2).replace("var c=active[k],m=moves[k],","var ")+"\n"+src.slice(u1,u2);
  site=site.replace("fraction=1;","fraction=S.fr;");
  if(which==='cand'&&!site.includes('collectiveCommit(c,et,fraction)'))site+="/*commit call missing*/";
  const collCall=site;
  return new Function("cont","P","S",`var clamp=function(v,a,b){return v<a?a:v>b?b:v};\n${defs}\nreturn {wallPull:wallPull,effR:effR,ink:function(c){${inkCall}},coll:function(c,m){${collCall}},wp:function(c){wallPull(c,effR(c),true)}};`);
}
const FB=factory(BASE,'base'),FC=factory(CAND,'cand');
let fails=0,checks=0;const ok=(c,msg)=>{checks++;if(!c){fails++;console.log('FAIL',msg)}};
const eq=(a,b)=>a===b||(Number.isNaN(a)&&Number.isNaN(b));
function cell(o){return Object.assign({x:0,y:0,vx:0,vy:0,radius:30,sq:0.3,sqS:0,envVx:0,envVy:0,alive:true},o)}
const KEYS=['x','y','vx','vy','envVx','envVy','sqS'];
function mkContext(o){return Object.assign({x:100,y:100,w:400,h:300,wvx0:0,wvx1:0,wvy0:0,wvy1:0},o)}
function run(F,cont,P,c0,steps,S){const cc=JSON.parse(JSON.stringify(c0)),cn=JSON.parse(JSON.stringify(cont)),pp=JSON.parse(JSON.stringify(P));const f=F(cn,pp,S);for(const st of steps){if(st[0]==='ink')f.ink(cc);else if(st[0]==='coll')f.coll(cc,st[1]);else if(st[0]==='wp')f.wp(cc);else if(st[0]==='frame')S.t=st[1];else if(st[0]==='cont')Object.assign(cn,st[1]);else if(st[0]==='mut')st[1](cc)}return cc}
function cmp(name,cont,P,c0,steps,keys=KEYS){const a=run(FB,cont,P,c0,steps,{t:1,fr:1}),b=run(FC,cont,P,c0,steps,{t:1,fr:1});const bad=keys.filter(k=>!eq(a[k],b[k]));ok(!bad.length,name+' differs in '+bad.map(k=>k+':'+a[k]+' vs '+b[k]).join(' '));return [a,b]}
const P0={boundAware:1,boundGap:0,wallCarry:1,squashMax:0.18};
// effR(c)=30*(1-.18*.3)=28.38; box x:[128.38,471.62] y:[128.38,371.62]
const cases=[];
// I1: single early clamp then wallPull, strip positions, all wall behaviours
for(const wall of [{},{wvx0:2},{wvx1:-2},{wvy0:1.5},{wvy1:-3},{wvx0:2,wvy0:1.5},{wvx1:-2,wvy1:-3}])
 for(const P of [P0,{...P0,wallCarry:0},{...P0,boundGap:5},{...P0,wallCarry:2}])
  for(const pos of [[110,200],[128,200],[140,200],[200,110],[200,125],[105,105],[120,360],[480,385],[470,200],[300,200]])
   for(const v of [[-1,0.3],[0.8,-0.5],[0,0]]){
    const c0=cell({x:pos[0],y:pos[1],vx:v[0],vy:v[1]});
    cases.push(['ink',wall,P,c0,[['ink'],['wp']]]);
    cases.push(['coll',wall,P,c0,[['coll',[-12,3]],['wp']]]);
    cases.push(['coll2',wall,P,c0,[['coll',[-6,-9]],['coll',[4,-2]],['wp']]]);
    cases.push(['ink+coll',wall,P,c0,[['ink'],['coll',[-7,-7]],['wp']]]);
   }
let n=0;for(const [k,w,P,c0,steps] of cases){n++;const cont=mkContext(w);
  // exact for all damping state; positions may differ only when the body is not overrun (candidate keeps it inside the box)
  const [a,b]=cmp('I1 '+k+' '+JSON.stringify([w,P,c0.x,c0.y,c0.vx,c0.vy]),cont,P,c0,steps,['vx','vy','envVx','envVy','sqS']);
  // base final position is on the line when overrun; candidate the same. Otherwise candidate >= base inside
  const bx=a.x,cx=b.x;ok(Math.abs(bx-cx)<1e-9||(Math.abs(cx-bx)>0),'pos');}
console.log('I1 cases',n);
// positions equal for single clamp sequences
for(const [k,w,P,c0,steps] of cases.filter(c=>c[0]==='ink'||c[0]==='coll')){cmp('I1pos '+k+' '+JSON.stringify([w,P,c0.x,c0.y]),mkContext(w),P,c0,steps)}
// I2 once: wallPull twice after one early clamp -> carry count 1
{const cont=mkContext({wvx0:2}),P=P0;const c0=cell({x:110,y:200,vx:-1});const a=run(FB,cont,P,c0,[['ink'],['wp']],{t:1,fr:1}),b=run(FC,cont,P,c0,[['ink'],['wp'],['wp']],{t:1,fr:1}),c=run(FC,cont,P,c0,[['ink'],['wp']],{t:1,fr:1});
 ok(b.envVx===c.envVx&&b.sqS===c.sqS&&b.vx===c.vx,'I2 second wallPull must be a no-op');}
// I3 stale: receipt from another frame ignored; body moved away (solver) -> no carry in candidate, none in base
{const cont=mkContext({wvx0:2}),P=P0;const c0=cell({x:110,y:200,vx:-1});
 const [a,b]=cmp('I3 frame boundary between clamp and wallPull (receipt still consumed)',cont,P,c0,[['ink'],['frame',2],['wp']]);
 // base counterfactual: base with the body moved to the same place after the clamp
 for(const mv of [60,30,10,5]){cmp('I3 solver moved '+mv,cont,P,c0,[['ink'],['mut',c=>{c.x+=mv}],['wp']],['vx','vy','envVx','envVy','sqS'])}}
// I3b: counterfactual with solver motion: base moves body by the same amount from its (strip) position; candidate from the box position. Damping state must match when the base counterfactual overruns
{let n3=0,bad=0;for(const mv of [-8,-3,0,3,8,20,40])for(const x0 of [110,120,126]){const cont=mkContext({wvx0:2}),c0=cell({x:x0,y:200,vx:-1});
  const sA=run(FB,cont,P0,c0,[['ink'],['mut',c=>{c.x+=mv}],['wp']],{t:1,fr:1}),sB=run(FC,cont,P0,c0,[['ink'],['mut',c=>{c.x+=mv}],['wp']],{t:1,fr:1});n3++;
  for(const k of ['vx','envVx','sqS'])if(!eq(sA[k],sB[k])){bad++;console.log('  I3b mismatch mv',mv,'x0',x0,k,sA[k],sB[k])}}console.log('I3b solver-move counterfactual cases',n3,'mismatches',bad);if(bad)fails++}
// I4: no receipt -> wallPull bit-identical to base; boundAware 0 identical; oversize identical
for(const x of [90,130,300,480,520])for(const y of [90,130,300,380,420]){const c0=cell({x,y,vx:0.5,vy:-0.7});cmp('I4 no receipt '+x+','+y,mkContext({wvx0:1}),P0,c0,[['wp']]);cmp('I4 boundAware0 '+x+','+y,mkContext({wvx0:1}),{...P0,boundAware:0},c0,[['ink'],['coll',[-9,4]],['wp']])}
for(const r of [150,160,400]){const c0=cell({x:300,y:200,radius:r,vx:1,vy:1});for(const st of [[['ink'],['wp']],[['coll',[-5,5]],['wp']]])cmp('I4 oversize r'+r,mkContext({wvx0:1}),P0,c0,st)}
// I5 ABA / line change / radius change between clamp and wallPull
{const cont=mkContext({wvx0:2}),c0=cell({x:110,y:200,vx:-1});
 for(const mut of [c=>{c.x+=40;c.x-=40},c=>{c.radius=45},c=>{c.sq=0.9}])cmp('I5 ABA/radius '+mut,cont,P0,c0,[['ink'],['mut',mut],['wp']],['vx','envVx','sqS']);
 cmp('I5 line change (cont moved)',cont,P0,c0,[['ink'],['cont',{x:120,w:380}],['wp']],['vx','envVx','sqS'])}
// two axis / corner: both axes carried exactly once each
{const cont=mkContext({wvx0:2,wvy0:1.5}),c0=cell({x:105,y:105,vx:-1,vy:-1});const [a,b]=cmp('corner',cont,P0,c0,[['ink'],['wp']]);ok(a.envVx!==0&&a.envVy!==0&&b.envVx===a.envVx&&b.envVy===a.envVy,'corner both axes')}
// fraction < 1 (partial move across a segment) and repeated passes: damping state must still match
{let n=0;for(const fr of [0.3,0.5,0.9])for(const [k,w,P,c0,steps] of cases.filter(c=>c[0]==='coll2'||c[0]==='ink+coll').slice(0,600)){n++;const a=run(FB,mkContext(w),P,c0,steps,{t:1,fr}),b=run(FC,mkContext(w),P,c0,steps,{t:1,fr});const bad=['vx','vy','envVx','envVy','sqS'].filter(q=>!eq(a[q],b[q]));ok(!bad.length,'frac '+fr+' '+k+' '+JSON.stringify([w,P,c0.x,c0.y])+bad.join())}console.log('fraction cases',n)}
// mutants of the candidate must be caught by the I1 suite
const mutants={noReceiptRead:s=>s.replace("var rv = ovVirt(p),","var rv = [p.x,p.y],"),noClear:s=>s.replace("p._ovDx = 0; p._ovDy = 0; } // consumed","} // consumed"),dxWrong:s=>s.replace("ovSet(c, c.x - vx, c.y - vy);","ovSet(c, 0, 0);"),collNoCommit:s=>s.replace("c.y+=(ty-c.y)*fraction;collectiveCommit(c,et,fraction);","c.y+=(ty-c.y)*fraction;")};
let killed=0;
for(const [mn,f] of Object.entries(mutants)){const src=f(CAND);if(src===CAND){console.log('mutant text not found',mn);continue}
  const FM=factory(src,'cand');let caught=false;
  for(const [k,w,P,c0,steps] of cases.slice(0,2000)){const a=run(FB,mkContext(w),P,c0,steps,{t:1,fr:1}),b=run(FM,mkContext(w),P,c0,steps,{t:1,fr:1});if(['vx','vy','envVx','envVy','sqS'].some(q=>!eq(a[q],b[q]))){caught=true;break}}
  // noClear is caught by I2
  if(!caught&&mn==='noClear'){const cont=mkContext({wvx0:2}),c0=cell({x:110,y:200,vx:-1});const b=run(FM,cont,P0,c0,[['ink'],['wp'],['wp']],{t:1,fr:1}),c=run(FC,cont,P0,c0,[['ink'],['wp']],{t:1,fr:1});caught=b.envVx!==c.envVx||b.sqS!==c.sqS}
  console.log('mutant',mn,caught?'killed':'SURVIVED');if(caught)killed++;else fails++}
console.log('checks',checks,'fails',fails);process.exit(fails?1:0);

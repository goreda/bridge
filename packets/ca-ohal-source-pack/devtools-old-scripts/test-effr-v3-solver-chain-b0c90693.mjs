// v3 receipt: chain coll->ink and the ACTUAL constraintSolver between receipt set and consume (not a rigid offset).
import fs from 'fs';
const BASE=fs.readFileSync(new URL('./base.js',import.meta.url),'utf8'), CAND=fs.readFileSync(new URL('./ca2-v3.js',import.meta.url),'utf8');
function fn(src,name){const i=src.indexOf('  function '+name+'(');if(i<0)return null;let j=src.indexOf('{',i),d=0,k=j;for(;k<src.length;k++){if(src[k]==='{')d++;else if(src[k]==='}'){d--;if(d===0)break}}return src.slice(i,k+1)}
const names=['effR','carrySide','wallPull','wallBox','wallBoxFit','ovVirt','ovSet','inkWallClamp','collectiveTarget','collectiveCommit','constraintSolver'];
function factory(src,which){
  const defs=names.map(n=>fn(src,n)).filter(Boolean).join('\n');
  let inkCall;
  if(which==='base'){const a=src.indexOf("      var bg0 = Math.max(0, P.boundGap || 0), bx0 = cont.x + bg0");const b=src.indexOf("function separatorCollectivePass");inkCall=src.slice(a,src.lastIndexOf("    }\n  }",b))}
  else{if(!src.includes('      inkWallClamp(c);'))throw new Error('ink call');inkCall='inkWallClamp(c);'}
  const a1=src.indexOf("var c=active[k],m=moves[k],bg=Math.max(0,P.boundGap||0),");const a2=src.indexOf("fraction=1;",a1)+11;
  const u1=src.indexOf("c._sepX=c.x;c._sepY=c.y;c.x+=(tx-c.x)*fraction;c.y+=(ty-c.y)*fraction;");const u2=src.indexOf("\n",u1);
  const site=src.slice(a1,a2).replace("var c=active[k],m=moves[k],","var ").replace("fraction=1;","fraction=1;")+"\n"+src.slice(u1,u2);
  return new Function('cont','P','cells',`var clamp=function(v,a,b){return v<a?a:v>b?b:v}; var frameT=1; var axisInfo={segs:null}; var LW=function(){return 2}, DD=1;\n${defs}\nreturn {ink:function(c){${inkCall}},coll:function(c,m){${site}},wp:function(c){wallPull(c,effR(c),true)},solver:function(){constraintSolver()}};`);
}
const FB=factory(BASE,'base'),FC=factory(CAND,'cand');
let seed=12345;const rnd=()=>{seed=(seed*1664525+1013904223)>>>0;return seed/4294967296};
const eq=(a,b)=>a===b||(Number.isNaN(a)&&Number.isNaN(b));
const KEYS=['vx','vy','envVx','envVy','sqS'];
function scenario(){
  const cont={x:100,y:100,w:400,h:300,wvx0:(rnd()<.5?rnd()*3:0),wvx1:(rnd()<.5?-rnd()*3:0),wvy0:(rnd()<.5?rnd()*3:0),wvy1:(rnd()<.5?-rnd()*3:0)};
  const n=2+Math.floor(rnd()*5);const cells=[];
  for(let i=0;i<n;i++){const edge=rnd()<.7;const x=edge?(rnd()<.5?100+rnd()*40:460+rnd()*40):100+rnd()*400,y=edge?(rnd()<.5?100+rnd()*40:360+rnd()*40):100+rnd()*300;
    cells.push({x,y,vx:(rnd()-.5)*3,vy:(rnd()-.5)*3,radius:20+rnd()*25,sq:rnd()*.6,sqS:0,envVx:0,envVy:0,alive:true})}
  const P={boundAware:1,boundGap:rnd()<.3?5:0,wallCarry:rnd()<.8?1:0,squashMax:.18,solverIters:rnd()<.5?4:8,solverOverlap:1,metaballStrength:1,THRESHOLD:1,separatorOn:0,showAxis:0};
  const steps=[];const k=1+Math.floor(rnd()*3);for(let i=0;i<k;i++)steps.push(rnd()<.5?'ink':'coll');
  const ms=cells.map(()=>[ (rnd()-.5)*30,(rnd()-.5)*30]);
  return {cont,cells,P,steps,ms,chain:rnd()<.5};
}
function run(F,sc){const cont=JSON.parse(JSON.stringify(sc.cont)),P=JSON.parse(JSON.stringify(sc.P)),cells=JSON.parse(JSON.stringify(sc.cells));const f=F(cont,P,cells);
  for(const st of sc.steps){cells.forEach((c,i)=>{if(st==='ink')f.ink(c);else f.coll(c,sc.ms[i])});if(sc.chain&&st==='coll')cells.forEach(c=>f.ink(c))} // coll -> ink chain (separatorCollectivePass ends each pass with separatorPass)
  f.solver();cells.forEach(c=>f.wp(c));return cells}
function tally(label,gen,N){let seedSave=seed;let cells=0,bad=0,sc0=0,badScen=0,maxd=0;const pend={};for(let i=0;i<N;i++){const sc=gen();const a=run(FB,sc),b=run(FC,sc);let sb=false;a.forEach((c,j)=>{cells++;const m=KEYS.filter(k=>!eq(c[k],b[j][k]));if(m.length){bad++;sb=true;for(const k of m)maxd=Math.max(maxd,Math.abs(c[k]-b[j][k]))}});sc0++;if(sb)badScen++}
  console.log(label,'scenarios',sc0,'cells',cells,'cells with damping-state mismatch',bad,'scenarios with any mismatch',badScen,'max abs diff',maxd.toFixed(3));return {bad,badScen}}
// A: solver disabled (iters 0) -> chain-only equivalence, must be exactly 0
const noSolver=()=>{const s=scenario();s.P.solverIters=0;return s};
const rA=tally('A chain coll->ink, no solver',noSolver,3000);
// B: actual constraintSolver between set and consume
const rB=tally('B actual constraintSolver',scenario,3000);
// C: solver on but cells far from walls and from each other -> no solver interaction, still exactly 0
const farGen=()=>{const s=scenario();s.cells.forEach(c=>{c.x=200+rnd()*200;c.y=180+rnd()*140});s.cells=[s.cells[0]];s.ms=[s.ms[0]];return s};
const rC=tally('C solver on, isolated interior cell (no solver contact)',farGen,1000);
// D: single cell at the wall, solver on (no pair overlap possible): solver reduces to its centre-box clamp
const oneEdge=()=>{const s=scenario();s.cells=[s.cells[0]];s.ms=[s.ms[0]];return s};
tally('D solver on, one cell near walls (no pairs)',oneEdge,3000);
// E: >=2 cells, report mismatch only when the actual solver moved some cell in either pipeline? count by pair overlap presence
process.exit(0)

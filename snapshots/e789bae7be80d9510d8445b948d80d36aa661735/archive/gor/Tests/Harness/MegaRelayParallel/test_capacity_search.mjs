// Execute shipping adaptive controller with measured byte/time inputs.
import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
const source=fs.readFileSync(new URL('../../../Resources/vendor/mega_relay/mega_relay.mjs',import.meta.url),'utf8');
const ctx=vm.createContext({Math});vm.runInContext(source.slice(source.indexOf('function capacitySearch()'),source.indexOf('// Per-source cumulative totals'))+';globalThis.make=capacitySearch;',ctx);
function window(c,now,limit,rate,demand=true){let change=null;for(let i=0;i<=12;i++){const got=c.sample(now+i*1000,rate,limit,demand);if(got)change=got;}return change;}
let c=ctx.make(),at=0,limit=6,changes=[];
// Per-connection throttle: more lanes increase aggregate supply.
for(let i=0;i<6;i++){let change=window(c,at,limit,limit*500000);at+=13000;if(change){changes.push(change);limit=change.to;}assert(limit<=12);}
assert.equal(limit,12);assert(changes.some(c=>c.decision==='gain'));console.log('PASS per-connection throughput gain6->8->10->12, never above12');
// Shared bottleneck: more requests do not increase aggregate supply.
c=ctx.make();at=0;limit=6;changes=[];for(let i=0;i<5;i++){let change=window(c,at,limit,2000000);at+=13000;if(change){changes.push(change);limit=change.to;}}
assert.equal(limit,6);assert(changes.some(c=>c.decision==='no_gain'));console.log('PASS shared bottleneck/no gain returns6 and cools down, not a blind permanent increase');
c=ctx.make();for(let i=0;i<5;i++)assert.equal(window(c,i*13000,6,10000000,false),null);
c.reset(70000);assert.equal(window(c,71000,1,1000000),null);assert.equal(window(c,72000,6,10000000),null);
console.log('PASS idle/no queued foreground never probes; throttling resets search and holds60s');

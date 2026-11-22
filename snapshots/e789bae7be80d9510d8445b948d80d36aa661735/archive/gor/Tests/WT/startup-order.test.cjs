const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const server=fs.readFileSync(process.env.WT_STARTUP_SOURCE || path.resolve(__dirname,'../../Resources/vendor/wt_server/wt_server.mjs'),'utf8');

// MAX_CONNS startup regression, actual option-evaluation slice. No sockets or
// swarm traffic. Also executes the original bad ordering as a negative control.
{
  const declaration = '// v22.23: connection cap, shared by client opts and the FUNNEL hot marker.\nconst MAX_CONNS = 200;\n';
  assert.equal(server.split(declaration).length, 2, 'one unchanged cap declaration');
  const begin = server.indexOf('const client = new WebTorrent({');
  const end = server.indexOf('// Session lifetime: wire download counts piece payload', begin);
  const capAt = server.indexOf(declaration);
  assert(begin >= 0 && end > begin && capAt < begin, 'MAX_CONNS must initialize before client construction');
  const noCap = server.slice(begin, end).replace(declaration, '');
  const preamble = 'const _dhtPort=1,_dhtOccupied=false,TORRENT_LISTEN_PORT=1,src=null,tmpDir=null,RingStoreFactory=null,_admitStreamingPiece=null,TIER1=[];\n';
  function startup(body) {
    const stats = {ctor: 0, add: 0, maxConns: null};
    const torrent = {setMaxListeners(){},on(){}};
    function WebTorrent(opts) {stats.ctor++;stats.maxConns=opts.maxConns;this.setMaxListeners=()=>{};this.add=()=>{stats.add++;return torrent;};}
    let error = null;
    try {vm.runInNewContext(preamble+body,{WebTorrent,process:{platform:'darwin',stdout:{write(){}}},setInterval(){return{unref(){}};},clearInterval(){}},{timeout:250});}
    catch(e) {error=e;}
    return {stats,error};
  }
  const actual = startup(declaration + noCap);
  assert.equal(actual.error,null);assert.deepEqual(actual.stats,{ctor:1,add:1,maxConns:200});
  const restoredTDZ = startup(noCap + declaration);
  assert.equal(restoredTDZ.error?.name,'ReferenceError');
  assert(restoredTDZ.error.message.includes('MAX_CONNS'));assert.equal(restoredTDZ.stats.ctor,0);assert.equal(restoredTDZ.stats.add,0);
  const wrongValue = startup(declaration.replace('200','201') + noCap);
  assert.notEqual(wrongValue.stats.maxConns,200,'value mutation discriminated');
  console.log('PASS actual WT constructor/add MAX_CONNS=200; original TDZ and changed-value controls RED; dependency/port/timer stubs, not real swarm');
}

// Actual metadata-stage helper, with exact historical pin limits.
{
 const a=server.indexOf('  pinFileEdges('),b=server.indexOf('\n  _evictForPump(',a);assert(a>=0&&b>a);
 const method=server.slice(a,b),declaration='const RING_PIN_HEAD = 2, RING_PIN_TAIL = 3, RING_PIN_MAX = 5;';
 assert.equal(server.split(declaration).length,2);assert(server.indexOf(declaration)<server.indexOf('class RingBufferStore {'));
 assert(server.includes('globalRing.pinFileEdges(fileFirst, fileLast)'));assert(server.includes('globalRing.pinFileEdges(fFirst, fLast)'));
 const body='class Probe {constructor(){this.pinned=new Set()}'+method+'}; const p=new Probe();p.pinFileEdges(10,100);const long=[...p.pinned];p.pinFileEdges(10,11);const short=[...p.pinned];p.pinFileEdges(10,NaN);({long,short,invalid:p.pinned.size})';
 const context={process:{stdout:{write(){}}}};
 assert.equal(JSON.stringify(vm.runInNewContext(declaration+body,context)),JSON.stringify({long:[10,11,98,99,100],short:[10,11],invalid:0}));
 assert.throws(()=>vm.runInNewContext(body,{process:{stdout:{write(){}}}}),/RING_PIN_HEAD/);
 console.log('PASS actual metadata pinFileEdges2head3tail/max5,overlap,invalid; missing-declaration mutant RED');
}

"""Production config and vendor transport route regression, no Internet torrent needed."""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[2]
s=(root/'Resources/vendor/wt_server/wt_server.mjs').read_text()
a=s.index('const client = new WebTorrent({');b=s.index('client.setMaxListeners',a)
config=s[a:b].replace('const client = new WebTorrent','globalThis.client = new WebTorrent')
v=(root/'Resources/vendor/webtorrent-cli/node_modules/webtorrent/lib/torrent.js').read_text();a=v.index('  _drain () {');b=v.index('\n  /**',a)
method=v[a:b]
code='''const assert=require('node:assert/strict');const vm=require('node:vm');
let opts;
for(const platform of ['darwin','linux']) {
 const context={process:{platform},WebTorrent:function(o){opts=o},_dhtPort:4444,TORRENT_LISTEN_PORT:51413,_dhtOccupied:false};vm.runInNewContext(__CONFIG__,context);
 assert.equal(opts.utp,platform!=='darwin');assert.equal(opts.dht.port,4444);assert.equal(opts.tracker,true);assert.equal(opts.lsd,true);assert.equal(opts.utPex,true);
 let tcp=0,udp=0;
 const connection=()=>({once(){},on(){}});
 const net={connect:()=>{tcp++;return connection();}},utp={connect:()=>{udp++;return connection();}};
 const Peer={TYPE_UTP_OUTGOING:'utpOutgoing'},addrToIPPort=()=>['127.0.0.1',6881],RECONNECT_WAIT=[1000];
 const Torrent=eval('(class Torrent {'+__METHOD__+'})');
 const t=new Torrent();t._debug=()=>{};t.destroyed=false;t.paused=false;t._numConns=0;t._numQueued=1000;t.numPeers=0;t.client=opts;
 t._queue={shift:()=>({addr:'127.0.0.1:6881',type:'utpOutgoing',startConnectTimeout(){}})};
 for(let i=0;i<1000;i++)t._drain();
 assert.equal(udp,platform==='darwin'?0:1000);assert.equal(tcp,platform==='darwin'?1000:0);
}
console.log('PASS actual clientopts +vendor _drain1000peer burst: macOS0uTP/1000TCP vs prior1000uTP; DHT/LSD/tracker/PEX unchanged; Linux behavior unchanged');
'''.replace('__CONFIG__',__import__('json').dumps(config)).replace('__METHOD__',__import__('json').dumps(method))
with tempfile.TemporaryDirectory() as temp:
 p=Path(temp)/'test.cjs';p.write_text(code);subprocess.run(['node',str(p)],check=True)
print('NOT_RUN native torrent throughput/timeout stacks after update; expected sampled utp_check_timeouts path removed, not yet measured smoothness')

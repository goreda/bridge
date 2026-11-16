#!/usr/bin/env python3
# Proposed migration for archived v22.14, not a measured gorav integration.
# Removes cross-process sweeping for every mode. Local fixture mode forbids
# public discovery and takes one explicit loopback peer, retaining ring policy.
import pathlib,sys,hashlib
source=pathlib.Path(sys.argv[1]);output=pathlib.Path(sys.argv[2]);s=source.read_text()
anchor='const port = parseInt(process.argv[2]) || 2222;'
assert anchor in s;s=s.replace(anchor,'''const isolated = process.env.GOR_WT_ISOLATED === '1';
const isolatedPeer = process.env.GOR_WT_ISOLATED_PEER;
if (isolated && (!isolatedPeer || !/^127\\.0\\.0\\.1:[1-9][0-9]{0,4}$/.test(isolatedPeer) || Number(isolatedPeer.split(':')[1]) > 65535)) {
  process.stderr.write('ERROR: isolated mode requires exact loopback peer\\n'); process.exit(1);
}
'''+anchor,1)
a=s.index('// v20.2: reap wt_server processes');b=s.index('// v17.5: EPIPE',a)
s=s[:a]+'''// Parent owns only its spawned process and cancellation handle. Never
// enumerate or signal another bridge instance, including older instances.
'''+s[b:]
s=s.replace("const mirrorLog = process.env.GOR_WT_FULL_LOG !== '0';", "const mirrorLog = process.env.GOR_WT_FULL_LOG === '1';")
s=s.replace("  if (!src.includes('&tr=')) {", "  if (!isolated && !src.includes('&tr=')) {",1)
s=s.replace('  dht: { port: _dhtPort },','  dht: isolated ? false : { port: _dhtPort },',1)
s=s.replace('  tracker: true, lsd: !_dhtOccupied, utPex: true,','  tracker: !isolated, lsd: !isolated && !_dhtOccupied, utPex: !isolated,',1)
s=s.replace('  webSeeds: true, maxConns: 1000,','  webSeeds: !isolated, maxConns: isolated ? 2 : 1000,',1)
s=s.replace('  announce: TIER1,','  announce: isolated ? [] : TIER1,',1)
s=s.replace('function injectTrackers(list) {','function injectTrackers(list) {\n  if (isolated) return;',1)
anchor='torrent.setMaxListeners(0);'
assert s.count(anchor)==1;s=s.replace(anchor,anchor+'''
if (isolated) {
  // No tracker/DHT/PEX/webseed fallback. Local fixture peers only.
  const attachLocalPeer = () => torrent.addPeer(isolatedPeer);
  torrent.on('infoHash', attachLocalPeer);
  if (torrent.infoHash) attachLocalPeer();
  process.stdout.write('ISOLATED:loopback peer only, discovery disabled\\n');
}
''',1)
output.write_text(s)
print('archived_input_sha256='+hashlib.sha256(source.read_bytes()).hexdigest())
print('candidate_output_sha256='+hashlib.sha256(output.read_bytes()).hexdigest())

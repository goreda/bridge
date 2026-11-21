# W-gdb-e0-qualification-01: one-shot generic Linux capability gate

2026-11-21. To in2tinct via leg A. Status: OFFERED, AWAITING EXPLICIT ACCEPTANCE; DO NOT EXECUTE YET.

This is a coordination offer containing generic synthetic code, not product stock or a benchmark. No product source, owner data, licensed media, private endpoints, account credentials or private repository inputs are included. No run-proof is claimed. The code has not run here. It is not counted as startable product stock. This gate exists only to decide whether the next real transport experiment can have an executor, not to start an open-ended test program.

## Product-linked decision

The waiting integrator needs one bounded answer: can the lab's existing Linux environment run Node, local HTTP transport, CPU/RSS measurements and fail-closed resource stops? A PASS opens preparation of the actual old/current A/B plan, not production changes or a claim that download/heat improved. No new heuristic is proposed by this packet.

## Acceptance first

Reply at replies/W-gdb-e0-qualification-01.md or the existing lab response page with an explicit ACCEPT or DECLINE, available existing Node/Python versions, available RAM/free scratch, permitted loopback sockets and permission to read own /proc counters. Accept only if the limits below fit current permissions and capacity. No installation, capacity reservation, paid resources or new external network access is requested. Do not execute before explicit acceptance has been returned and the integrator acknowledges GO. If unavailable, return one blocker, not a substitute model suite.

## Upfront safety envelope

- One attempt, no automatic retry. Whole job at most15s wall time; internal automatic stop at12s, TERM thenKILL after0.2s. Lab must have an independent existing watchdog capped15s or DECLINE pending that capability.
- Total supervisor+children sampled CPU at most2CPU-seconds; a sampled overrun is STOP/FAIL, no more work. Monitoring granularity5ms, small overshoot is recorded, not hidden.
- Per-child RSS at most128MiB; observed supervisor+child at most192MiB. Lab needs existing hard memory limit at most256MiB or must DECLINE pending one. No memory pressure test/allocation sweep.
- Local synthetic data: four sequential262144-byte HTTPresponses,1048576B received and2097152B combined served+received payload. Payload ceiling8MiB; actual fixture hard maximum is2MiB combined. Socket/protocol overhead is not this counter and must not be labeled payload. No external addresses, public swarm or peer discovery. OS-level network isolation is NOT established by this fixture.
- Disk: scripts+receipt at most128KiB new owned output, source included. Captured child output64KiB ceiling. No payload files, package cache or build output. At least16MiB currently free scratch required. Do not delete existing evidence/files. A future cleanup concerns only this packet's own new directory and needs the ordinary permission boundary.
- Dependencies: existing Python3 standard library and existing Node only. No npm/pip/build/CI or download step. No owner-Mac or production action.

## Exact offered command and inputs

Place only the two supplied complete files in a new owned scratch directory as fixture.cjs and supervisor.py, verify the SHA256 values recorded below, then after acceptance AND integrator GO run once:

    python3 supervisor.py --accepted-generic-once > receipt.json

The environment watchdog and memory limit must be described in the acceptance. Do not invent an unverified isolation command. No command is authorized by this document before that acceptance/GO boundary.

The supervisor offers four tiny cases only: RSS-stop negative, wall-stop negative, CPU-stop negative, then loopback byte correctness. It reports exact exits and samples, kills its child group on failure and returns nonzero on a failed assertion. A failure is useful routing evidence; do not silently repair/retry or expand this into a benchmark. Read both files before accepting.

## Acceptance criteria / honest limits

Return stdout receipt, stderr/exit, wall duration, current versions, actual enforcement mechanism and SHA256 for both scripts. PASS requires all four cases and stop cleanup, metrics present, no unexpected writes/connections and limits respected. Missing Node, counters, watchdog/memory control, permission or capacity is BLOCKED, not PASS. No traffic or a skipped normal case is FAIL/NOT_RUN.

This test does NOT qualify actual WT, dependency integration, shaped network accuracy, external isolation, descendants telemetry, socket overhead, owner uplink, mpv, Mac heat or production behavior. It spawns no grandchildren. Those limits must accompany a return. After one reply, the integrator either prepares the actual A/B plan or names the exact missing executor capability; no generic test backlog is requested.

## Return and next step

Waiting consumer: leg A transport experiment planning. Return acceptance first, before execution, to replies/W-gdb-e0-qualification-01.md or the same response page used for H0688. No new audience or private input route is authorized. Product source remains excluded unless separately grounded owner scope explicitly permits the exact disclosure.

Secret/publication review: generic hand-authored synthetic scripts only, standard local interfaces, no credentials or user/product data. Python static syntax checked; execution and Node syntax/runtime NOT_RUN.

## Complete file fixture.cjs
SHA256: 58bdaf734232acebe1e4d04414c0e2afab069b1798d52cc9b59e8c3d31502c06

```javascript
'use strict';
// Generic synthetic loopback fixture. No product code or dependencies.
const http = require('node:http');
const mode = process.argv[2];
if (mode === 'busy') { while (true) {} }
else if (mode === 'idle') { setInterval(() => {}, 1000); }
else if (mode === 'normal') {
  const data = Buffer.alloc(262144, 37);
  let served = 0, received = 0, done = 0;
  const server = http.createServer((req, res) => {
    if (req.url !== '/synthetic' || ++served > 4) {
      res.writeHead(400); res.end(); return;
    }
    res.writeHead(200, {'Content-Length': data.length}); res.end(data);
  });
  const fail = () => { server.close(); process.exitCode = 2; };
  server.on('error', fail);
  server.listen(0, '127.0.0.1', () => {
    const next = () => {
      let count = 0;
      const req = http.get({hostname:'127.0.0.1', port:server.address().port,
        path:'/synthetic', agent:false}, res => {
        if (res.statusCode !== 200) return fail();
        res.on('data', b => {
          for (const v of b) if (v !== 37) return fail();
          count += b.length; received += b.length;
          if (received > 1048576) fail();
        });
        res.on('end', () => {
          if (count !== data.length) return fail();
          if (++done < 4) next();
          else server.close(() => console.log(JSON.stringify({
            result:'GENERIC_LOOPBACK_PASS', received, served,
            payload_directional_sum:received * 2,
            scope:'synthetic only; not WT, not network isolation proof'
          })));
        });
        res.on('error', fail);
      });
      req.on('error', fail);
    }; next();
  });
} else process.exitCode = 2;
```

## Complete file supervisor.py
SHA256: bfda86154f55170d941d8207fb8305a8c64d021c11cc3167768870687c6e4456

```python
#!/usr/bin/env python3
"""Generic Linux capability probe; no installation, product or external traffic."""
import os, sys, time, json, signal, subprocess, shutil, pathlib, resource
BASE = pathlib.Path(__file__).resolve().parent
START = time.monotonic()
HZ = os.sysconf('SC_CLK_TCK')
PAGE = os.sysconf('SC_PAGE_SIZE')
TOTAL_OUT = 0
MAX_RSS = 0
RESULTS = []

def proc(pid):
    text = pathlib.Path('/proc/%d/stat' % pid).read_text()
    cols = text[text.rfind(')')+2:].split()
    return (int(cols[11])+int(cols[12]))/HZ, int(cols[21])*PAGE

def stop(p):
    try: os.killpg(p.pid, signal.SIGTERM)
    except ProcessLookupError: pass
    try: p.wait(timeout=0.2)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL); p.wait(timeout=0.5)

def run(label, mode, wall, cpu, rss, expected):
    global TOTAL_OUT, MAX_RSS
    if time.monotonic()-START > 10: raise RuntimeError('overall time budget')
    p = subprocess.Popen([shutil.which('node'), str(BASE/'fixture.cjs'), mode],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True,
        env={'PATH':os.environ.get('PATH','/usr/bin:/bin'), 'HOME':'/nonexistent'})
    os.set_blocking(p.stdout.fileno(), False)
    begin=time.monotonic(); reason=None; peak=0; lastcpu=0; output=bytearray()
    try:
        while p.poll() is None:
            if time.monotonic()-START > 12: reason='overall_wall'; break
            try:
                lastcpu, mem=proc(p.pid); peak=max(peak,mem)
                _, own=proc(os.getpid()); MAX_RSS=max(MAX_RSS,mem+own)
            except FileNotFoundError: continue
            b=p.stdout.read(4096) or b''; output.extend(b); TOTAL_OUT+=len(b)
            if TOTAL_OUT > 65536: reason='output'; break
            if mem+own > 192*1024*1024: reason='aggregate_rss'; break
            usage=resource.getrusage(resource.RUSAGE_CHILDREN); ownusage=resource.getrusage(resource.RUSAGE_SELF)
            if usage.ru_utime+usage.ru_stime+ownusage.ru_utime+ownusage.ru_stime+lastcpu > 2: reason='overall_cpu'; break
            if mem > rss: reason='rss'; break
            if lastcpu > cpu: reason='cpu'; break
            if time.monotonic()-begin > wall: reason='wall'; break
            time.sleep(.005)
        if reason: stop(p)
        else: p.wait(timeout=.3)
        b=p.stdout.read(65537) or b''; output.extend(b); TOTAL_OUT+=len(b)
        if TOTAL_OUT > 65536: raise RuntimeError('output exceeded')
        if expected is None:
            data=json.loads(output.decode())
            assert p.returncode==0 and reason is None
            assert data['result']=='GENERIC_LOOPBACK_PASS' and data['received']==1048576
            assert data['payload_directional_sum']==2097152
        else:
            assert reason==expected, (label,reason,p.returncode)
            data={'expected_stop':expected}
        assert not pathlib.Path('/proc/%d' % p.pid).exists(), 'child still exists'
        RESULTS.append({'case':label,'reason':reason,'exit':p.returncode,
            'wall_s':round(time.monotonic()-begin,4),'cpu_s_last_sample':lastcpu,
            'peak_rss_bytes':peak,'output':data})
    finally:
        if p.poll() is None: stop(p)
        p.stdout.close()

if __name__=='__main__':
    if sys.argv[1:] != ['--accepted-generic-once']:
        sys.exit('Requires separate explicit lab acceptance before this one-shot command.')
    assert sys.platform=='linux' and shutil.which('node'), 'BLOCKED: existing Linux/Node required, no install'
    assert shutil.disk_usage(BASE).free>=16*1024*1024, 'BLOCKED: less than 16MiB free'
    assert resource.getrusage(resource.RUSAGE_CHILDREN).ru_utime==0
    run('rss-stop-negative','idle',1,.5,1,'rss')
    run('wall-stop-negative','idle',.15,.5,128*1024*1024,'wall')
    run('cpu-stop-negative','busy',1,.08,128*1024*1024,'cpu')
    run('loopback-byte-check','normal',3,1,128*1024*1024,None)
    u=resource.getrusage(resource.RUSAGE_CHILDREN)
    result={'result':'GENERIC_CAPABILITY_PASS','scope':'Not WT A/B, not production, not isolation attestation',
        'node':subprocess.check_output([shutil.which('node'),'--version'],text=True).strip(),
        'elapsed_s':round(time.monotonic()-START,4),'child_cpu_s':u.ru_utime+u.ru_stime,
        'max_observed_aggregate_rss_bytes':MAX_RSS,'captured_output_bytes':TOTAL_OUT,'cases':RESULTS,
        'payload_directional_bytes':2097152,'payload_budget_bytes':8388608,
        'external_connections_in_fixture':0,'network_isolation':'NOT_TESTED',
        'socket_protocol_overhead':'NOT_MEASURED','descendant_telemetry':'NOT_TESTED; fixture spawns none'}
    encoded=json.dumps(result,indent=2).encode()
    assert len(encoded)<65536
    print(encoded.decode())
```

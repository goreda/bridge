#!/usr/bin/env python3
"""Bounded C runtime gate. Runs only an explicit gor binary and local fixture.
No build, install, native dispatch, settings writes or network operations.
Exit 0 means instrumented checks green, still PARTIAL app-lifecycle/venue scope.
"""
import argparse, json, os, subprocess, time
from pathlib import Path

REQUIRED = {'C3.window-open', 'C3.first-frame-anchor', 'C3.pause-control',
 'C3.pause12-time-frozen', 'C3.pause12-no-eos',
 'C3.real-audio-and-presentation-pause', 'C3.parked-seek-committed',
 'C3.resume-landing-anchor', 'C3.resume-live-counters', 'C3.audio-landing',
 'C3.no-control-refusal', 'C3.close-from-paused', 'C.summary'}

def assess(code, text, timed_out=False):
    rows=[]
    for raw in text.splitlines():
        try: row=json.loads(raw)
        except ValueError: continue
        if isinstance(row,dict) and row.get('stage')=='C': rows.append(row)
    passed={r.get('check') for r in rows if r.get('status')=='PASS'}
    failures=[r for r in rows if r.get('status')=='FAIL']
    missing=sorted(REQUIRED-passed)
    ok=code==0 and not timed_out and not failures and not missing
    return {'status':'PARTIAL' if ok else 'FAIL', 'checks_green':ok,
            'exit':code,'timeout':timed_out,'missing_pass_checks':missing,
            'failure_lines':failures,'checks':rows,
            'remaining':['normal AppDelegate lifecycle NOT_RUN',
              'macOS13 runtime/HDR/EDR/owner acceptance NOT_RUN',
              'real scanout NOT_VERIFIED by this harness']}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--gor',type=Path,required=True)
    p.add_argument('--fixture',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--venue',required=True,help='ops-observed display/runner venue; never inferred')
    a=p.parse_args()
    if not a.gor.is_file() or not a.fixture.is_file(): p.error('binary and local fixture must exist')
    if a.output.exists(): p.error('output must be a new directory, preserving prior failures')
    a.output.mkdir(parents=True)
    log=a.output/'C-runtime.raw.log';begin=time.monotonic();timed=False
    env=dict(os.environ,GOR_NATIVE_GATE_VENUE=a.venue)
    with log.open('wb') as out:
        proc=subprocess.Popen([str(a.gor.resolve()),'--gorav-native-gate',str(a.fixture.resolve())],
                              env=env,stdout=out,stderr=subprocess.STDOUT,start_new_session=True)
        try: code=proc.wait(timeout=120)
        except subprocess.TimeoutExpired:
            import signal
            timed=True;os.killpg(proc.pid,signal.SIGKILL);code=proc.wait()
    text=log.read_text(errors='replace');receipt=assess(code,text,timed)
    receipt.update(seconds=time.monotonic()-begin,venue=a.venue,
       gor=str(a.gor.resolve()),fixture=str(a.fixture.resolve()),raw_log=str(log),
       timeout_contract={'process_s':120,'open_s':20,'pause_state_s':2,
         'pause_hold_min_s':12,'resume_landing_s':10,'close_ms_less_than':300,
         'provenance':'gate operational bounds proposed for native87, not historical product timeouts'})
    (a.output/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    if not receipt['checks_green']:
        (a.output/'failure-tail.log').write_text('\n'.join(text.splitlines()[-200:])+'\n')
    print(json.dumps({k:receipt[k] for k in ['status','checks_green','exit','timeout','missing_pass_checks','seconds']}))
    return 0 if receipt['checks_green'] else 1
if __name__=='__main__': raise SystemExit(main())

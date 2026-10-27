# W0218 photon noise-feed pilot - in2tinct reviewer failure cases (v4, frozen; written without reading any solver fix)

Status: AUTHORED, not executed against a fix. Derived only from the baseline packet (pin 3e5b0f43...), PROBLEM.md, harness, manifest and fresh-480 evidence. No solver fix or 1nstinct result was read. Software llvmpipe only, no real GPU, no owner-eyes acceptance, no product claim. Delivery id photon123-noise-pilot-v1.

## Findings from the baseline packet itself (executed: read + arithmetic + oracle on fresh-480-events.json)
1. First live feed is at wall 30.81s, not "13.886s". The 13.886s event is has_feed=false (noise=0.1 fallback). The packet's "first feed 13.886s" is a fallback payload.
2. Seek event is at wall 10.02s, but observer.lua schedules seek at 8s after file-loaded. Under llvmpipe the harness clock drifts ~2s. Post-seek deadline must be measured from the seek event, not file-loaded.
3. Only 4 scene-feed events in 30s, 2 with has_feed=true, 22ms apart. That is not per-frame. check_noise_feed.py needs only one live event <=5s and any strength-mult, so it can pass with one stray event.
4. The checker's "first<=5" uses wall since file-loaded for the whole run. A feed at 1s then dead after seek passes.
5. BASELINE-ONLY finding: with the baseline shader excerpt, smooth_noise=0.1 gives factor 1 - smoothstep(.05,.35,.1)*.5 = 0.9630 (about -3.7% grain), while the contract says missing source uses x1.0. This says nothing about a fix. The oracle does not hardcode it; C5 checks the delivered multiplier events instead, or returns UNKNOWN.
6. Missing observability, not a proven algorithm failure: the has_feed=true payload shows no provenance key. Keys seen are only peak/contrast/noise/block/ring/rlevel/sat/motion/smooth_*/fps/is_hdr/is_cut/has_feed(/baseline_*/hue/warmth). Nothing in the payload says whether the noise value is a source estimate or scene statistics; other evidence may exist.
7. Observed strength-mult args: (0.5000, 1, 480p.mp4, 109.9392, 0.715, 1, 1, 0). Value 0.5 with share 0.715 and raw noise 0.7153: multiplier sits on the lower clamp, so a 0.715 share maps to the floor. Whether the mapping is intended is unknown; the packet warns share is not a calibrated noise value.
8. The packet's HUD values (grain source=0 output=0 strength=4.800 ...) show output=0 for all fresh frames. Not the owner's historical log; do not cite as such.

## Cases (each: fixture, procedure, oracle, call site, must-not-change, feasibility)
Oracle script v4: noise_feed_oracle.py. Verdicts PASS / PASS-PARTIAL / FAIL / UNKNOWN. UNKNOWN and PASS-PARTIAL are never full passes (exit 2); any FAIL exits 1. Self-test: 39 real assertions with negative counterexamples (assert-log.txt, exit 0). No wire field is required by the oracle.
- C0 malformed, nonfinite or unparsable HARNESS lines are counted (parse errors tracked, not silently dropped); any gives UNKNOWN. Strength valid flags are canonicalised (1/true/1.0, 0/false/0.0); anything else is rejected.
- C1 first live feed <=5s after the CURRENT file-loaded (prestart and prior-generation feeds excluded). C2 first live feed <=5s after each seek event. 5s is contract. No seek gives UNKNOWN.
- C3 is a FRESHNESS PROXY, not a per-frame proof. A gap over the authored MAX_AGE (0.25s) against frame-position events (trailing outage counted) is a certain miss, so FAIL. No gap gives UNKNOWN: a 4Hz feed over 30fps, or one feed reused for many frames, also passes the proxy. PASS only when frame-position events carry observed frame_id values and every one matches a live feed's frame value. Counts of unique ids never give PASS (arbitrary ids 1000..1299 do not match). Fewer than 30 frame events gives UNKNOWN.
- C4 provenance: no payload key means missing observability (UNKNOWN), not a proven algorithm failure; other external evidence may meet the contract. A candidate key is also UNKNOWN. Semantics must be settled against the solver spec. No new wire field is required.
- C5 fallback: needs a valid=0 strength event in the current load and latest (doc_gen, revision). None gives UNKNOWN (not exercised). With one, x1.0 gives PASS-PARTIAL (multiplier alone cannot certify shader neutrality); anything else FAIL.
- C6 multiplier within .5..1.5, never 0. C7 valid-vs-fallback: valid=0 at x1.0 is a legitimate fallback; a valid flag is not proof of provenance (PASS-PARTIAL at best). C5-C7 use only strength events after the current load and in the latest (doc_gen, revision), compared numerically (10 beats 9). Non-numeric doc_gen or revision rejects the event (C0 UNKNOWN).
- C8 freshness needs at least 3 live feeds all carrying a finite stamp, else UNKNOWN. Strict increase within each seek epoch gives PASS-PARTIAL only (a necessary proxy, not freshness proof). A stamp reset after a seek is legitimate because feeds are partitioned into epochs at seek events; a reset with no seek is FAIL. Equal noise values are never staleness. Stamp key names are assumptions.

| ID | Case | Fixture | Procedure | Oracle (must hold) | Call site | Must not change | Feasible here |
|---|---|---|---|---|---|---|---|
| F1 | Static scene | a looped still image (testsrc2 MOVES, so it is not static), 10s, 8-bit SDR, generated locally | run.sh-style single file | feed live <=5s; noise reading valid even when ~0 motion; no mult 0; cadence per frame; static must not read as "invalid" | photon.lua GS.tick_body, GS.last_noise_at | saved look, positive bounded grain | yes (software) |
| F2 | Flat colour | lavfi color=c=gray, no noise | same | noise ~0 is a valid source reading, not missing; mult stays in .5..1.5 (not 0, not silent off); shader factor finite (1e-30 gate kept) | photon-grain gr_push_params, gate 1e-30 | 1e-30 gate; do not use 1e-66 | yes |
| F3 | Scene cut | concat of two clips with different noise (NASA clip + gray) | seek not needed; cut at 5s | is_cut=true frame must not publish stale noise from the pre-cut scene; new reading within 5s of cut; has_feed not stuck | photon_publish_scene_feed, is_cut | manual suppression | yes |
| F4 | Seek | NASA480/1080 | seek to 8s exact and back to 1s | live feed <=5s after the seek event (C2); first post-seek payload is not the pre-seek payload (C8) | GS.paced_tick | doc_gen/revision identity | yes |
| F5 | Film grain vs compression noise (falsification/control, NOT a requirement from the contract) | same source at several CRFs, plus ffmpeg noise-filter grain as a synthetic control | run all | no assumption that CRF gives monotonic noise and no assumption of a perfect grain classifier. Record raw noise with block/ring per variant. Falsify only: a claim of source-noise tracking is refuted if reported noise is flat across a clearly noise-added control, or tracks block/ring alone. Report as observation, not pass/fail | noise estimate in tick_body | ring/block fields | partly: synthetic only; real film grain no |
| F6 | 10-bit | ffmpeg -pix_fmt yuv420p10le | run | feed live <=5s, same oracle; value scale must not be 8-bit-only | tick_body | bright/SDR/chrome | yes if mpv build decodes 10-bit; else mark not executed |
| F7 | HDR | PQ tagged clip (-color_trc smpte2084, bt2020) | run | is_hdr=true; mult in range; shader is_hdr factor .55 unchanged; no NaN | shader hook, hdr_black_gate | HDR handling | proposed only: no HDR display here |
| F8 | Invalid / stale input | feed message with has_feed=true but noise=nan, negative, >1, missing keys; feed not updated for N s | inject script-message photon-scene-feed via mpv IPC | receiver must reject or fall back to x1.0, never 0/NaN (contract: missing valid reading uses x1.0). PROPOSED, not contract: a 2s staleness limit and drop to has_feed=false are authored thresholds, to be settled with the solver | photon-scene-feed receiver, f.smooth_noise | manual override semantics | yes (IPC injection) |
| F9 | Rollback / error recovery | kill/reload photon.lua mid-play; drop photon-grain after a feed | script-message sequence | after rollback grain returns to prior look value, not stuck at last feed multiplier; revision identity preserved | photon-grain-set-strength-mult revision arg | doc_gen/revision | yes |
| F10 | Manual override | set manual suppression then run feed | script-message | feed must not override manual suppression | strength-mult receiver | manual suppression | yes |
| F11 | Provenance | any | inspect payload and any external evidence | contract: something explicit must distinguish source estimate from scene statistics; has_feed alone does not. Existing external provenance evidence may satisfy this. A new payload field is a PROPOSAL, not a required wire change. Absence of a key is UNKNOWN pending semantics; judge actual semantics, not key presence | photon_publish_scene_feed, scene_kv_encode | encode format backward compat | yes |
| F12 | Backend/latency | any | run on a real GPU | latency/load numbers | n/a | n/a | NO: needs real hardware; owner eyes accepts final |

## Executed vs proposed
Executed: reading packet, arithmetic above, oracle self-test (39 assertions, all pass, assert-log.txt), oracle run on fresh-480-events.json (baseline-run.txt): C1 FAIL, C2 FAIL (live feed 20.8s after the seek event), C3 UNKNOWN (4 frame events), C4 UNKNOWN (missing observability), C5 UNKNOWN (no fallback event), C6 PASS and C7 PASS-PARTIAL on one strength-mult event (weak), C8 UNKNOWN. Baseline C1 and C2 FAILs stand. Proposed, not run: F1-F12 fixtures against mpv. Not available: real GPU, owner eyes, product repo.

## Remaining gaps
No named product-repo acceptance test. Historical owner HUD log missing. 8-bit SDR NASA fixture only. After cases published, review the fix against these and report failures to the same W id.

## Authored assumptions (not contract)
MAX_AGE 0.25s and MIN_FRAMES 30 in C3; MIN_STAMPS 3 and stamp key names in C8; F8 2s staleness; synthetic control in F5; any new provenance field name. The 5s deadline, .5..1.5 range, x1.0 neutral fallback and 1e-30 gate are from PROBLEM.md. Real GPU not available; no real-GPU claim is made.

## Reuse
License: proposed MIT for the case text and script, pending owner confirmation (no license set by the owner). Baseline packet pin: 3e5b0f43c94b85d5ec761cd40259a906151b29f0. No third-party media bytes included.
Commands: `python3 noise_feed_oracle.py --selftest` (expects "39 assertions passed", exit 0); `python3 noise_feed_oracle.py results/480-photon/stdout.log` or an events JSON. Exit 0 all PASS, 1 any FAIL, 2 UNKNOWN or PASS-PARTIAL remain.
noise_feed_oracle.py sha256: abd7e0cb2c6b3351e4e3d4a9e4aeff5e16070c729279d53854942e2f4c0bc65b

## Embedded script (noise_feed_oracle.py)
```python
#!/usr/bin/env python3
"""W-0218 in2tinct reviewer oracle v4. Authored test, NOT product acceptance, not run against any fix.
Usage: noise_feed_oracle.py EVENTS.json|stdout.log   |   noise_feed_oracle.py --selftest
Verdicts: PASS / FAIL / UNKNOWN. UNKNOWN means the events lack the data to decide; it is never a pass.
License: proposed MIT, pending owner confirmation (no license set by owner).
Run: python3 noise_feed_oracle.py --selftest ; python3 noise_feed_oracle.py EVENTS.json|stdout.log
Exit: 0 only if every check is PASS; 1 on any FAIL; 2 if UNKNOWN or PASS-PARTIAL remain.
PASS-PARTIAL = necessary condition met, not a full proof.
AUTHORED PARAMETERS (not contract): MAX_AGE=0.25s freshness proxy, MIN_FRAMES=30, MIN_STAMPS=3. 5s deadline IS contract.
No wire field is required: absence of a payload key is missing observability (UNKNOWN), not a proven algorithm failure."""
import json,math,sys
PARSE_ERRORS=0
MAX_AGE=0.25; MIN_STAMPS=3; MIN_FRAMES=30; DEADLINE=5.0
STAMP_KEYS=('seq','frame','src_time','feed_ts')            # proposed freshness stamps, names are assumptions
PROV_KEYS=('source','provenance','noise_source','noise_valid','valid')  # candidate keys only, semantics unverified
def fin(x):
    try: return math.isfinite(float(x))
    except (TypeError,ValueError): return False
def load(p):
    t=open(p).read()
    global PARSE_ERRORS
    PARSE_ERRORS=0
    try: raw=json.loads(t)
    except ValueError:
        raw=[]
        for l in t.splitlines():
            if 'HARNESS {' in l:
                try: raw.append(json.loads(l[l.index('{'):]))
                except ValueError: PARSE_ERRORS+=1
    if not isinstance(raw,list): PARSE_ERRORS+=1;return []
    return raw
def canon_valid(x):
    s=str(x).strip().lower()
    if s in('1','true','1.0'): return True
    if s in('0','false','0.0'): return False
    return None
def clean(raw):
    """drop malformed / nonfinite events; return (events, rejected_count). Never raises."""
    ev=[];bad=0
    for e in raw:
        if not isinstance(e,dict) or not isinstance(e.get('kind'),str) or not fin(e.get('wall')): bad+=1;continue
        e=dict(e);e['wall']=float(e['wall'])
        if e['kind']=='scene-feed':
            x=e.get('extra');
            if not(isinstance(x,list) and x and isinstance(x[0],str)): bad+=1;continue
            d=dict(p.split('=',1) for p in x[0].split(';') if '=' in p)
            if not(fin(d.get('noise')) and fin(d.get('smooth_noise')) and d.get('has_feed') in('true','false')): bad+=1;continue
            e['d']=d
        elif e['kind']=='strength-mult':
            x=e.get('extra')
            if not(isinstance(x,list) and len(x)>=7 and fin(x[0]) and canon_valid(x[6]) is not None): bad+=1;continue
            if not(len(x)>7 and fin(x[1]) and fin(x[7])): bad+=1;continue   # doc_gen/revision must be finite numbers
            e['valid']=canon_valid(x[6]);e['gen']=(float(x[1]),float(x[7]))  # numeric, so 10 > 9
        elif e['kind']=='frame-position':
            x=e.get('extra')
            if not(isinstance(x,list) and x and fin(x[0])): bad+=1;continue
            if 'frame_id' in e and not fin(e['frame_id']): bad+=1;continue
        ev.append(e)
    return ev,bad
def check(raw):
    ev,bad=clean(raw);bad+=PARSE_ERRORS;R=[]
    def add(c,v,m): R.append((c,v,m))
    loads=[e['wall'] for e in ev if e['kind']=='file-loaded']
    t0=max(loads) if loads else None            # latest load = current generation; earlier feeds excluded
    feeds=[e for e in ev if e['kind']=='scene-feed' and t0 is not None and e['wall']>=t0]
    live=sorted((e for e in feeds if e['d']['has_feed']=='true'),key=lambda e:e['wall'])
    add('C0-input','PASS' if bad==0 else 'UNKNOWN',f'{bad} malformed/nonfinite/unparsable events rejected, {len(ev)} usable')
    if t0 is None: add('C1-start<=5s','UNKNOWN','no file-loaded event');
    else:
        f=live[0]['wall']-t0 if live else None
        add('C1-start<=5s','PASS' if f is not None and f<=DEADLINE else 'FAIL',f'first live feed {f}s after current file-loaded (prestart/prior-generation feeds excluded)')
    seeks=[e['wall'] for e in ev if e['kind']=='seek' and t0 is not None and e['wall']>=t0]
    if not seeks: add('C2-postseek<=5s','UNKNOWN','no seek event')
    for s in seeks:
        a=[e['wall']-s for e in live if e['wall']>s]
        add('C2-postseek<=5s','PASS' if a and min(a)<=DEADLINE else 'FAIL',f'seek@{s}: first live feed {min(a) if a else None}s after seek event')
    frames=[e['wall'] for e in ev if e['kind']=='frame-position' and t0 is not None and e['wall']>=t0]
    if len(frames)<MIN_FRAMES: add('C3-freshness-proxy/perframe','UNKNOWN',f'only {len(frames)} frame events (<{MIN_FRAMES}); no denominator')
    else:
        lw=[e['wall'] for e in live];unc=0
        for fw in frames:
            prior=[w for w in lw if w<=fw]
            if not prior or fw-prior[-1]>MAX_AGE: unc+=1      # trailing outage counted
        ids=[float(e['frame_id']) for e in ev if e['kind']=='frame-position' and t0 is not None and e['wall']>=t0 and 'frame_id' in e]
        fv={float(e['d']['frame']) for e in live if fin(e['d'].get('frame'))}
        assoc=len(ids)==len(frames) and all(i in fv for i in ids)   # every OBSERVED frame id must match a feed's frame value; counts never suffice
        if unc: add('C3-freshness-proxy/perframe','FAIL',f'{unc}/{len(frames)} frames have no live feed within {MAX_AGE}s (authored proxy; a gap is a certain miss)')
        elif assoc: add('C3-freshness-proxy/perframe','PASS',f'every one of {len(frames)} observed frame ids matches a live feed frame value')
        else: add('C3-freshness-proxy/perframe','UNKNOWN','no gap >%.2fs, but this is a freshness proxy only: a 4Hz feed over 30fps or one feed reused for many frames also passes it. Per-frame needs observed frame_id events matching feed frame values; not provided'%MAX_AGE)
    pk=sorted({k for e in live for k in e['d'] if k in PROV_KEYS})
    if not live: add('C4-provenance','UNKNOWN','no live feeds')
    elif not pk: add('C4-provenance','UNKNOWN','no payload key observed; provenance may be carried by other external evidence. Missing observability, not a proven algorithm failure. Settle against solver semantics/evidence')
    else: add('C4-provenance','UNKNOWN',f'candidate keys {pk} present; semantics must be validated against solver spec, key presence is not proof')
    sm=[e for e in ev if e['kind']=='strength-mult' and t0 is not None and e['wall']>=t0]
    if sm:
        latest=max((e['gen'] for e in sm),key=lambda g:g);sm=[e for e in sm if e['gen']==latest]   # current load, latest (doc_gen,revision) only
    fb=[e for e in sm if not e['valid']]
    if not fb: add('C5-fallback','UNKNOWN','no valid=0 (fallback) strength event in current load/generation: not exercised')
    else:
        badf=[e['extra'] for e in fb if abs(float(e['extra'][0])-1.0)>1e-6]
        add('C5-fallback','FAIL' if badf else 'PASS-PARTIAL',f'valid=0 events must deliver x1.0; violations {badf}. Multiplier alone cannot certify shader neutrality (partial proxy)')
    if not sm: add('C6-mult-range','UNKNOWN','no current-generation strength-mult events')
    else:
        v=[float(e['extra'][0]) for e in sm]
        add('C6-mult-range','PASS' if all(.5<=x<=1.5 for x in v) else 'FAIL',f'values {v}, must be within .5..1.5 and never 0')
        okv=[e for e in sm if e['valid']]
        add('C7-valid-vs-fallback','PASS-PARTIAL' if okv else 'UNKNOWN',f'{len(okv)} valid-measurement events (flags canonicalised); valid=0 with x1.0 is a legitimate neutral fallback. Validity flag is not proof of source provenance')
    st=[k for k in STAMP_KEYS if live and all(fin(e['d'].get(k)) for e in live)]
    if not st or len(live)<MIN_STAMPS: add('C8-freshness','UNKNOWN',f'need >={MIN_STAMPS} live feeds all carrying a finite stamp (have {len(live)}, keys {st}); a single event is not freshness proof; equal noise values never show staleness')
    else:
        cuts=sorted(seeks)     # a stamp reset after a seek is legitimate: partition into epochs at seek events
        ep={}
        for e in live: ep.setdefault(sum(1 for c in cuts if e['wall']>c),[]).append(float(e['d'][st[0]]))
        okc=all(b>a for v in ep.values() for a,b in zip(v,v[1:]))
        add('C8-freshness','PASS-PARTIAL' if okc else 'FAIL',f'stamp {st[0]} strictly increasing within each of {len(ep)} seek epoch(s) is a necessary proxy only, not freshness proof')
    return R
def mk(w,n='0.3',s='0.3',h='true',x=''): return {'kind':'scene-feed','wall':w,'extra':[f'noise={n};smooth_noise={s};has_feed={h}{x}']}
def fr(w): return {'kind':'frame-position','wall':w,'extra':[w]}
def V(R,c): return [v for k,v,_ in R if k==c]
def selftest():
    L={'kind':'file-loaded','wall':0.0};n=0
    def ok(c,cond):
        nonlocal n;n+=1
        print(('ASSERT OK  ' if cond else 'ASSERT FAIL'),c)
        if not cond: sys.exit(1)
    C3='C3-freshness-proxy/perframe'
    frames=[fr(i/30) for i in range(300)]
    good=[L]+frames+[mk(i/30,x=f';seq={i}') for i in range(300)]
    R=check(good)
    ok('good: C1 PASS',V(R,'C1-start<=5s')==['PASS']);ok('good 30fps feed: C3 only UNKNOWN (proxy, no unique frame association)',V(R,C3)==['UNKNOWN']);ok('good: C8 PASS-PARTIAL (necessary proxy only)',V(R,'C8-freshness')==['PASS-PARTIAL'])
    withf=[L]+frames+[mk(i/30,x=f';seq={i};frame={i}') for i in range(300)]
    ok('unique count only (feed frame stamps, no observed ids): C3 UNKNOWN',V(check(withf),C3)==['UNKNOWN'])
    fid=lambda off:[L]+[{**fr(i/30),'frame_id':i+off} for i in range(300)]+[mk(i/30,x=f';seq={i};frame={i}') for i in range(300)]
    ok('observed ids match feed frame values: C3 PASS',V(check(fid(0)),C3)==['PASS'])
    ok('arbitrary ids 1000..1299 vs observed 0..299: C3 not PASS',V(check([L]+[{**fr(i/30),'frame_id':i} for i in range(300)]+[mk(i/30,x=f';seq={i};frame={1000+i}') for i in range(300)]),C3)==['UNKNOWN'])
    ok('nonfinite frame_id rejected: C0 UNKNOWN',V(check([L,{**fr(1),'frame_id':'nan'}]),'C0-input')==['UNKNOWN'])
    slow=[L]+frames+[mk(i*7.5/30,x=f';seq={i}') for i in range(40)]
    ok('4Hz feed over 30fps: not PASS (FAIL on gap or UNKNOWN)',V(check(slow),C3)[0] in('FAIL','UNKNOWN'))
    ok('4Hz feed at 0.2s age passes gap proxy only as UNKNOWN',V(check([L]+frames[:90]+[mk(i*0.2,x=f';seq={i}') for i in range(16)]),C3)[0] in('FAIL','UNKNOWN'))
    tr=[L]+frames+[mk(i/30,x=f';seq={i}') for i in range(100)]
    ok('trailing outage: C3 FAIL',V(check(tr),C3)==['FAIL'])
    ok('3 events no denominator: C3 UNKNOWN',V(check([L,mk(1),mk(2),mk(3)]),C3)==['UNKNOWN'])
    const=[L]+frames+[mk(i/30,'0','0',x=f';seq={i}') for i in range(300)]
    ok('flat constant noise + advancing seq: C8 PASS-PARTIAL',V(check(const),'C8-freshness')==['PASS-PARTIAL'])
    rs=[L]+[mk(i/30,x=f';seq={i}') for i in range(10)]+[{'kind':'seek','wall':1.0}]+[mk(1.1+i/30,x=f';seq={i}') for i in range(10)]
    ok('stamp reset after seek is valid: C8 PASS-PARTIAL',V(check(rs),'C8-freshness')==['PASS-PARTIAL'])
    rs2=[L]+[mk(i/30,x=f';seq={i}') for i in range(10)]+[mk(1.1+i/30,x=f';seq={i}') for i in range(10)]
    ok('stamp reset with NO seek: C8 FAIL',V(check(rs2),'C8-freshness')==['FAIL'])
    ok('constant noise no stamp: C8 UNKNOWN',V(check([L]+[mk(i/30,'0','0') for i in range(10)]),'C8-freshness')==['UNKNOWN'])
    ok('frozen stamp: C8 FAIL',V(check([L]+[mk(i/30,x=';seq=5') for i in range(10)]),'C8-freshness')==['FAIL'])
    ok('single event with stamp: C8 UNKNOWN',V(check([L,mk(1,x=';seq=1')]),'C8-freshness')==['UNKNOWN'])
    ok('nonfinite stamps only: C8 UNKNOWN not vacuous PASS',V(check([L]+[mk(i/30,x=';seq=nan') for i in range(10)]),'C8-freshness')==['UNKNOWN'])
    ok('prestart feed excluded from C1',V(check([mk(-3),{'kind':'file-loaded','wall':1.0},mk(20)]),'C1-start<=5s')==['FAIL'])
    ok('late feed C1 FAIL',V(check([L,mk(20)]),'C1-start<=5s')==['FAIL'])
    ok('seek, no post-seek feed: C2 FAIL',V(check([L,mk(1),{'kind':'seek','wall':10.0}]),'C2-postseek<=5s')==['FAIL'])
    ok('no seek C2 UNKNOWN',V(check([L,mk(1)]),'C2-postseek<=5s')==['UNKNOWN'])
    junk=[L,{'kind':'scene-feed','wall':float('nan'),'extra':['x']},{'kind':'scene-feed','wall':1,'extra':['noise=nan;smooth_noise=1;has_feed=true']},'str',None,{'kind':'strength-mult','wall':1,'extra':['inf',1,'a','b','c',1,1,0]}]
    R=check(junk);ok('malformed: no crash, C0 UNKNOWN, C1 not PASS',V(R,'C0-input')==['UNKNOWN'] and V(R,'C1-start<=5s')!=['PASS'])
    import tempfile,os
    f=tempfile.NamedTemporaryFile('w',suffix='.log',delete=False);f.write('HARNESS {bad json\nHARNESS '+json.dumps(L)+'\n');f.close()
    R=check(load(f.name));os.unlink(f.name);ok('unparsable HARNESS line tracked: C0 UNKNOWN',V(R,'C0-input')==['UNKNOWN'])
    ok('no payload provenance key: C4 UNKNOWN (not FAIL)',V(check([L,mk(1)]),'C4-provenance')==['UNKNOWN'])
    ok('candidate key: C4 UNKNOWN',V(check([L,mk(1,x=';valid=1')]),'C4-provenance')==['UNKNOWN'])
    sm=lambda v,val,w=1,g='1',r='0':{'kind':'strength-mult','wall':w,'extra':[str(v),g,'n','1','.5','1',val,r]}
    ok('no fallback event: C5 UNKNOWN (not vacuous PASS)',V(check([L,sm(1.0,'1')]),'C5-fallback')==['UNKNOWN'])
    ok('valid=0 x1.0: C5 PASS-PARTIAL',V(check([L,sm(1.0,'0')]),'C5-fallback')==['PASS-PARTIAL'])
    ok('valid=false x1.0 canonicalised: C5 PASS-PARTIAL',V(check([L,sm(1.0,'false')]),'C5-fallback')==['PASS-PARTIAL'])
    ok('valid=0 x0.97: C5 FAIL',V(check([L,sm(0.97,'0')]),'C5-fallback')==['FAIL'])
    ok('mult 0: C6 FAIL',V(check([L,sm(0,'1')]),'C6-mult-range')==['FAIL'])
    ok('mult 1.6: C6 FAIL',V(check([L,sm(1.6,'1')]),'C6-mult-range')==['FAIL'])
    ok('invalid flag string: event rejected, C0 UNKNOWN',V(check([L,sm(1.0,'maybe')]),'C0-input')==['UNKNOWN'])
    ok('prior-load strength event ignored',V(check([{'kind':'file-loaded','wall':5.0},sm(0,'1',w=1)]),'C6-mult-range')==['UNKNOWN'])
    ok('latest gen numeric: 10 beats 9',V(check([L,sm(0,'1',g='9'),sm(1.0,'1',g='10')]),'C6-mult-range')==['PASS'])
    ok('latest revision numeric: 10 beats 9',V(check([L,sm(0,'1',r='9'),sm(1.0,'1',r='10')]),'C6-mult-range')==['PASS'])
    ok('non-numeric doc_gen rejected: C0 UNKNOWN',V(check([L,sm(1.0,'1',g='abc')]),'C0-input')==['UNKNOWN'])
    ok('only latest (doc_gen,revision) judged',V(check([L,sm(0,'1',g='1',r='0'),sm(1.0,'1',g='2',r='0')]),'C6-mult-range')==['PASS'])
    ok('no strength events: C6 UNKNOWN',V(check([L]),'C6-mult-range')==['UNKNOWN'])
    print(f'{n} assertions passed')
if __name__=='__main__':
    if len(sys.argv)>1 and sys.argv[1]=='--selftest': selftest();sys.exit(0)
    R=check(load(sys.argv[1]))
    for r in R: print(*r)
    vs=[r[1] for r in R];sys.exit(1 if 'FAIL' in vs else 2 if any(v!='PASS' for v in vs) else 0)
```

import json,pathlib,sys
root=pathlib.Path(__file__).resolve().parent.parent
failed=False
for h in [480,1080,2160]:
 events=[]
 for line in (root/'results'/f'{h}-photon/stdout.log').read_text().splitlines():
  if 'HARNESS {' in line:
   try:events.append(json.loads(line[line.index('{'):]))
   except ValueError:pass
 live=[e for e in events if e['kind']=='scene-feed' and 'has_feed=true' in str(e.get('extra'))]
 strength=[e for e in events if e['kind']=='strength-mult']
 first=min((e['wall'] for e in live),default=None)
 ok=first is not None and first<=5 and bool(strength)
 print(h,'first_live_feed_wall_s',first,'source_strength_events',len(strength),'deadline', 'PASS'if ok else'FAIL')
 # A source estimate must carry explicit validity/provenance. has_feed alone
 # can also mean radar/scene statistics. This check is necessary, not sufficient.
 print('source-noise provenance/per-frame and post-seek 5s: REVIEW REQUIRED, not inferred from has_feed')
 failed|=not ok
sys.exit(1 if failed else 0)

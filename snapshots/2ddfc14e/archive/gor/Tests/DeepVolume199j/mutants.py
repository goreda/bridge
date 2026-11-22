from pathlib import Path
import subprocess,os,json
r=Path(__file__).parent;s=(r/'ThreeD.swift').read_text();out=r/'mutants';out.mkdir(exist_ok=True)
override='''var gain = span.gain
        if deep, angularSpan(ipd * gain * factor) < today {
            var lo = gain, hi = maxGain
            for _ in 0..<60 { let m = (lo + hi) / 2; if angularSpan(ipd * m * factor) < today { lo = m } else { hi = m } }
            gain = hi
        }'''
rows=[]
for name,old,new in [
 ('restore-raw-override','let gain = span.gain',override),
 ('drop-today-dial','let zcToday = screenDepth ?? 1.5','let zcToday = 1.5'),
 ('drop-deep-dial','p50 * ((screenDepth ?? 1.5) / 1.5)','p50'),
 ('ignore-today-fallback','guard let c = raw, !c.todayFallback else','guard let c = raw else'),
 ('invert-fallback','c.todayFallback = seenSpan < today','c.todayFallback = seenSpan > today'),
 ('keep-stale-token','("deep2", deepVolume)','("deep", deepVolume)'),
 ]:
 assert s.count(old)==1,(name,s.count(old));d=out/name;d.mkdir(exist_ok=True);p=d/'ThreeD.swift';p.write_text(s.replace(old,new))
 q=subprocess.run(['python',str(r/'test.py'),'--source',str(p),'--out',str(d),'--allow-failure'],capture_output=True,text=True,timeout=60);(d/'driver.log').write_text(q.stdout+q.stderr);assert q.returncode==0,q.stderr
 counts=[]
 for mode in ['-Onone','-O']:
  log=(d/('run'+mode+'.log')).read_text();fails=[line for line in log.splitlines() if line.startswith('FAIL ')];assert fails,(name,mode,log);counts.append(len(fails))
 rows.append(dict(mutant=name,compiled_both=True,failures_Onone=counts[0],failures_O=counts[1]));print(name,counts);p.unlink()
(out/'RESULTS.json').write_text(json.dumps(rows,indent=2)+'\n')

from pathlib import Path
import argparse,re
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);a=p.parse_args();s=a.source.read_text();checks={}
checks['one_helper_definition']=s.count('func deepComfort(_ raw: ShotComfort?)')==1
checks['three_helper_consumers']=len(re.findall(r'prefs\.deepComfort\(raw\)',s))==3
checks['three_raw_compute_sites']=len(re.findall(r'let raw\s*=\s*prefs.comfortActive\(expOpts\) \? ShotComfortShot.compute',s))==3
checks['measurement_from_raw_before_filter']='deepMeasurement = raw?.measurement\n                    let cf = prefs.deepComfort(raw)' in s
checks['fallback_logs_after_success']='if ok, let measurement = deepMeasurement' in s
checks['no_override_bisection']='if deep, angularSpan(ipd * gain * factor) < today' not in s
checks['displayed_comparison']='c.todayFallback = seenSpan < today' in s
checks['today_uses_dial']='let zcToday = screenDepth ?? 1.5' in s
checks['deep2_cache_token']='("deep2", deepVolume)' in s and '("deep", deepVolume)' not in s
checks['logs_mode_and_today']='mode=\\(mode) seenTodayDeg=\\(spanTodayDeg)' in s
for k,v in checks.items():print(('PASS ' if v else 'FAIL ')+k)
print(f'SUMMARY {len(checks)} static source checks, {sum(not v for v in checks.values())} failures')
assert all(checks.values())

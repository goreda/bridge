"""Execute the entry-level refusal battery against the installed 151c bytes."""
import json, pathlib, sys
sys.path.insert(0, '/tmp/w249fix')
from run_entry import run

KIT = pathlib.Path('/tmp/w249fix/kit')
OUT = pathlib.Path('/tmp/w249fix/out')
A = str((OUT / 'fixtures' / 'collection-a').resolve())
EMPTY = str((OUT / 'fixtures' / 'collection-empty').resolve())
ENV = OUT / 'env'
R = {}

def case(name, args, env_file=None):
    env = {'KNI_COMPOSITION_SETTINGS': str(env_file)} if env_file else None
    rc, so, se = run(KIT, args, env)
    R[name] = {'rc': rc, 'stderr_last': se.strip().splitlines()[-1] if se.strip() else '', 'stdout_last': so.strip().splitlines()[-1] if so.strip() else ''}
    print('%-28s rc=%d | %s' % (name, rc, R[name]['stderr_last'][:110]))

case('T-12 empty input', ['--composition-series', EMPTY])
case('T-08 env(A->B mismatch inv)', ['--composition-series', A], ENV / 'bad-source-mismatch.json')
case('T-10(i) unknown key', ['--composition-series', A], ENV / 'bad-unknown-key.json')
case('T-10(ii) non-integer', ['--composition-series', A], ENV / 'bad-noninteger.json')
case('T-10(iii) out-of-range', ['--composition-series', A], ENV / 'bad-out-of-range.json')
case('T-10(iv) bad scope token', ['--composition-series', A], ENV / 'bad-scope-token.json')
case('T-10 label token', ['--composition-series', A], ENV / 'bad-label-token.json')
case('T-10(vii) truncated JSON', ['--composition-series', A], ENV / 'bad-malformed-json.json')
# valid env against A: settings should validate; the run then dies at the engine (composition page intake) - record where
case('valid env (engine absent)', ['--composition-series', A], ENV / 'valid-a.json')

pathlib.Path('/tmp/w249fix/refusal-results.json').write_text(json.dumps(R, indent=1, sort_keys=True) + '\n')

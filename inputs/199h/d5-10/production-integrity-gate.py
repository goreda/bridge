#!/usr/bin/env python3
"""Run the exact fail-closed preinstall integrity branch from production build.sh.
Only this read-only branch is extracted; no fetch, source copy, install or launch.
"""
import pathlib,subprocess,argparse,json
p=argparse.ArgumentParser();p.add_argument('--root',type=pathlib.Path,required=True);a=p.parse_args();r=a.root.resolve();s=(r/'build.sh').read_text();start=s.index('    if ! /usr/bin/python3 "$src_root/tools/architecture.py" --root "$src_root" --integrity-only; then');end=s.index('\n    fi',s.index('manifest_tree_test.py" >/dev/null',start))+len('\n    fi');block=s[start:end];q=subprocess.run(['bash','-c','src_root="$1"\n'+block,'production-integrity-gate',str(r)]);print('PRODUCTION_BUILD_SH_INTEGRITY_BRANCH '+json.dumps({'exit':q.returncode,'root':str(r),'no_install':True}));raise SystemExit(q.returncode)

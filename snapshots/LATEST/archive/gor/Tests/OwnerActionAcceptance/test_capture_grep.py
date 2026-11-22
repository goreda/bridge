import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import sys,tempfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'tools'))
from owner_action_capture_grep import collect, PATTERNS
with tempfile.TemporaryDirectory() as folder:
 p=Path(folder)/'log';p.write_text('3D-REJECTED sender=legacy message=projection revision=none\n3D-LUA sender=store-applier revision=4 vr_source_layout=0 vr_flat_mono=1 vr_pack=3\nunrelated\n3D-DECISION path=store_applier output=off\nvr180-look: shader variant extended\n')
 output=collect([p])
 assert '3D-DECISION path=store_applier output=off' in output
 assert 'vr180-look: shader variant extended' in output
 assert 'NO_MATCH 3D-DECISION lua_enable requested=' in output
 assert '3D-REJECTED sender=legacy' in output and '3D-LUA sender=store-applier' in output
 assert 'unrelated' not in output
 assert 'NOT_RUN log_unavailable' in collect([Path(folder)/'missing'])
 print('PASS 5 capture grep cases')

assert "tools/owner_action_capture_grep.py" in (Path(__file__).resolve().parents[2]/"build.sh").read_text(), "update capture must append routing diagnostics"

bs=(Path(__file__).resolve().parents[2]/"build.sh").read_text()
assert '"${update_mode:-false}" = true' in bs and 'for owner_kind in ordinary native' in bs
assert 'GOR_STEP_LIMIT=90' in bs and '3D-OWNER-ACTION leg=$owner_kind rc=$owner_rc' in bs
assert bs.index('for owner_kind in ordinary native') < bs.index('RELAUNCH prior_exact_path_processes=gone')

with tempfile.TemporaryDirectory() as folder:
 p=Path(folder)/'session.log';p.write_text('3D-FILE-RESET path=public.mp4\n3D-DROPPED reason=identityEmpty revision=4\n3D-LUA-FAIL reason=flat_store_kind_crossed_native_engine')
 text=collect([p])
 for marker in ('3D-FILE-RESET path=public.mp4','3D-DROPPED reason=identityEmpty','3D-LUA-FAIL reason='):
  assert marker in text,text
print('PASS193g updategrep includes reset/drop/fatal sessionfamilies')
with tempfile.TemporaryDirectory() as folder:
 p=Path(folder)/'route.log';p.write_text('vrOpenRoute film=public-id file=public.mp4 metadata=none tag=none detected=flat2D\nvrProbeResult file=public.mp4 projection=none\n3D-DECISION path=store_applier film=public-id source=flat2D engine=flat_full_sbs')
 result=collect([p]);assert all(marker in result for marker in ('vrOpenRoute film=','vrProbeResult file=','3D-DECISION path=store_applier film='))
print('PASS193i updategrep retains route/probe/decision diagnosis lines')

features=(_pp_split().path(Path(__file__).resolve().parents[2],'PPController_Features.swift')).read_text()
for family in ('3D-DROPPED','3D-DECISION path=store_applier','3D-APPLIED'):
 assert 'Diag.mediaRecord("'+family in features
 assert 'Diag.log("'+family not in features
print('PASS193j route/drop/applied diagnostics use normalbundle mediaRecord, not GOR_DIAG debug gate')

for family in ('3D-TRANSITION ','3D-VERIFIED ','3D-CLOSE '):assert family in PATTERNS
print('PASS193k capture retains request/verified/close rows')

with tempfile.TemporaryDirectory() as folder:
 p=Path(folder)/'switch.log';p.write_text('3D-TRANSITION file=Eden West.mp4 generation=3 revision=10 previous=full_sbs output=off engine=flat_off phase=requested\n3D-VERIFIED file=Eden West.mp4 generation=3 revision=10 output=off engine=flat_off verdict=FAIL verification=route_state layout=0 pack=3 enabled=false\n3D-CLOSE file=Eden West.mp4 generation=3 revision=10 reason=quit\n')
 result=collect([p]);assert all(marker in result for marker in ('3D-TRANSITION file=Eden West.mp4','verdict=FAIL verification=route_state','3D-CLOSE file=Eden West.mp4'))
print('PASS193k exact update capture preserves film name/transition/failure/close')

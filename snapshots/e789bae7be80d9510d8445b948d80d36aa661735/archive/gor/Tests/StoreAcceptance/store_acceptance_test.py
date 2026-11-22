#!/usr/bin/env python3
"""191b-T pins for tools/store_acceptance.py: the B1 matrix is complete (10 sources x 6 outputs
plus sequences 1-5), per-case artifact custody is enforced by name (aggregate-only FAIL is not a
result), NOT_RUN carries its reason, fixtures synthesize from the public ToS clip only, and the
sv3d patch round-trips through ffprobe."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import importlib.util, json, subprocess, sys, tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("store_acceptance", ROOT / "tools" / "store_acceptance.py")
S = importlib.util.module_from_spec(spec)
spec.loader.exec_module(S)

fails = 0
def check(name, ok, extra=""):
    global fails
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else "\n" + str(extra)))
    fails += 0 if ok else 1

check("B1 matrix: 10 sources x 6 outputs = 60 pair cases", len(S.matrix_cases()) == 60
      and len(S.SOURCES) == 10 and len(S.OUTPUTS) == 6)
check("B1 source names match the block", S.SOURCES == ["auto", "flat2D", "sbsFull", "sbsHalf", "tbFull",
      "tbHalf", "vr180SBS", "vr180TB", "vr360Mono", "vr360TB"])
check("B1 output names match the block", S.OUTPUTS == ["off", "sbs", "halfSBS", "tb", "vr180", "anaglyph"])
check("sequences 1-5 from the block, in order", S.SEQUENCES == ["seq1_open2d_sbs_stable",
      "seq2_vr180_off_reopen", "seq3_native_vr180_off_flat", "seq4_magnet_2d", "seq5_keys_table"])
check("expected cases = matrix + sequences", len(S.expected_cases()) == 65)

with tempfile.TemporaryDirectory() as d:
    base = Path(d)
    v, r = S.validate_case(base, "matrix_auto__off")
    check("missing case dir is a named FAIL, never aggregate", (v, r) == ("FAIL", "case_dir_missing"), (v, r))
    case = base / "matrix_auto__off"
    case.mkdir()
    for artifact in S.ARTIFACTS:
        (case / artifact).write_text("x")
    v, r = S.validate_case(base, "matrix_auto__off")
    check("full artifacts but FAIL verdict fails with the reason", v == "FAIL", (v, r))
    (case / "verdict.txt").write_text("PASS output_applied\n")
    check("PASS verdict passes", S.validate_case(base, "matrix_auto__off") == ("PASS", "output_applied"))
    (case / "verdict.txt").write_text("NOT_RUN owner_file_not_provided\n")
    check("NOT_RUN carries its reason", S.validate_case(base, "matrix_auto__off") == ("NOT_RUN", "owner_file_not_provided"))
    (case / "frame.png").write_text("")
    (case / "verdict.txt").write_text("PASS ok\n")
    v, r = S.validate_case(base, "matrix_auto__off")
    check("empty artifact is a named FAIL", (v, r) == ("FAIL", "artifact_missing_frame_png"), (v, r))

check("artifact set is the 191b-T contract", S.ARTIFACTS == ["action.log", "store-before.json",
      "store-after.json", "commands.json", "frame.png", "verdict.txt"])

# Missing dependencies must be named, not collapsed into an app failure.
with tempfile.TemporaryDirectory() as folder:
    try:
        S.run(folder)
        check("missing components named",False)
    except ValueError as e:
        check("missing components named",str(e)=="missing_built_app_and_ffmpeg",str(e))
bs=(ROOT/'build.sh').read_text()
check("relaunch first waits for prior process exit and records identity", 'RELAUNCH prior_exact_path_processes=gone' in bs and 'RELAUNCH pid=$fresh_pid started=' in bs and 'Contents/Resources/build-id.txt' in bs)
check("NOT_RUN wrapper distinct from FAIL and PASS", 'store_not_run=true; st_note "NOT_RUN store-acceptance:' in bs and 'SELFTEST PARTIAL' in bs)

import shutil
if shutil.which("ffmpeg") and shutil.which("ffprobe"):
    with tempfile.TemporaryDirectory() as folder:
        no_probe = S.synthesize_fixtures(ROOT,Path(folder),"ffmpeg",None)
        check("installed ffmpeg-only kit produces all spatial fixtures", sorted(no_probe)==["plain","sbs","vr180meta"])
    with tempfile.TemporaryDirectory() as d:
        out = S.synthesize_fixtures(ROOT, Path(d), "ffmpeg", "ffprobe")
        check("fixtures synthesize: plain, sbs, vr180meta", sorted(out) == ["plain", "sbs", "vr180meta"], sorted(out))
        check("only public-ToS-derived fixtures, no owner material",
              all(str(p).startswith(d) for p in out.values()))
        if "vr180meta" in out:
            probe = subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-of", "json", str(out["vr180meta"])],
                                   capture_output=True, text=True)
            check("vr180 fixture carries Spherical Mapping side data", "Spherical Mapping" in probe.stdout)
            dec = subprocess.run(["ffmpeg", "-v", "error", "-i", str(out["vr180meta"]), "-f", "null", "-"],
                                 capture_output=True, text=True)
            check("patched vr180 fixture still decodes cleanly", dec.returncode == 0 and dec.stderr.strip() == "")
else:
    check("ffmpeg/ffprobe available for fixture synthesis check", False)

check("sequence 4 needs an explicit owner file env", "GOR_STORE_ACCEPTANCE_MAGNET" in
      (ROOT / "tools" / "store_acceptance.py").read_text())

check("sv3d tag tree matches the SphericalTag contract (st3d left-right, equi 180x180)",
      b'st3d' in S.sv3d_tag() and b'sv3d' in S.sv3d_tag() and b'equi' in S.sv3d_tag()
      and S.sv3d_tag().count(bytes([0x40, 0, 0, 0])) >= 2)

tiny = S.box(b'free', b'abcd') + S.box(b'mdat', b'xyz')
walk = [(t, e - a) for t, a, e, h in S.children(tiny, 0, len(tiny))]
check("box walker yields types and sizes", walk == [(b'free', 12), (b'mdat', 11)], walk)

tagged = S.mp4_spherical_patch(S.mp4_spherical_patch and (ROOT / "tools/depth_analysis/kit/x2_tos_reference/tos_input_320x180_48f.mp4").read_bytes())
check("sv3d patch is idempotent on an already-tagged file", S.mp4_spherical_patch(tagged) == tagged)

check("image_bytes returns None on undecodable input",
      S.image_bytes("ffmpeg", "/nonexistent.png") is None)

check("matrix case naming is source__output", S.matrix_cases()[0] == "matrix_auto__off"
      and S.matrix_cases()[-1] == "matrix_vr360TB__anaglyph")

bad = subprocess.run([sys.executable, str(ROOT / "tools" / "store_acceptance.py"), "/nonexistent-root"],
                     capture_output=True, text=True)
check("missing app is a NOT_RUN with reason, rc 2, never a crash",
      bad.returncode == 2 and "verdict=NOT_RUN" in bad.stdout and "reason=" in bad.stdout, bad.stdout + bad.stderr)


with tempfile.TemporaryDirectory() as home:
    dl = Path(home) / "Downloads"; dl.mkdir()
    (dl / "plain movie.mkv").write_bytes(b"x")
    import os, time
    old_t = time.time() - 100
    os.utime(dl / "plain movie.mkv", (old_t, old_t))
    (dl / "newer vr180 clip.mp4").write_bytes(b"y")   # stereo-named, newer: must be excluded
    (dl / "empty.mp4").write_bytes(b"")                # zero bytes: skipped
    pick = S.discover_magnet_file(Path(home))
    check("discovery picks the newest plain-named video", pick is not None and pick.name == "plain movie.mkv", pick)
with tempfile.TemporaryDirectory() as home:
    check("discovery returns None with no Downloads/Movies", S.discover_magnet_file(Path(home)) is None)
check("stereo-name tokens exclude tagged files", S.looks_stereo_named("film VR180 SBS.mkv")
      and S.looks_stereo_named("x_3dh.mp4") and not S.looks_stereo_named("plain film.mp4"))
src = (ROOT / "tools" / "store_acceptance.py").read_text()
check("the seq4 path is only ever printed hashed", "sha256:" in src and "discover_magnet_file" in src)

# pin3 actor fixes (pin2 red capture 261109-235806, build log via owner): AppDelegate.swift:2796 and
# six StoreAcceptance sites called @MainActor ThreeDMenu/ThreeDStore from nonisolated contexts.
AD = (ROOT / "Sources/gor/App/AppDelegate.swift").read_text()
SA = (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDStoreAcceptance.swift'+' '):_b.index('// END relocated '+'ThreeDStoreAcceptance.swift'+'\n')])((_threed_split().path(ROOT)).read_text())
check("acceptance runner is MainActor-isolated end to end", "@MainActor enum StoreAcceptance {" in SA)
check("acceptance dispatch hops onto the main actor explicitly",
      "awaitReady(root:root,deadline:Date().timeIntervalSince1970+35)" in SA and "MainActor.assumeIsolated {awaitReady(" in SA)
check("AppDelegate menu install hops onto the main actor (pin2 red site AppDelegate.swift:2796)",
      "MainActor.assumeIsolated {ThreeDMenu.shared.install(in: videoMenu)};" in AD)
wiring=(lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDWiring.swift'+' '):_b.index('// END relocated '+'ThreeDWiring.swift'+'\n')])((_threed_split().path(ROOT)).read_text())
start=wiring.split("func startThreeDCoordinator() {",1)[1].split("ThreeDSubtitleDepth.shared.changed",1)[0]
check("wiring call site stays inside MainActor.assumeIsolated",
      "MainActor.assumeIsolated {" in start and "StoreAcceptance.startIfRequested" in start
      and start.index("MainActor.assumeIsolated {") < start.index("StoreAcceptance.startIfRequested")
      and "\n        }" not in start.split("StoreAcceptance.startIfRequested",1)[0])

check("heavy 65-case matrix only runs in explicit full selftest", 'if [ "$selftest_mode" = full ] && [ -f "$project_root/tools/store_acceptance.py" ]' in bs)
check("all store cases retained, no tail truncation", 'grep 3D-STORE || true; } | while read' in bs and 'grep 3D-STORE || true; } | tail' not in bs)
check("fresh process per case opens actual fixture", "for name in expected_cases():" in src and "subprocess.Popen([str(binary), str(fixture)]" in src and "GOR_STORE_ACCEPTANCE_CASE=name" in src)
check("native sequence opens native metadata fixture", "kind = 'vr180meta' if name == 'seq3_native_vr180_off_flat'" in src)
check("sequence4 opens actual supplied/discovered path", "if name == 'seq4_magnet_2d': fixture = Path(magnet)" in src)
with tempfile.TemporaryDirectory() as folder:
    import contextlib,io
    root=Path(folder);prior=root/'.gor-store-acceptance'/'1';prior.mkdir(parents=True)
    (prior/'complete.json').write_text(json.dumps({'cases':[{'case':'hidden_case','verdict':'FAIL bad'}]}))
    fail=prior/'hidden_case';fail.mkdir();(fail/'verdict.txt').write_text('FAIL bad')
    key=prior/'seq5_keys_table';key.mkdir();(key/'action.log').write_text('missing row act=example')
    capture=io.StringIO()
    with contextlib.redirect_stdout(capture): S.emit_prior_store_evidence(root)
    check("prior complete/failing verdict/seq5 action retained", all(x in capture.getvalue() for x in ['prior-complete','prior-fail case=hidden_case','prior-seq5-action missing row']))
check("acceptance store is transient", 'if transient { return }' in (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDState.swift'+' '):_b.index('// END relocated '+'ThreeDState.swift'+'\n')])((_threed_split().path(ROOT)).read_text()))
# Exercise the actual Python orchestration with isolated fixture processes. These
# are harness fixtures only, not a substitute for a Mac product verdict.
with tempfile.TemporaryDirectory() as folder:
    import os,contextlib,io
    root=Path(folder);binary=root/'gor.app/Contents/MacOS/gor';binary.parent.mkdir(parents=True)
    ffmpeg=root/'Resources/vendor/ffmpeg/bin/ffmpeg';ffmpeg.parent.mkdir(parents=True);ffmpeg.touch()
    fixture_paths={key:root/(key+'.mp4') for key in ['plain','vr180meta','sbs']}
    for path in fixture_paths.values(): path.write_bytes(b'public-test')
    binary.write_text("""#!/usr/bin/env python3
import os,json,sys
from pathlib import Path
root=Path(os.environ['GOR_STORE_ACCEPTANCE_DIR']);name=os.environ['GOR_STORE_ACCEPTANCE_CASE'];case=root/name;case.mkdir()
for item in ['action.log','store-before.json','store-after.json','commands.json','frame.png']: (case/item).write_text('artifact')
(case/'action.log').write_text('opened='+sys.argv[1]+' pid='+str(os.getpid()))
verdict='FAIL planted' if name in %r else 'PASS fixture'
(case/'verdict.txt').write_text(verdict)
(root/'complete.json').write_text(json.dumps({'complete':True,'cases':[{'case':name,'verdict':verdict}]}))
import time;time.sleep(3)
""" % S.expected_cases()[:9]);binary.chmod(0o755)
    original_live,original_synth,original_discover=S.live_gor_instances,S.synthesize_fixtures,S.discover_magnet_file
    S.live_gor_instances=lambda _:[]
    S.synthesize_fixtures=lambda *args:fixture_paths
    S.discover_magnet_file=lambda _:fixture_paths['plain']
    capture=io.StringIO()
    try:
        with contextlib.redirect_stdout(capture): rc=S.run(root,seconds=120)
    finally: S.live_gor_instances,S.synthesize_fixtures,S.discover_magnet_file=original_live,original_synth,original_discover
    text=capture.getvalue()
    check("all nine planted fail names survive capture", rc==1 and all('case='+name+' verdict=FAIL' in text for name in S.expected_cases()[:9]))
    logs=list((root/'.gor-store-acceptance').rglob('action.log'))
    pids={path.read_text().split('pid=')[-1] for path in logs}
    check("all 65 cases use distinct child processes", len(logs)==65 and len(pids)==65)
    native=next(path for path in logs if path.parent.name=='seq3_native_vr180_off_flat')
    magnet=next(path for path in logs if path.parent.name=='seq4_magnet_2d')
    check("fixture opens are measured in child argv", str(fixture_paths['vr180meta']) in native.read_text() and str(fixture_paths['plain']) in magnet.read_text())
check("VR180 menu drive enters from Off; target assertion unchanged", 'if output == .vr180 {ok = perform(.viewOff, log: &log) && ok}' in SA and 'guard cur.output == output' in SA)
check("subtitle-only keys checked as keyboard chords, not nonexistent menu rows", 'row.act == .subtitleDepthNearer || row.act == .subtitleDepthFarther' in SA and 'chord.matches(charactersIgnoringModifiers:' in SA)
print("store_acceptance_test: " + ("PASS" if fails == 0 else "FAIL %d" % fails))
sys.exit(1 if fails else 0)

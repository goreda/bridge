#!/usr/bin/env python3
"""191a pins for tools/gor_state_dump.py: token cleaning never leaks free text, paths are hashed,
vrOpenDecision keeps typed fields and drops the file name, every section degrades to NOT_RUN,
exit code is always 0, and the build.sh hook rides the subtitle evidence line without adding lines."""
import importlib.util, json, os, subprocess, sys, tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("gor_state_dump", ROOT / "tools" / "gor_state_dump.py")
G = importlib.util.module_from_spec(spec)
spec.loader.exec_module(G)

fails = 0
def check(name, ok, extra=""):
    global fails
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else "\n" + str(extra)))
    fails += 0 if ok else 1

check("geometry shader snapshot counts only, never paths", G.clean_geometry("glsl-shaders",["/secret/vr180-look-shader-a.glsl","/private/photon.glsl"]) == {"count":2,"look_count":1})
check("geometry crop rejects arbitrary text", G.clean_geometry("video-crop","/secret/film") is None and G.clean_geometry("video-crop","256x256+0+0")=="256x256+0+0")
check("Off receipt recursively excludes paths and arbitrary keys", G.clean_geometry("user-data/vr180-look/off-properties",{"glsl-shaders":["/private/shader"],"path":"/secret","video-zoom":0}) == {"glsl-shaders":{"count":1,"look_count":0},"video-zoom":0})
check("geometry unavailable is explicit",G.section_geometry(None)==["state-geometry NOT_RUN no running gor"])
check("tok keeps enums and numbers", G.tok("vr180") == "vr180" and G.tok(1920) == "1920" and G.tok(True) == "true")
check("tok strips free text to safe chars and bounds it", G.tok("/Users/o/My Film (1).mkv") == "_Users_o_My_Film__1_.mkv" and len(G.tok("x" * 500)) <= 48)
check("hashed_path never contains the path", G.hashed_path("/Users/o/secret/film.mkv").startswith("sha256:") and "secret" not in G.hashed_path("/Users/o/secret/film.mkv"))

rec = {"k": "vrOpenDecision", "file": "private-film-name.mkv", "w": 3840, "h": 1920, "decision": "vr180",
       "reason": "projectionMetadata", "probeStatus": "metadataAbsent", "remembered": "", "stereoIn": ""}
lines = ["noise", json.dumps(rec), json.dumps({"k": "vrOpenDecision", "file": "later.mkv", "decision": "mono", "reason": "monoNegative"})]
out = G.section_vr_open(lines)
check("last vrOpenDecision wins and keeps typed fields", out[0].startswith("state-vrOpenDecision ") and "decision=mono" in out[0] and "reason=monoNegative" in out[0], out)
check("vrOpenDecision never carries the file field", "file" not in out[0] and "later.mkv" not in out[0], out)
check("vrOpenDecision degrades when absent", G.section_vr_open(["nothing"])[0].startswith("state-vrOpenDecision NOT_RUN"))
check("vrOpenDecision degrades without a log", G.section_vr_open(None)[0].startswith("state-vrOpenDecision NOT_RUN"))

with tempfile.TemporaryDirectory() as d:
    res = Path(d) / "gor.app" / "Contents" / "Resources"
    res.mkdir(parents=True)
    (res / "build-id.txt").write_text("commit=abc123\nidentity_kind=source-manifest-sha256\n")
    check("installed build-id is reported", G.section_installed(d) == ["state-installed commit=abc123 kind=source-manifest-sha256"])
    check("installed degrades when missing", G.section_installed("/nonexistent")[0].startswith("state-installed NOT_RUN"))

check("gor3d-shot keeps bounded trace lines", G.section_shots(["gor3d-shot v1 shot=3 pts=1.500 menu_mode=full key=a/b"])[0].startswith("state-gor3d-shot gor3d-shot v1 shot=3"))
check("gor3d-shot degrades when absent", G.section_shots(["x"])[0].startswith("state-gor3d-shot NOT_RUN"))


check("tok handles floats, empty and colon values", G.tok(1.5) == "1.5" and G.tok("") == "-" and G.tok("a:b") == "a:b")
check("hashed_path is deterministic and distinct per path",
      G.hashed_path("/a.mkv") == G.hashed_path("/a.mkv") and G.hashed_path("/a.mkv") != G.hashed_path("/b.mkv"))

bad = ["{not json", '{"k":"other","x":1}', json.dumps({"k": "vrOpenDecision", "file": "f.mkv", "decision": "vr180"})]
out = G.section_vr_open(bad)
check("malformed lines are skipped, valid decision survives", "decision=vr180" in out[0], out)
rec2 = {"k": "vrOpenDecision", "file": "f.mkv", "decision": "mono", "reason": "remembered", "remembered": "vr180",
        "par": 1.0, "stereoIn": "mono", "metadataProjection": "vr180", "probeStereoSBS": False, "manualThisSession": True}
out = G.section_vr_open([json.dumps(rec2)])[0]
check("all typed fields ride the line", "remembered=vr180" in out and "par=1.0" in out and "metadataProjection=vr180" in out
      and "probeStereoSBS=false" in out and "manualThisSession=true" in out, out)

plist = {"gor.3d.sourceByFilm.v1.output": {"/Users/o/film a.mkv": "full_sbs", "/Users/o/film b.mkv": "off"},
         "gor.3d.sourceByFilm.v1.off": {"/Users/o/film b.mkv": True},
         "gor.3d.stereoSource": "flat", "unrelated.key": "x"}
out = G.format_defaults(plist)
check("per-file maps report counts and kinds", out[0] == "state-output entries=3"
      and any(l.startswith("state-output kind=output ") and "value=full_sbs" in l for l in out)
      and any(l.startswith("state-output kind=off ") and "value=true" in l for l in out), out)
check("no raw path anywhere in defaults output", not any("/Users/o" in l or "film a" in l for l in out), out)
check("global override is reported", out[-1] == "state-stereoSource value=flat", out)
check("empty maps degrade", G.format_defaults({})[0] == "state-output entries=0"
      and G.format_defaults({})[1].startswith("state-output NOT_RUN")
      and G.format_defaults({})[-1] == "state-stereoSource NOT_RUN unset")

check("vr-mode degrades without a running app", G.section_vr_mode(None)[0] == "state-vr-mode NOT_RUN no running gor")
out = G.section_trace_geom(None)
check("trace-geom reports not-running app and a launchctl state", out[0] == "state-trace-geom app=not-running"
      and out[1].startswith("state-trace-geom launchctl="), out)

r = subprocess.run([sys.executable, str(ROOT / "tools" / "gor_state_dump.py"), str(ROOT)], capture_output=True, text=True)
check("full run exits 0 with BEGIN/END markers", r.returncode == 0 and "BEGIN gor state dump v1" in r.stdout and r.stdout.rstrip().endswith("END gor state dump v1"), r.stdout)

b = (ROOT / "build.sh").read_text()
res_txt = b[b.index("gor_update_result_commit() {"):b.index("gor_update_exit_trap() {")]
hooks = [l for l in res_txt.splitlines() if "gor_state_dump.py" in l]
check("exactly one state dump hook line inside the result commit", len(hooks) == 1, hooks)
h = hooks[0] if hooks else ""
check("hook cannot fail the update and is bounded", "gor state dump unavailable" in h and "GOR_STEP_LIMIT=90" in h)
check("hook appends to subtitle evidence without new lines", 'subtitle_evidence="$subtitle_evidence"' in h)
check("build.sh is valid bash", subprocess.run(["bash", "-n", str(ROOT / "build.sh")]).returncode == 0)
print("gor_state_dump_test: " + ("PASS" if fails == 0 else "FAIL %d" % fails))
sys.exit(1 if fails else 0)

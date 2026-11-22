#!/usr/bin/env python3
"""191a update-capture state dump (owner 21:57): read-only snapshot of the installed gor's
routing state, appended to every ./build.sh --update capture so a reproduced defect can be
told apart from a stale install or a remembered per-file output.

Sections (each best-effort, each degrades to NOT_RUN <reason>, exit is always 0):
  state-installed     installed bundle's build-id.txt (source-manifest identity)
  state-vrOpenDecision last vrOpenDecision JSON from the gor diag log, typed fields only
  state-output        per-file OUTPUT/off/lastOutput/source maps from UserDefaults, paths hashed
  state-stereoSource  global gor.3d.stereoSource override, if set
  state-vr-mode       mpv user-data/gor-test-vr-mode of the running app over its IPC socket
  state-trace-geom    GOR_TRACE_GEOM on the running app's environment and launchctl
  state-gor3d-shot    last gor3d-shot v1 play-trace lines from the diag log

Privacy: no film paths or filenames. Paths are sha256-truncated; log JSON keeps only
token-cleaned fields (never the "file" field); every free string is reduced to [A-Za-z0-9._:+-].
"""
import hashlib, json, os, plistlib, re, socket, subprocess, sys

from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from session_log_paths import resolve
LOG = str(resolve("/tmp/gor_diag.log"))
TAIL = 512 * 1024
TOKEN = re.compile(r"[^A-Za-z0-9._:+-]")
LOGCHAR = re.compile(r"[^A-Za-z0-9 ._:+='-]")


def tok(value, limit=48):
    """Reduce any value to a bounded safe token; free text cannot leak into the capture."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    cleaned = TOKEN.sub("_", str(value))[:limit]
    return cleaned if cleaned else "-"


def hashed_path(path):
    return "sha256:" + hashlib.sha256(str(path).encode("utf-8", "replace")).hexdigest()[:12]


def section_installed(root):
    build_id = os.path.join(root, "gor.app", "Contents", "Resources", "build-id.txt")
    try:
        fields = dict(l.split("=", 1) for l in open(build_id).read().splitlines() if "=" in l)
        return ["state-installed commit=%s kind=%s" % (tok(fields.get("commit", "?"), 64), tok(fields.get("identity_kind", "?")))]
    except (OSError, ValueError):
        return ["state-installed NOT_RUN build-id.txt unreadable"]


def log_tail():
    try:
        with open(LOG, "rb") as f:
            f.seek(max(0, os.path.getsize(LOG) - TAIL))
            return f.read(TAIL).decode("utf-8", "replace").splitlines()
    except OSError:
        return None


def section_vr_open(lines):
    if lines is None:
        return ["state-vrOpenDecision NOT_RUN diag log unreadable"]
    keep = ("decision", "reason", "probeStatus", "w", "h", "par", "stereoIn", "metadataStereo",
            "metadataProjection", "probeProjection", "probeStereoSBS", "remembered", "manualThisSession")
    last = None
    for line in lines:
        at = line.find('{"')
        if "vrOpenDecision" in line and at >= 0:
            try:
                obj = json.loads(line[at:])
                if obj.get("k") == "vrOpenDecision":
                    last = obj
            except (ValueError, TypeError):
                pass
    if last is None:
        return ["state-vrOpenDecision NOT_RUN no vrOpenDecision in log tail"]
    return ["state-vrOpenDecision " + " ".join("%s=%s" % (k, tok(last[k])) for k in keep if k in last)]


def format_defaults(plist):
    """Pure: per-file routing maps and the global override from the gor UserDefaults plist."""
    out = []
    base = "gor.3d.sourceByFilm.v1"
    entries = 0
    for suffix, kind in (("", "source"), (".off", "off"), (".output", "output"), (".lastOutput", "lastOutput")):
        table = plist.get(base + suffix)
        if not isinstance(table, dict):
            continue
        for path in sorted(table)[:40]:
            entries += 1
            out.append("state-output kind=%s path=%s value=%s" % (kind, hashed_path(path), tok(table[path])))
    out.insert(0, "state-output entries=%d" % entries)
    if entries == 0:
        out.append("state-output NOT_RUN no per-file entries")
    override = plist.get("gor.3d.stereoSource")
    out.append("state-stereoSource value=%s" % tok(override) if isinstance(override, str) else "state-stereoSource NOT_RUN unset")
    return out


def section_defaults():
    try:
        raw = subprocess.run(["/usr/bin/defaults", "export", "com.gokcebalkan.gor", "-"],
                             capture_output=True, timeout=10).stdout
        plist = plistlib.loads(raw)
    except (OSError, ValueError, subprocess.SubprocessError):
        return ["state-output NOT_RUN defaults unreadable", "state-stereoSource NOT_RUN defaults unreadable"]
    return format_defaults(plist)


def running_gor_pid():
    try:
        pids = subprocess.run(["/usr/bin/pgrep", "-x", "gor"], capture_output=True, timeout=5).stdout.decode().split()
        return pids[0] if pids else None
    except (OSError, subprocess.SubprocessError):
        return None


def section_vr_mode(pid):
    if pid is None:
        return ["state-vr-mode NOT_RUN no running gor"]
    try:
        tmp = subprocess.run(["/usr/bin/getconf", "DARWIN_USER_TEMP_DIR"], capture_output=True, timeout=5).stdout.decode().strip()
        sock_path = os.path.join(tmp, "pp-%s.sock" % pid)
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(2)
        s.connect(sock_path)
        s.sendall(b'{"command":["get_property","user-data/gor-test-vr-mode"]}\n')
        reply = json.loads(s.recv(4096).decode("utf-8", "replace").splitlines()[0])
        s.close()
        return ["state-vr-mode value=%s source=ipc pid=%s" % (tok(reply.get("data")), tok(pid, 12))]
    except (OSError, ValueError, subprocess.SubprocessError, IndexError):
        return ["state-vr-mode NOT_RUN ipc unavailable"]


GEOMETRY_KEYS=("video-crop","video-aspect-override","video-zoom","video-pan-x","video-pan-y","panscan","video-scale-x","video-scale-y","keepaspect","glsl-shaders","glsl-shader-opts","user-data/vr180-look/off-properties")
def clean_geometry(key,value):
    if key=="glsl-shader-opts":
        return {"count":len(value),"look_count":sum(str(k).startswith("vr180-look-shader-") for k in value)} if isinstance(value,dict) else None
    if key=="glsl-shaders":
        return {"count":len(value),"look_count":sum("vr180-look-shader-" in str(x) for x in value)} if isinstance(value,list) else None
    if key=="user-data/vr180-look/off-properties":
        if isinstance(value,str):
            try:value=json.loads(value)
            except ValueError:return None
        return {k:clean_geometry(k,v) for k,v in value.items() if k in GEOMETRY_KEYS and k!=key} if isinstance(value,dict) else None
    if isinstance(value,(bool,int,float)) or value is None:return value
    if key=="video-crop" and (value=="" or re.fullmatch(r"[0-9x+.-]{1,80}",str(value))):return value
    return None

def section_geometry(pid):
    if pid is None:return ["state-geometry NOT_RUN no running gor"]
    try:
        tmp=subprocess.run(["/usr/bin/getconf","DARWIN_USER_TEMP_DIR"],capture_output=True,timeout=5).stdout.decode().strip()
        s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);s.settimeout(2);s.connect(os.path.join(tmp,"pp-%s.sock"%pid))
        for i,key in enumerate(GEOMETRY_KEYS):s.sendall((json.dumps({"command":["get_property",key],"request_id":100+i})+"\n").encode())
        values={};f=s.makefile("rb")
        for _ in range(100):
            row=json.loads(f.readline());i=row.get("request_id",0)-100
            if 0<=i<len(GEOMETRY_KEYS):values[GEOMETRY_KEYS[i]]=clean_geometry(GEOMETRY_KEYS[i],row.get("data"))
            if len(values)==len(GEOMETRY_KEYS):break
        f.close();s.close()
        if len(values)!=len(GEOMETRY_KEYS):return ["state-geometry NOT_RUN incomplete readback"]
        return ["state-geometry pid="+str(int(pid))+" "+json.dumps(values,sort_keys=True,separators=(",",":"))]
    except (OSError,ValueError,subprocess.SubprocessError,IndexError):return ["state-geometry NOT_RUN ipc unavailable"]


def section_trace_geom(pid):
    out = []
    if pid is not None:
        try:
            env = subprocess.run(["/bin/ps", "eww", "-p", pid], capture_output=True, timeout=5).stdout.decode("utf-8", "replace")
            out.append("state-trace-geom app=%s" % ("on" if "GOR_TRACE_GEOM=1" in env else "off"))
        except (OSError, subprocess.SubprocessError):
            out.append("state-trace-geom app=unknown")
    else:
        out.append("state-trace-geom app=not-running")
    try:
        val = subprocess.run(["/bin/launchctl", "getenv", "GOR_TRACE_GEOM"], capture_output=True, timeout=5).stdout.decode().strip()
        out.append("state-trace-geom launchctl=%s" % (tok(val) if val else "unset"))
    except (OSError, subprocess.SubprocessError):
        out.append("state-trace-geom launchctl=unknown")
    return out


def section_shots(lines):
    if lines is None:
        return ["state-gor3d-shot NOT_RUN diag log unreadable"]
    shots = ["state-gor3d-shot " + LOGCHAR.sub("_", l)[:300] for l in lines if l.startswith("gor3d-shot v1 ")][-6:]
    return shots if shots else ["state-gor3d-shot NOT_RUN none in log tail"]


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    out = ["BEGIN gor state dump v1"]
    lines = log_tail()
    out += section_installed(root)
    out += section_vr_open(lines)
    out += section_defaults()
    pid = running_gor_pid()
    out += section_vr_mode(pid)
    out += section_geometry(pid)
    out += section_trace_geom(pid)
    out += section_shots(lines)
    out.append("END gor state dump v1")
    print("\n".join(out))


if __name__ == "__main__":
    main()

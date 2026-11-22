#!/usr/bin/env python3
"""191c R4 Task 2: production-input mpv capture runner (roll fusion).

Drives the actual vr180-look.lua through its PRODUCTION input path. The pose
message name/arity and the mode-route messages are DISCOVERED from the shader
text at run time (never invented); a divergent or missing registration is a
refusal, not a fallback. Captures 2560x1600 window screenshots for every
(fixture x roll-angle) cell, plus crossed +/-15 cells and a separate
zero-roll baseline per fixture captured in a fresh mpv process with NO pose
message injected.

Evidence rules (GO 199bd item 4):
- Shader is bound to zuellue/gorav-native-ci @
  2ca10de8ab767d8a24d8c3f4b481e5d6984701e0 via a source-binding JSON carrying
  the pinned sha256. No verified binding -> NOT_RUN (default) or an
  explicitly labelled smoke run (--allow-unbound-smoke): acceptance_class
  "smoke_not_evidence", never presented as rendered evidence of the pin.
- Software rendering is labelled software; it is never Mac/GPU acceptance.
- Missing renderer/binding yields runnable code plus the exact error; no
  capture is ever fabricated.

Exit codes (semantic exit): 0 every planned cell captured; 2 NOT_RUN (zero
cells captured); 3 partial (mix of captured and error).
"""
import argparse, hashlib, json, math, os, re, shutil, socket, struct
import subprocess, sys, tempfile, time, zlib

SCHEMA = "roll-capture/v1"
RUNNER_VERSION = "1.3.0"
PIN_REPO = "zuellue/gorav-native-ci"
PIN_COMMIT = "2ca10de8ab767d8a24d8c3f4b481e5d6984701e0"
PIN_PATH = "payload/gor/Resources/vendor/mpv/scripts/vr180-look.lua"
ANGLES_DEG = (-30, -15, -5, 0, 5, 15, 30)
CROSSED_ANGLES_DEG = (-15, 15)
OUT_W, OUT_H = 2560, 1600
MANIFEST_SCHEMA = "roll-markers/v1"
BINDING_SCHEMA = "roll-source-binding/v1"
MODE_TO_KIND = {"sbs": "flat-sbs", "half_sbs": "flat-sbs",
                "top_bottom": "flat-tb", "mono": "flat-2d3d",
                "native_vr180": "vr180"}
KIND_TO_LAYOUT = {"flat-2d3d": 0, "flat-sbs": 1, "flat-tb": 2, "vr180": 3,
                  "vr180-tb": 4, "vr360-mono": 5, "vr360-tb": 6}
SOFTWARE_RENDERER_RE = re.compile(r"llvmpipe|softpipe|swrast|swiftshader|lavapipe", re.I)
REQUIRED_OPTION_KEYS = ("vr_roll", "vr_head_roll", "vr_cross_eye", "vr_source_layout",
                        "vr_flat_mono", "vr_flat_sbs", "vr_fov", "vr_eye_aspect")


class RunnerError(Exception):
    """Fatal error -> NOT_RUN (exit 2) with this exact message."""


class CellError(Exception):
    """Per-cell error -> record status 'error', exact message kept."""


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def git_blob_sha1_file(path):
    h = hashlib.sha1(b"blob %d\x00" % os.path.getsize(path))
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def png_dimensions(path):
    with open(path, "rb") as f:
        head = f.read(33)
    if len(head) < 33 or head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        raise ValueError("not a PNG: %s" % path)
    w, h = struct.unpack(">II", head[16:24])
    return w, h


def load_manifest(path):
    with open(path, "r") as f:
        doc = json.load(f)
    if doc.get("schema") != MANIFEST_SCHEMA:
        raise RunnerError("manifest schema is %r, expected %r" % (doc.get("schema"), MANIFEST_SCHEMA))
    fixtures = doc.get("fixtures")
    if not isinstance(fixtures, list) or not fixtures:
        raise RunnerError("manifest has no fixtures array")
    return doc, fixtures


def load_binding(path):
    """Return dict(repo, commit, path, sha256) or None if path is None."""
    if path is None:
        return None
    with open(path, "r") as f:
        doc = json.load(f)
    if doc.get("schema") != BINDING_SCHEMA:
        raise RunnerError("binding schema is %r, expected %r" % (doc.get("schema"), BINDING_SCHEMA))
    for key in ("repo", "commit", "path", "sha256"):
        if not doc.get(key):
            raise RunnerError("binding missing field %r" % key)
    if doc["repo"] != PIN_REPO or doc["commit"] != PIN_COMMIT or doc["path"] != PIN_PATH:
        raise RunnerError("binding points at %s@%s:%s, not the packet pin %s@%s:%s"
                          % (doc["repo"], doc["commit"], doc["path"], PIN_REPO, PIN_COMMIT, PIN_PATH))
    return doc


def resolve_binding(shader_path, binding, allow_smoke, provenance):
    """Classify the shader against the pin. Returns (status, expected_sha256, actual, blob1)."""
    if not os.path.isfile(shader_path):
        raise RunnerError("shader file not found: %s" % shader_path)
    actual = sha256_file(shader_path)
    blob1 = git_blob_sha1_file(shader_path)
    if binding is None:
        if not allow_smoke:
            raise RunnerError(
                "pinned shader binding missing: no %s carrier for %s@%s:%s; "
                "cannot prove the local shader is the pinned source (NOT_RUN, no captures fabricated)"
                % (BINDING_SCHEMA, PIN_REPO, PIN_COMMIT, PIN_PATH))
        if not provenance:
            raise RunnerError("--allow-unbound-smoke requires --provenance naming the unbound source")
        return "unbound-smoke", None, actual, blob1
    expected = binding["sha256"].lower()
    if actual.lower() != expected:
        raise RunnerError("shader sha256 mismatch: binding expects %s, file is %s" % (expected, actual))
    return "verified", expected, actual, blob1


REG_RE = re.compile(r'mp\.register_script_message\("([^"]+)"\s*,\s*function\s*\(([^)]*)\)')
KINDMAP_RE = re.compile(r'\["([a-z0-9\-]+)"\]\s*=\s*(\d)')
ROUTE_REG_RE = re.compile(r'register_route\("([^"]+)"\s*,\s*function\s*\(([^)]*)\)')


class ShaderContract(object):
    """Production input contract discovered from the shader text itself."""

    def __init__(self, text):
        self.text = text
        self.pose_message, self.pose_args = self._find_pose_message(text)
        self.store_revision_message = self._find_named(text, "store-revision")
        self.route = {}
        for name in ("set-projection", "set-pack", "set-enabled", "route-complete",
                     "viewing-cross", "set-swap-eyes"):
            self.route[name] = self._find_named(text, name)
        missing = [k for k, v in self.route.items() if v is None]
        if self.store_revision_message is None:
            missing.append("store-revision")
        if missing:
            raise RunnerError("shader lacks registered production messages: %s" % ", ".join(sorted(missing)))
        self.kinds = dict(KINDMAP_RE.findall(text))
        for need in ("flat-sbs", "flat-tb", "flat-2d3d", "vr180"):
            if need not in self.kinds:
                raise RunnerError("shader projection kind %r not found" % need)
        if "vr180-look-shader-" not in text:
            raise RunnerError("shader slot-file naming (vr180-look-shader-a|b.glsl) not found")
        if "installed-shader" not in text:
            raise RunnerError("shader installed-shader receipt not found")
        if "applied-state" not in text:
            raise RunnerError("shader applied-state publication not found")
        m = re.search(r"route_arity\s*=\s*\{([^}]*)\}", text)
        self.route_arity = {}
        if m:
            for name, num in re.findall(r'\["([^"]+)"\]\s*=\s*(\d+)', m.group(1)):
                self.route_arity[name] = int(num)
        self.store_revision_args = self._args_of(text, self.store_revision_message)
        need = ("revision", "kind", "sender", "want_enabled", "want_layout",
                "want_pack", "output", "engine", "generation", "file", "app_pid")
        if self.store_revision_args[:11] != list(need):
            raise RunnerError("store-revision arg list diverges from production: %r"
                              % (self.store_revision_args,))
        if '"store%-applier"' not in text and '"store-applier"' not in text:
            raise RunnerError("store-applier sender gate not found in shader")

    @staticmethod
    def _args_of(text, message):
        for m in REG_RE.finditer(text):
            if m.group(1) == message:
                return [a.strip() for a in m.group(2).split(",") if a.strip()]
        return []

    @staticmethod
    def _find_named(text, suffix):
        for m in REG_RE.finditer(text):
            if m.group(1).endswith(suffix):
                return m.group(1)
        for m in ROUTE_REG_RE.finditer(text):
            if m.group(1).endswith(suffix):
                return m.group(1)
        return None

    @staticmethod
    def _require(text, pat):
        return re.search(pat, text) is not None

    @staticmethod
    def _find_pose_message(text):
        """The pose input is the registration whose handler assigns vr_roll."""
        for m in REG_RE.finditer(text):
            args = [a.strip() for a in m.group(2).split(",") if a.strip()]
            body = text[m.end():m.end() + 4000]
            if "vr_roll" not in body:
                continue
            roll_idx = next((i for i, a in enumerate(args)
                             if a.rstrip("_s") in ("roll", "vr_roll")), None)
            if roll_idx is None:
                continue
            lowered = [a.rstrip("_s") for a in args]
            if not all(k in lowered for k in ("yaw", "pitch", "fov")):
                raise RunnerError("pose registration %r found but yaw/pitch/fov args missing: %r"
                                  % (m.group(1), args))
            return m.group(1), {"args": args, "roll_index": roll_idx}
        raise RunnerError("no registered script-message assigning vr_roll found in shader")

    def pose_argv(self, roll_rad):
        argv = [""] * len(self.pose_args["args"])
        argv[self.pose_args["roll_index"]] = "%.6f" % roll_rad
        return argv


def capture_id(fixture_id, kind, roll_deg, crossed=False, baseline=False):
    tag = "rollm%d" % abs(roll_deg) if roll_deg < 0 else "rollp%d" % roll_deg
    cid = "%s__%s__%s" % (fixture_id, kind, tag)
    if crossed:
        cid += "__crossed"
    if baseline:
        cid += "__baseline"
    return cid


def logical_eye_aspect(fx):
    dims = fx.get("logical_eye_dimensions")
    if isinstance(dims, list) and len(dims) == 2 and dims[1]:
        return dims[0] / float(dims[1])
    eyes = fx.get("eyes") or {}
    left = eyes.get("left") or [0, 0, fx["width"], fx["height"]]
    sar = fx.get("sample_aspect_ratio") or [1, 1]
    return (left[2] * sar[0] / float(sar[1])) / float(left[3])


class Cell(object):
    def __init__(self, fixture, kind, roll_deg, crossed=False, baseline=False):
        self.fixture = fixture
        self.fixture_id = fixture["id"]
        self.kind = kind
        self.roll_deg = roll_deg
        self.roll_rad = math.radians(roll_deg)
        self.crossed = crossed
        self.baseline = baseline
        self.capture_id = capture_id(self.fixture_id, kind, roll_deg, crossed, baseline)


def build_plan(fixtures):
    """Every fixture x 7 angles, one zero-roll baseline per fixture (fresh
    process, no pose), crossed +/-15 on each production kind's zero-disparity
    fixture."""
    cells = []
    for fx in fixtures:
        kind = MODE_TO_KIND.get(fx["mode"])
        if kind is None:
            raise RunnerError("fixture %r has unknown mode %r" % (fx["id"], fx["mode"]))
        for deg in ANGLES_DEG:
            cells.append(Cell(fx, kind, deg))
        cells.append(Cell(fx, kind, 0, baseline=True))
    zero_by_kind = {}
    for fx in fixtures:
        if (fx.get("signed_disparity_fraction") or 0) == 0:
            zero_by_kind.setdefault(MODE_TO_KIND[fx["mode"]], fx)
    for kind in sorted(zero_by_kind):
        for deg in CROSSED_ANGLES_DEG:
            cells.append(Cell(zero_by_kind[kind], kind, deg, crossed=True))
    return cells


def verify_fixture_bytes(fx, fixtures_dir):
    path = os.path.join(fixtures_dir, fx["path"])
    if not os.path.isfile(path):
        raise RunnerError("fixture image missing: %s" % path)
    actual = sha256_file(path)
    if fx.get("sha256") and actual.lower() != fx["sha256"].lower():
        raise RunnerError("fixture %r sha256 mismatch: manifest %s, file %s"
                          % (fx["id"], fx["sha256"], actual))
    w, h = png_dimensions(path)
    if (w, h) != (fx["width"], fx["height"]):
        raise RunnerError("fixture %r dims %dx%d, manifest says %dx%d"
                          % (fx["id"], w, h, fx["width"], fx["height"]))
    return path, actual


class IpcError(CellError):
    pass


class MpvIpc(object):
    """Minimal mpv JSON IPC client (unix socket, newline-terminated JSON)."""

    def __init__(self, sock_path, connect_timeout=15.0):
        deadline = time.monotonic() + connect_timeout
        while True:
            try:
                self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                self.sock.connect(sock_path)
                break
            except OSError:
                if time.monotonic() > deadline:
                    raise IpcError("mpv IPC socket never appeared: %s" % sock_path)
                time.sleep(0.05)
        self.sock.settimeout(0.1)
        self.buf = b""
        self.req_id = 0
        self.events = []

    def _read_once(self):
        try:
            data = self.sock.recv(65536)
        except socket.timeout:
            return
        except OSError as e:
            raise IpcError("mpv IPC read failed: %s" % e)
        if not data:
            raise IpcError("mpv closed the IPC socket (process died)")
        self.buf += data

    def _next_line(self, deadline):
        while b"\n" not in self.buf:
            if time.monotonic() > deadline:
                return None
            self._read_once()
        line, self.buf = self.buf.split(b"\n", 1)
        return json.loads(line.decode("utf-8", "replace"))

    def command(self, *args, timeout=15.0):
        self.req_id += 1
        rid = self.req_id
        self.sock.sendall(json.dumps({"command": list(args), "request_id": rid}).encode() + b"\n")
        deadline = time.monotonic() + timeout
        while True:
            msg = self._next_line(deadline)
            if msg is None:
                raise IpcError("mpv IPC timeout waiting for reply to %r" % (args,))
            if msg.get("request_id") == rid:
                if msg.get("error") not in (None, "success"):
                    raise IpcError("mpv command %r failed: %s" % (args, msg.get("error")))
                return msg.get("data")
            if "event" in msg:
                self.events.append(msg)

    def drain_events(self):
        """Drop everything already queued/received so only post-command events count."""
        deadline = time.monotonic() + 0.3
        while time.monotonic() < deadline:
            try:
                self.sock.settimeout(0.05)
                self._read_once()
            except IpcError:
                break
            if b"\n" in self.buf:
                line, self.buf = self.buf.split(b"\n", 1)
                try:
                    msg = json.loads(line.decode("utf-8", "replace"))
                    if "event" in msg:
                        self.events.append(msg)
                except ValueError:
                    pass
            else:
                break
        self.sock.settimeout(0.1)
        self.events = []

    def wait_event(self, names, timeout):
        deadline = time.monotonic() + timeout
        while True:
            for i, ev in enumerate(self.events):
                if ev.get("event") in names:
                    self.events.pop(i)
                    return ev
            if time.monotonic() > deadline:
                raise IpcError("timed out (%.1fs) waiting for mpv event %s" % (timeout, "/".join(names)))
            msg = self._next_line(deadline)
            if msg is not None and "event" in msg:
                self.events.append(msg)

    def get_property(self, name, native=False):
        if native:
            return self.command("get_property", name)
        return self.command("get_property", name)

    def wait_property(self, name, predicate, timeout, poll=0.05, native=True):
        deadline = time.monotonic() + timeout
        last = None
        while time.monotonic() <= deadline:
            try:
                last = self.command("get_property", name)
            except IpcError:
                last = None
            if last is not None and predicate(last):
                return last
            time.sleep(poll)
        raise IpcError("stale option: property %r never satisfied (last=%r, waited %.1fs)"
                       % (name, last, timeout))


class Display(object):
    """One Xvfb (preferred) or surfaceless-EGL environment for all cells."""

    def __init__(self, log):
        self.proc = None
        self.env_extra = {}
        self.name = None
        self.log = log
        xvfb = shutil.which("Xvfb")
        if xvfb:
            disp = ":%d" % (100 + (os.getpid() % 800))
            self.proc = subprocess.Popen(
                [xvfb, disp, "-screen", "0", "%dx%dx24" % (OUT_W, OUT_H), "-nolisten", "tcp"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            deadline = time.monotonic() + 10
            sock = "/tmp/.X11-unix/X%s" % disp[1:]
            while time.monotonic() < deadline and not os.path.exists(sock):
                if self.proc.poll() is not None:
                    break
                time.sleep(0.05)
            if os.path.exists(sock):
                self.env_extra = {"DISPLAY": disp}
                self.name = "xvfb"
                log("display: Xvfb %s %dx%d" % (disp, OUT_W, OUT_H))
                return
            self.proc.kill()
            self.proc = None
        raise RunnerError("no display: Xvfb missing (this mpv build exposes no "
                          "surfaceless EGL context; x11egl via Xvfb is the headless path)")

    def gpu_context_args(self):
        return ["--gpu-context=x11egl"]

    def close(self):
        if self.proc is not None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
            self.proc = None


def classify_renderer(log_text):
    m = re.search(r"GL_RENDERER='([^']+)'", log_text)
    renderer = m.group(1) if m else None
    if renderer is None:
        return None, "unknown"
    cls = "software" if SOFTWARE_RENDERER_RE.search(renderer) else "hardware"
    return renderer, cls


SHADER_LOG_ERROR_RE = re.compile(
    r"^\[[^\]]*\]\[e\]\[vo/gpu(?:/[^\]]+)?\].*"
    r"(Unrecognized command|Error while parsing|No FORMAT specified|"
    r"compile|compilation|linking|parse)")

MAX_SHADER_ERROR_LINES = 20


def scan_shader_log(log_path):
    """Raw vo/gpu error lines indicating shader parse/compile/link failure.
    mpv aborts a user shader at the first unrecognized directive, so one bad
    line means the pass (and everything after it) never installed."""
    if not log_path or not os.path.isfile(log_path):
        return []
    hits = []
    with open(log_path, errors="replace") as f:
        for line in f:
            if SHADER_LOG_ERROR_RE.search(line.rstrip("\n")):
                hits.append(line.rstrip("\n"))
                if len(hits) >= MAX_SHADER_ERROR_LINES:
                    break
    return hits


class MpvProcess(object):
    """One mpv instance bound to one capture cell."""

    def __init__(self, mpv_bin, shader_path, home, display, log_path, extra_env=None):
        self.mpv_bin = mpv_bin
        self.shader_path = shader_path
        self.home = home
        self.display = display
        self.log_path = log_path
        self.sock_path = os.path.join(home, "mpv-ipc.sock")
        self.proc = None
        self.ipc = None
        self.argv = None
        self.extra_env = extra_env or {}

    def start(self, fixture_path, allow_sw):
        config_dir = os.path.join(self.home, ".config", "mpv")
        os.makedirs(config_dir, exist_ok=True)
        argv = [self.mpv_bin, "--config-dir=" + config_dir,
                "--idle=yes", "--force-window=yes", "--keep-open=yes",
                "--vo=gpu", "--gpu-api=opengl",
                "--geometry=%dx%d" % (OUT_W, OUT_H), "--hidpi-window-scale=no",
                "--image-display-duration=inf", "--pause=no",
                "--osd-level=0", "--no-osd-bar", "--no-osc",
                "--no-input-default-bindings", "--audio=no", "--hwdec=no",
                "--screenshot-format=png", "--screenshot-png-compression=3",
                "--msg-level=all=v",
                "--log-file=" + self.log_path,
                "--input-ipc-server=" + self.sock_path,
                "--scripts-append=" + self.shader_path,
                ]
        if allow_sw:
            argv.append("--gpu-sw")
        argv += self.display.gpu_context_args()
        argv.append(fixture_path)
        self.argv = argv
        env = dict(os.environ)
        env.update(self.display.env_extra)
        env.update(self.extra_env)
        env["HOME"] = self.home
        env["XDG_CONFIG_HOME"] = os.path.join(self.home, ".config")
        err_path = self.log_path + ".stderr"
        self._err_file = open(err_path, "wb")
        self.proc = subprocess.Popen(argv, env=env, stdin=subprocess.DEVNULL,
                                     stdout=self._err_file, stderr=self._err_file)
        deadline = time.monotonic() + 20
        while not os.path.exists(self.sock_path):
            rc = self.proc.poll()
            if rc is not None:
                self._err_file.flush()
                tail = open(err_path, errors="replace").read()[-600:]
                raise CellError("mpv exited at startup (rc=%s): %s" % (rc, tail.strip() or "no stderr"))
            if time.monotonic() > deadline:
                break
            time.sleep(0.05)
        try:
            self.ipc = MpvIpc(self.sock_path, connect_timeout=5)
        except IpcError:
            self._err_file.flush()
            tail = ""
            if os.path.isfile(self.log_path):
                tail = open(self.log_path, errors="replace").read()[-800:]
            rc = self.proc.poll()
            raise CellError("mpv failed to start (rc=%s): %s" % (rc, tail.strip() or "no log"))
        self.ipc.wait_event(("file-loaded",), timeout=30)

    def stop(self):
        if self.ipc is not None:
            try:
                self.ipc.command("quit", timeout=3)
            except Exception:
                pass
        if self.proc is not None:
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait(timeout=5)
        if getattr(self, "_err_file", None) is not None:
            try:
                self._err_file.close()
            except Exception:
                pass
            self._err_file = None
        self.proc = None
        self.ipc = None


ROUTE_SENDER = "store-applier"


def route_messages(contract, cell, aspect, revision="1"):
    kind = cell.kind
    layout = KIND_TO_LAYOUT[kind]
    msgs = [[contract.store_revision_message, revision, kind, ROUTE_SENDER, "true",
             str(layout), "0", "sbs", "mpv", revision, cell.fixture["path"], "pid-test"]]
    if kind == "flat-2d3d":
        msgs.append([contract.route["set-pack"], "0", "1", "0.5", "1", "1", revision, ROUTE_SENDER])
    msgs.append([contract.route["set-projection"], kind, "%.6f" % aspect, revision, ROUTE_SENDER])
    msgs.append([contract.route["set-enabled"], "true", revision, ROUTE_SENDER])
    msgs.append([contract.route["route-complete"], revision, ROUTE_SENDER])
    return msgs


# vr_fov is pushed deg2rad()-converted (135 deg default), i.e. radians in the uniform.
DEFAULT_FOV = math.radians(135.0)

RENDER_PROOF_NOTE = ("Per-cell option_receipt and the mpv log prove the shader installed, "
                     "the route applied and the uniforms settled. A receipt alone is NOT "
                     "render proof: a level marker grid at native +15 is indistinguishable "
                     "from an unapplied shader without pixel measurement, which is the "
                     "scorer's job. The lua's installed-shader PASS is the script's own "
                     "byte/entry check; it does not prove mpv parsed the shader. Cells whose "
                     "mpv log carries shader parse/compile errors are flagged "
                     "captured_shader_error and their image is the untransformed frame.")


def expected_option_state(cell, aspect, pose_injected):
    layout = float(KIND_TO_LAYOUT[cell.kind])
    flat = cell.kind in ("flat-sbs", "flat-tb", "flat-2d3d")
    roll = cell.roll_rad if pose_injected else 0.0
    exp = {"vr_roll": roll, "vr_head_roll": roll,
           "vr_cross_eye": 1.0 if cell.crossed else 0.0,
           "vr_source_layout": layout,
           "vr_flat_sbs": 1.0 if flat else 0.0,
           "vr_flat_mono": 1.0 if cell.kind == "flat-2d3d" else 0.0,
           "vr_fov": DEFAULT_FOV}
    if flat:
        exp["vr_eye_aspect"] = aspect
    return exp


def _opts_full_match(exp, slot):
    """None until every required key is present in the ACTIVE shader slot's
    namespace, then True or a mismatch list. Only one coherent namespace may
    satisfy the expectation: keys from the other (stale) slot are ignored, so
    a mixed map can never assemble a pass from two slots."""
    prefix = "vr180-look-shader-%s/" % slot
    def pred(opts):
        if not isinstance(opts, dict):
            return None
        got = {}
        for k, v in opts.items():
            ks = str(k)
            if ks.startswith(prefix):
                got[ks[len(prefix):]] = v
        if not any(k.startswith("vr_roll") for k in got):
            return None
        bad = []
        for key, want in exp.items():
            if key not in got:
                bad.append("%s missing" % key)
                continue
            try:
                val = float(got[key])
            except (TypeError, ValueError):
                bad.append("%s unparseable %r" % (key, got[key]))
                continue
            if not math.isfinite(val):
                bad.append("%s non-finite %r" % (key, got[key]))
                continue
            tol = 5e-7 if abs(want) < 1 else 1e-4
            if abs(val - want) > tol:
                bad.append("%s expected %.6f got %.6f" % (key, want, val))
        return bad
    return pred


def capture_cell(cell, contract, drv, out_dir, binding_status, renderer, timeout_s,
                 pose_injected=True):
    rec = {
        "capture_id": cell.capture_id,
        "fixture_id": cell.fixture_id,
        "fixture_sha256": cell.fixture.get("sha256"),
        "mode": cell.kind,
        "production_route": {"kind": cell.kind,
                             "aspect": round(logical_eye_aspect(cell.fixture), 6)},
        "roll_deg": cell.roll_deg,
        "roll_rad": round(cell.roll_rad, 6),
        "crossed": cell.crossed,
        "zero_roll_baseline": cell.baseline,
        "pose_message": None,
        "effective_options": None,
        "shader_slot": None,
        "shader_sha256": None,
        "renderer_class": renderer[1],
        "status": "error",
        "error": None,
        "image": None,
        "acceptance_class": "evidence" if binding_status == "verified" else "smoke_not_evidence",
        "golden": {"bound": False, "golden_sha256": None, "golden_path": None},
        "option_receipt": None,
        "shader_errors": None,
        "sync": {"option_sync": "glsl-shader-opts vr_roll observed",
                 "frame_sync": "seek 0 absolute+exact -> playback-restart",
                 "timeout_s": timeout_s},
        "command": None,
        "timings": {},
    }
    t0 = time.monotonic()
    os.makedirs(os.path.join(out_dir, "captures"), exist_ok=True)
    png_path = os.path.join(out_dir, "captures", cell.capture_id + ".png")
    fixture_path = cell.fixture["_abs_path"]
    try:
        drv.start(fixture_path, allow_sw=True)
        rec["command"] = drv.argv
        ipc = drv.ipc
        aspect = logical_eye_aspect(cell.fixture)
        for msg in route_messages(contract, cell, aspect):
            ipc.command("script-message", *msg)
        # route + shader receipts
        inst = ipc.wait_property("user-data/vr180-look/installed-shader",
                                 lambda d: isinstance(d, dict) and d.get("verdict") == "PASS",
                                 timeout=timeout_s)
        ms = re.search(r"vr180-look-shader-([ab])\.glsl\s*$", str(inst.get("entry") or ""))
        if not ms:
            raise CellError("installed-shader verdict PASS but entry names no a/b slot: %r"
                            % (inst.get("entry"),))
        slot = ms.group(1)
        rec["shader_slot"] = "vr180-look-shader-" + slot
        def _applied_ok(s):
            if not isinstance(s, str):
                return False
            try:
                d = json.loads(s)
            except ValueError:
                return False
            return (d.get("enabled") is True
                    and str(d.get("completed_revision")) == "1"
                    and d.get("source_layout") == KIND_TO_LAYOUT[cell.kind])
        applied_raw = ipc.wait_property("user-data/vr180-look/applied-state", _applied_ok,
                                        timeout=timeout_s)
        if cell.crossed:
            ipc.command("script-message", contract.route["viewing-cross"], "true")
        if pose_injected:
            argv = contract.pose_argv(cell.roll_rad)
            ipc.command("script-message", contract.pose_message, *argv)
            rec["pose_message"] = {"name": contract.pose_message, "args": argv}
        else:
            rec["pose_message"] = {"name": contract.pose_message, "args": None,
                                   "note": "zero-roll baseline: no pose injected"}
        aspect_now = logical_eye_aspect(cell.fixture)
        exp = expected_option_state(cell, aspect_now, pose_injected)
        pred = _opts_full_match(exp, slot)
        last_bad = [None]

        def _check(opts):
            r = pred(opts)
            if isinstance(r, list):
                last_bad[0] = r
            return r == []

        try:
            opts = ipc.wait_property("glsl-shader-opts", _check, timeout=timeout_s)
        except IpcError as e:
            raise CellError("stale or wrong shader state: %s; last mismatches: %s"
                            % (e, last_bad[0]))
        pref = "vr180-look-shader-%s/" % slot
        rec["effective_options"] = {str(k)[len(pref):]: v for k, v in sorted(opts.items())
                                    if str(k).startswith(pref)}
        receipt_vals = {}
        for k, v in sorted(opts.items()):
            ks = str(k)
            if not ks.startswith(pref):
                continue
            try:
                fv = float(v)
                receipt_vals[ks[len(pref):]] = fv if math.isfinite(fv) else str(v)
            except (TypeError, ValueError):
                receipt_vals[ks[len(pref):]] = v
        rec["option_receipt"] = {
            "source": "glsl-shader-opts uniform readback (active slot %s only) plus "
                      "user-data/vr180-look installed-shader and applied-state receipts" % rec["shader_slot"],
            "slot": rec["shader_slot"],
            "installed_shader": inst,
            "installed_shader_verdict": "PASS",
            "applied_state": (json.loads(applied_raw) if isinstance(applied_raw, str)
                              else applied_raw),
            "values": receipt_vals,
            "matched_expectation": True}
        rec["timings"]["uniforms_settled_s"] = round(time.monotonic() - t0, 3)
        ipc.drain_events()
        ipc.command("seek", "0", "absolute+exact")
        ipc.wait_event(("playback-restart", "video-reconfig"), timeout=timeout_s)
        rec["timings"]["frame_settled_s"] = round(time.monotonic() - t0, 3)
        ipc.command("screenshot-to-file", png_path, "window", timeout=timeout_s)
        if not wait_file_stable(png_path, timeout_s):
            raise CellError("capture file missing or never stabilized: %s" % png_path)
        w, h = png_dimensions(png_path)
        if (w, h) != (OUT_W, OUT_H):
            raise CellError("capture size %dx%d, expected %dx%d (output surface wrong)"
                            % (w, h, OUT_W, OUT_H))
        rec["image"] = {"path": os.path.relpath(png_path, out_dir),
                        "sha256": sha256_file(png_path), "width": w, "height": h}
        rec["status"] = "captured"
    except (CellError, IpcError) as e:
        rec["error"] = str(e)
    except Exception as e:  # unexpected: still an exact, explicit error
        rec["error"] = "%s: %s" % (type(e).__name__, e)
    finally:
        rec["timings"]["total_s"] = round(time.monotonic() - t0, 3)
        try:
            drv.stop()
        except Exception:
            pass
    return rec


def wait_file_stable(path, timeout, interval=0.1):
    deadline = time.monotonic() + timeout
    last = -1
    while time.monotonic() <= deadline:
        try:
            size = os.path.getsize(path)
        except OSError:
            time.sleep(interval)
            continue
        if size > 0 and size == last:
            return True
        last = size
        time.sleep(interval)
    return False


EXPECTED_ARITY = {"set-projection": 2, "set-pack": 5, "set-enabled": 1}


def check_route_arity(contract):
    for suffix, want in EXPECTED_ARITY.items():
        full = contract.route[suffix]
        got = contract.route_arity.get(full)
        if got is not None and got != want:
            raise RunnerError("route message %s arity %d, production expects %d"
                              % (full, got, want))


GOLDEN_SCHEMA = "roll-golden-baseline/v1"


def load_golden(path):
    """Golden zero-roll baseline carrier: binds the theta=0 regression to the
    CURRENT SHIPPING build's captures, never to this run's own shader output.
    shader_sha256 in the carrier is the SHIPPING build's shader hash and may
    differ from the run shader; it is recorded, not required to match. Every
    referenced golden image is opened and hash-verified here; a missing file
    or hash mismatch is a hard error. Without a carrier the golden comparison
    is NOT_RUN; the run's own zero-roll cells are never a golden baseline."""
    if path is None:
        return None
    with open(path, "r") as f:
        doc = json.load(f)
    if doc.get("schema") != GOLDEN_SCHEMA:
        raise RunnerError("golden schema is %r, expected %r" % (doc.get("schema"), GOLDEN_SCHEMA))
    ship_sha = doc.get("shader_sha256")
    if not ship_sha:
        raise RunnerError("golden carrier missing shader_sha256 "
                          "(the shipping build's shader hash)")
    caps = doc.get("captures")
    if not isinstance(caps, dict) or not caps:
        raise RunnerError("golden carrier has no captures map")
    base = os.path.dirname(os.path.abspath(path))
    bound = {}
    for key in sorted(caps):
        ent = caps[key]
        if not isinstance(ent, dict) or not ent.get("path") or not ent.get("sha256"):
            raise RunnerError("golden entry %r missing path/sha256" % key)
        p = ent["path"]
        if not os.path.isabs(p):
            p = os.path.join(base, p)
        if not os.path.isfile(p):
            raise RunnerError("golden image missing for %r: %s" % (key, p))
        actual = sha256_file(p)
        if actual.lower() != str(ent["sha256"]).lower():
            raise RunnerError("golden image %r sha256 mismatch: carrier %s, file %s"
                              % (key, ent["sha256"], actual))
        bound[key] = {"path": p, "sha256": actual}
    return {"shipping_shader_sha256": str(ship_sha), "captures": bound,
            "carrier": os.path.abspath(path)}


def mpv_versions(mpv_bin, env_extra):
    env = dict(os.environ)
    env.update(env_extra)
    try:
        out = subprocess.run([mpv_bin, "--version"], env=env, capture_output=True,
                             text=True, timeout=30)
        first = out.stdout.splitlines()[0] if out.stdout else ""
        libmpv = next((l.strip() for l in out.stdout.splitlines() if "libmpv" in l), "")
        return first.strip(), libmpv
    except (OSError, subprocess.TimeoutExpired) as e:
        raise RunnerError("mpv not runnable at %r: %s" % (mpv_bin, e))


def log_line(msg):
    sys.stderr.write("[run_roll_capture] %s\n" % msg)
    sys.stderr.flush()


def run(args, driver_factory=None):
    t_start = time.monotonic()
    out_dir = os.path.abspath(args.out)
    os.makedirs(os.path.join(out_dir, "captures"), exist_ok=True)
    os.makedirs(os.path.join(out_dir, "logs"), exist_ok=True)
    manifest_doc, fixtures = load_manifest(args.manifest)
    fixtures_dir = os.path.abspath(args.fixtures_dir or os.path.dirname(args.manifest))
    for fx in fixtures:
        path, _ = verify_fixture_bytes(fx, fixtures_dir)
        fx["_abs_path"] = path
    manifest_sha = sha256_file(args.manifest)
    binding = load_binding(args.binding)
    binding_status, expected_sha, shader_sha, blob1 = resolve_binding(
        args.shader, binding, args.allow_unbound_smoke, args.provenance)
    shader_text = open(args.shader, "r", errors="replace").read()
    contract = ShaderContract(shader_text)
    check_route_arity(contract)
    golden = load_golden(args.golden) if args.golden else None
    cells = build_plan(fixtures)
    if args.only:
        cells = [c for c in cells
                 if any(c.capture_id.startswith(pfx) or pfx in c.capture_id for pfx in args.only)]
        if not cells:
            raise RunnerError("--only matched no cells")
    records = []
    fatal_env = None
    env_block = {
        "evidence_class": "synthetic-linux",
        "clean_checkout": False,
        "toolchain": {"python3": sys.version.split()[0], "mpv": None, "libmpv": None,
                      "vo": "gpu", "gpu_api": "opengl",
                      "gpu_context": None, "display": None,
                      "os": " ".join(os.uname()[0:3])},
        "renderer_class": "unavailable",
        "renderer_string": None,
        "mpv_binary_sha256": sha256_file(args.mpv) if os.path.isfile(args.mpv) else None,
    }
    display = None
    idx_path = os.path.join(out_dir, "run_roll_capture.index.json")

    def write_index(snapshot=True):
        cap = sum(1 for x in records if x["status"] == "captured")
        err = sum(1 for x in records if x["status"] == "error")
        sherr = sum(1 for x in records if x["status"] == "captured_shader_error")
        doc = {
            "schema": SCHEMA,
            "created_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "runner": {"name": "run_roll_capture.py", "version": RUNNER_VERSION,
                       "sha256": sha256_file(os.path.abspath(__file__))},
            "environment": env_block,
            "source": {"repo": PIN_REPO, "commit": PIN_COMMIT, "path": PIN_PATH,
                       "expected_sha256": expected_sha, "actual_sha256": shader_sha,
                       "git_blob_sha1": blob1, "binding_status": binding_status,
                       "provenance": args.provenance if binding_status != "verified"
                       else "pinned-carrier",
                       "provenance_assertion": "issuer-asserted; hash equality with a carrier "
                       "proves carrier equality only, never provenance by itself"},
            "fixtures_manifest": {"schema": MANIFEST_SCHEMA,
                                  "path": os.path.abspath(args.manifest), "sha256": manifest_sha},
            "planned_cells": len(cells), "captured": cap, "errored": err,
            "shader_errored": sherr,
            "complete": False,
            "acceptance_evidence": False,
            "render_proof_note": RENDER_PROOF_NOTE,
            "fatal_error": None,
            "captures": records,
        }
        tmpf = idx_path + ".tmp"
        with open(tmpf, "w") as f:
            json.dump(doc, f, indent=2)
            f.write("\n")
        os.rename(tmpf, idx_path)

    try:
        if driver_factory is not None:
            env_block["toolchain"]["mpv"] = "fake-driver (tests)"
            env_block["toolchain"]["display"] = "none (tests)"
        else:
            mpv_ver, libmpv_ver = mpv_versions(args.mpv, {})
            env_block["toolchain"]["mpv"] = mpv_ver
            env_block["toolchain"]["libmpv"] = libmpv_ver
            display = Display(log_line)
            env_block["toolchain"]["display"] = display.name
            env_block["toolchain"]["gpu_context"] = display.gpu_context_args()[0].split("=")[1]
        renderer = (None, "unknown")
        for i, cell in enumerate(cells):
            home = tempfile.mkdtemp(prefix="rollcap-home-", dir=out_dir)
            log_path = os.path.join(out_dir, "logs", cell.capture_id + ".mpv.log")
            if driver_factory is not None:
                drv = driver_factory(home, log_path)
            else:
                drv = MpvProcess(args.mpv, args.shader, home, display, log_path,
                                 extra_env={"GOR_VR_SAFE_MARKER": ""})
            rec = capture_cell(cell, contract, drv, out_dir, binding_status, renderer,
                               args.timeout, pose_injected=not cell.baseline)
            if cell.baseline:
                if golden:
                    g = golden["captures"].get(cell.fixture_id)
                    rec["golden"] = {"bound": bool(g),
                                     "golden_sha256": (g or {}).get("sha256"),
                                     "golden_path": (g or {}).get("path"),
                                     "golden_hash_verified": bool(g),
                                     "shipping_shader_sha256": golden["shipping_shader_sha256"]}
                else:
                    rec["golden"] = {"bound": False, "golden_sha256": None, "golden_path": None,
                                     "golden_hash_verified": False,
                                     "note": "no golden carrier: this zero-roll capture is a "
                                             "baseline candidate, never a golden baseline"}
            rec["log"] = os.path.relpath(log_path, out_dir)
            shader_errs = scan_shader_log(log_path)
            if shader_errs and rec["status"] == "captured":
                rec["status"] = "captured_shader_error"
                rec["shader_errors"] = shader_errs
                rec["error"] = ("mpv rejected the shader source (%d error line(s), first: %s); "
                                "the image is the untransformed frame"
                                % (len(shader_errs), shader_errs[0].split("]", 3)[-1].strip()))
            if renderer[0] is None and os.path.isfile(log_path):
                renderer = classify_renderer(open(log_path, errors="replace").read())
                env_block["renderer_string"] = renderer[0]
                env_block["renderer_class"] = renderer[1]
            rec["renderer_class"] = env_block["renderer_class"]
            records.append(rec)
            log_line("%d/%d %s -> %s%s" % (i + 1, len(cells), cell.capture_id, rec["status"],
                                           (" (" + rec["error"] + ")") if rec["error"] else ""))
            shutil.rmtree(home, ignore_errors=True)
            write_index(snapshot=False)
    except RunnerError:
        raise
    except Exception as e:
        fatal_env = "%s: %s" % (type(e).__name__, e)
    finally:
        if display is not None:
            display.close()
    captured = sum(1 for r in records if r["status"] == "captured")
    errored = sum(1 for r in records if r["status"] == "error")
    shader_errored = sum(1 for r in records if r["status"] == "captured_shader_error")
    for r in records:
        r.setdefault("shader_sha256", shader_sha)
        if r["shader_sha256"] is None:
            r["shader_sha256"] = shader_sha
    index = {
        "schema": SCHEMA,
        "created_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "runner": {"name": "run_roll_capture.py", "version": RUNNER_VERSION,
                   "sha256": sha256_file(os.path.abspath(__file__))},
        "environment": env_block,
        "source": {"repo": PIN_REPO, "commit": PIN_COMMIT, "path": PIN_PATH,
                   "expected_sha256": expected_sha, "actual_sha256": shader_sha,
                   "git_blob_sha1": blob1, "binding_status": binding_status,
                   "provenance": args.provenance if binding_status != "verified"
                   else "pinned-carrier",
                   "provenance_assertion": "issuer-asserted; hash equality with a carrier "
                   "proves carrier equality only, never provenance by itself"},
        "fixtures_manifest": {"schema": MANIFEST_SCHEMA,
                              "path": os.path.abspath(args.manifest), "sha256": manifest_sha},
        "planned_cells": len(cells), "captured": captured, "errored": errored,
        "shader_errored": shader_errored,
        "complete": (not args.only) and fatal_env is None and shader_errored == 0,
        "acceptance_evidence": (binding_status == "verified" and not args.only
                                and captured == len(cells) and errored == 0),
        "golden_comparison": ({"status": "recorded",
                               "carrier": golden["carrier"],
                               "shipping_shader_sha256": golden["shipping_shader_sha256"],
                               "run_shader_sha256": shader_sha,
                               "same_shader_as_run": golden["shipping_shader_sha256"].lower()
                               == (shader_sha or "").lower(),
                               "bound_baselines": sum(1 for x in records
                                                      if x.get("zero_roll_baseline")
                                                      and x.get("golden", {}).get("bound")),
                               "note": "runner opened and hash-verified every golden image; "
                                       "pixel comparison against this run is the scorer's job"}
                              if golden
                              else {"status": "NOT_RUN",
                                    "reason": "no golden baseline carrier: the theta=0 regression "
                                    "needs the current shipping build's captures; this run's own "
                                    "zero-roll captures are candidates, never a golden diff"}),
        "render_proof_note": RENDER_PROOF_NOTE,
        "fatal_error": fatal_env,
        "captures": records,
    }
    idx_path = os.path.join(out_dir, "run_roll_capture.index.json")
    tmp = idx_path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(index, f, indent=2, sort_keys=False)
        f.write("\n")
    os.rename(tmp, idx_path)
    log_line("index written: %s (captured=%d errored=%d planned=%d)"
             % (idx_path, captured, errored, len(cells)))
    if captured == 0:
        return 2  # nothing cleanly captured (includes all-cells-shader-error)
    if errored or shader_errored or fatal_env:
        return 3
    return 0


def write_not_run_index(args, message):
    """Machine-readable NOT_RUN index: the scorer consumes it end-to-end even
    when zero cells could be attempted (missing shader, binding, renderer)."""
    try:
        out_dir = os.path.abspath(args.out)
        os.makedirs(os.path.join(out_dir, "captures"), exist_ok=True)
        os.makedirs(os.path.join(out_dir, "logs"), exist_ok=True)
        records = []
        plan = []
        try:
            _, fixtures = load_manifest(args.manifest)
            plan = build_plan(fixtures)
        except Exception:
            fixtures = []
        for cell in plan:
            records.append({"capture_id": cell.capture_id, "fixture_id": cell.fixture_id,
                            "fixture_sha256": cell.fixture.get("sha256"), "mode": cell.kind,
                            "roll_deg": cell.roll_deg, "roll_rad": round(cell.roll_rad, 6),
                            "crossed": cell.crossed, "zero_roll_baseline": cell.baseline,
                            "pose_message": None, "effective_options": None,
                            "shader_slot": None,
                            "shader_sha256": None, "renderer_class": "unavailable",
                            "status": "not_run", "error": message, "image": None,
                            "acceptance_class": "not_run",
                            "golden": {"bound": False, "golden_sha256": None, "golden_path": None},
                            "option_receipt": None,
                            "shader_errors": None,
                            "sync": None, "command": None, "timings": {}})
        shader_sha = sha256_file(args.shader) if args.shader and os.path.isfile(args.shader) else None
        doc = {
            "schema": SCHEMA, "created_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "runner": {"name": "run_roll_capture.py", "version": RUNNER_VERSION,
                       "sha256": sha256_file(os.path.abspath(__file__))},
            "environment": {"evidence_class": "synthetic-linux", "clean_checkout": False,
                            "toolchain": {"python3": sys.version.split()[0]},
                            "renderer_class": "unavailable", "renderer_string": None},
            "source": {"repo": PIN_REPO, "commit": PIN_COMMIT, "path": PIN_PATH,
                       "expected_sha256": None, "actual_sha256": shader_sha,
                       "git_blob_sha1": None, "binding_status": "missing",
                       "provenance": args.provenance,
                       "provenance_assertion": "issuer-asserted; unverified"},
            "fixtures_manifest": {"schema": MANIFEST_SCHEMA,
                                  "path": os.path.abspath(args.manifest) if args.manifest else None,
                                  "sha256": sha256_file(args.manifest) if args.manifest and os.path.isfile(args.manifest) else None},
            "planned_cells": len(records), "captured": 0, "errored": 0,
            "shader_errored": 0, "not_run": len(records),
            "complete": False, "acceptance_evidence": False,
            "golden_comparison": {"status": "NOT_RUN", "reason": "run never started"},
            "render_proof_note": RENDER_PROOF_NOTE,
            "fatal_error": message,
            "captures": records,
        }
        idx = os.path.join(out_dir, "run_roll_capture.index.json")
        with open(idx + ".tmp", "w") as f:
            json.dump(doc, f, indent=2)
            f.write("\n")
        os.rename(idx + ".tmp", idx)
        log_line("NOT_RUN index written: %s (%d planned cells)" % (idx, len(records)))
    except Exception as e:
        log_line("additionally failed to write NOT_RUN index: %s" % e)


def main(argv=None):
    ap = argparse.ArgumentParser(description="191c R4 production-input mpv roll capture runner")
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--fixtures-dir")
    ap.add_argument("--shader", required=True)
    ap.add_argument("--binding", help="roll-source-binding/v1 JSON for the pinned shader")
    ap.add_argument("--allow-unbound-smoke", action="store_true",
                    help="run without a verified pin binding; every record is smoke_not_evidence")
    ap.add_argument("--provenance", help="required with --allow-unbound-smoke: names the unbound source")
    ap.add_argument("--golden", help="roll-golden-baseline/v1 JSON binding the theta=0 regression "
                    "to the current shipping build; without it the golden comparison is NOT_RUN")
    ap.add_argument("--mpv", default=shutil.which("mpv") or "mpv")
    ap.add_argument("--out", required=True)
    ap.add_argument("--timeout", type=float, default=20.0, help="per-sync timeout seconds")
    ap.add_argument("--only", action="append", help="substring filter for capture_ids (repeatable)")
    args = ap.parse_args(argv)
    try:
        rc = run(args)
    except RunnerError as e:
        log_line("NOT_RUN: %s" % e)
        write_not_run_index(args, str(e))
        return 2
    return rc


if __name__ == "__main__":
    sys.exit(main())

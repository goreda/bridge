# W-gdb-021 scripted loopback HTTP edge-case server kit
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-021

```packet-json
{
  "packet_id": "W-gdb-021",
  "writer": "gdb",
  "code_owner": "gdb integrator (gorav lane)",
  "product_repo": "goreda/gorav",
  "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
  "touched_files": [
    {
      "path": "Sources/remote-source-tests/main.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "ScenarioServer(scenario: String, ...); one typed switch per scenario + request log",
    "types": "9 scenario kinds: dribble, trickled headers, range honored/ignored/partial, redirect chains/loops, chunked/gzip, content-length mismatch, drop mid-body, slow EOF",
    "ownership_lifetime": "subprocess server; loopback only; no external endpoints, no credentials",
    "caller": "rows 54/61/62/64 transport test suites",
    "callee": "kit scenario API (python stdlib): dribble/trickle/range/redirect/chunked/gzip/length-mismatch/drop/slow-EOF, one typed switch each + request log"
  },
  "test": {
    "command": "python3 kits/loopback-server/selftest.py",
    "expected": "exit 0; stdout 'loopback-server selftest: 9/9 scenarios PASS'; a scenario switch produces exactly its scripted behavior shown in the request log",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "kits/loopback-server/"
    ],
    "return_form": "full-files"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "kits/loopback-server/kit.py",
        "block": "rf1"
      },
      {
        "path": "kits/loopback-server/selftest.py",
        "block": "rf2"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
    "command": "python3 kits/loopback-server/selftest.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:05:12.466140+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "loopback-server selftest: 9/9 scenarios PASS",
    "inline_files": [
      {
        "path": "kits/loopback-server/kit.py",
        "block": "rf1",
        "sha256": "4026ab3927f8558379297dcd6438a559d489ae8439215f758edfa744f783267a"
      },
      {
        "path": "kits/loopback-server/selftest.py",
        "block": "rf2",
        "sha256": "4bd7d264fa4f1ee0ba38b0b3a104c7502df2c98a54b7e8111bf374652810c2aa"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "10af36ab730f04641447557d5587be24bf34f144d643a7229f51a34320e71a2d",
    "last_5_lines": [
      "PASS gzip (298B wire -> 1024B decoded, wire bytes reproducible)",
      "PASS length-mismatch (declared 1024B, got 768B then EOF)",
      "PASS drop-mid-body (connection dropped after 512/1024B)",
      "PASS slow-eof (terminating chunk held 0.40s)",
      "loopback-server selftest: 9/9 scenarios PASS"
    ],
    "receipt_sha256": "6287b69589eaa5b64c3624625873e801eb8ce3a704296114c60a742d4010535a"
  }
}
```

## problem (what fails for the user)
rows 54/61/62/64 (remote audio/video open, transport snapshots) each spawn ad-hoc python loopback servers; there is no shared scripted edge-case server, so edge behaviors (dribble, range, drop mid-body) are covered unevenly and new remote code ships untested against them.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: Sources/remote-source-tests/main.swift (sha256 b7bfea62) - one of the ad-hoc servers to unify; scripts/ci/native-harness-map-195b.md (same pin) - the four rows that need the kit.
- real test command: swift run remote-source-tests (13 PASS on Linux with the http/tcp kit).

## expected behaviour
a python-stdlib-only scripted server kit: dribbled bodies, trickled headers, range honored/ignored/partial, redirect chains/loops, chunked/gzip, content-length mismatch, drop mid-body, slow EOF; each scenario behind one typed switch with a request log; reusable by any client transport test.

## exact call site and interface
the kit's scenario API is the deliverable; the pinned suite shows the consumer pattern.

## behaviour that must not change
the existing 13+23+5+16 checks across the four rows stay green; loopback only - no external endpoints, no credentials.

## acceptance test (from the product repo)
the kit replays every existing loopback leg green plus its new scenarios; a scenario switch produces exactly its scripted behavior (request log shown).

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/remote-source-tests/main.swift (sha256 b7bfea62, lines 1-60 of 115)
```swift id=source1
import Foundation
import GorAVCore
import GorAVFFmpegAdapter

// R3 (arch-195b) witness: remote (http) source open with headers/cookies,
// redaction, and refusal without credentials. Local python http server
// requires a header AND a cookie; serves a PCM wav (stream-friendly probe).

var failures = 0
func check(_ name: String, _ ok: Bool, _ info: String = "") {
    print((ok ? "PASS " : "FAIL ") + name + (ok || info.isEmpty ? "" : " \(info)"))
    if !ok { failures += 1 }
}

// U-series: redaction and option summary (pure)
check("U1 userinfo redacted", URLRedaction.redact("http://user:secret@example.com/a.wav") == "REDACTED")
check("U2 query values and keys redacted", URLRedaction.redact("https://h/p?token=abc&x=1") == "REDACTED")
check("U3 fragment and path redacted", URLRedaction.redact("http://h/secret#frag") == "REDACTED")
check("U4 local path not exposed", URLRedaction.redact("/plain/path.wav") == "REDACTED")
check("U6 malformed credential redacted", URLRedaction.redact("http://user:slash/secret@host/p?bareSecret") == "REDACTED")
check("U7 encoded credential redacted", URLRedaction.redact("http://%73ecret@host/%74oken?%73ecret") == "REDACTED")
check("U5 summary counts only", SourceOpenOptions(headers: ["Authorization": "s3cr3t"], cookies: ["k": "v"]).redactedSummary == "headers=1 cookies=1 deadline=none")

// S-series: live http open through the admitted remote path
let root = ProcessInfo.processInfo.environment["GORAV_REPO"] ?? FileManager.default.currentDirectoryPath
let fixture = root + "/fixtures/tone-48k.wav"
let tmp = NSTemporaryDirectory() + "r3srv-\(UUID().uuidString)"
try! FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
let serverPy = tmp + "/server.py"
let portFile = tmp + "/port"
let script = """
import http.server, sys, threading
fixture = sys.argv[1]
portfile = sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.headers.get('X-GorAV-Test') != 'yes' or ('session=abc' not in (self.headers.get('Cookie') or '') or 'other=def' not in (self.headers.get('Cookie') or '')):
            self.send_response(403); self.end_headers(); return
        with open(fixture, 'rb') as fh: data = fh.read()
        self.send_response(200)
        self.send_header('Content-Type', 'audio/wav')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Accept-Ranges', 'bytes')
        self.end_headers()
        self.wfile.write(data)
    def log_message(self, *a): pass
srv = http.server.ThreadingHTTPServer(('127.0.0.1', 0), H)
with open(portfile, 'w') as fh: fh.write(str(srv.server_address[1]))
srv.serve_forever()
"""
try! script.write(toFile: serverPy, atomically: true, encoding: .utf8)
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
proc.arguments = [serverPy, fixture, portFile]
try! proc.run()
var port: String? = nil
for _ in 0..<200 {
    if let p = try? String(contentsOfFile: portFile, encoding: .utf8), !p.isEmpty { port = p.trimmingCharacters(in: .whitespacesAndNewlines); break }
    try? await Task.sleep(nanoseconds: 50_000_000)
}
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```python id=fixtures1
from kit import ScenarioServer
srv = ScenarioServer(scenario="range-honored", dribble=None)
# GET /clip -> 200 full; GET with Range: bytes=100- -> 206 partial; request log records every hop
```

```text id=rf1
"""W-gdb-021: scripted loopback HTTP edge-case server kit.

Python stdlib only. IPv4 loopback only (127.0.0.1); no external
endpoints, no credentials. One typed switch per scenario plus a
request log.

Nine scenario kinds, twelve typed switches:

    kind                   switches
    dribble                dribble
    trickled headers       trickle-headers
    range                  range-honored, range-ignored, range-partial
    redirect               redirect-chain, redirect-loop
    chunked                chunked
    gzip                   gzip
    content-length mismatch length-mismatch
    drop mid-body          drop-mid-body
    slow EOF               slow-eof

Range semantics (range-honored / range-partial): satisfiable ranges
(including suffix form bytes=-N) get 206; unsatisfiable ranges
(start beyond body, reversed span) get 416 with
Content-Range: bytes */<size>; syntactically invalid ranges get 400.
range-ignored always serves 200 full, whatever the Range header.

gzip wire bytes are deterministic (gzip.compress with mtime=0).

Usage:
    from kit import ScenarioServer
    srv = ScenarioServer(scenario="range-honored", dribble=None)
    # GET srv.url + "/clip" -> 200 full
    # GET with Range: bytes=100- -> 206 partial
    # srv.request_log records every hop
    srv.close()
"""

import gzip as _gzip
import http.server
import math
import threading
import time

KINDS = {
    "dribble": ("dribble",),
    "trickled-headers": ("trickle-headers",),
    "range": ("range-honored", "range-ignored", "range-partial"),
    "redirect": ("redirect-chain", "redirect-loop"),
    "chunked": ("chunked",),
    "gzip": ("gzip",),
    "length-mismatch": ("length-mismatch",),
    "drop-mid-body": ("drop-mid-body",),
    "slow-eof": ("slow-eof",),
}
SCENARIOS = tuple(s for group in KINDS.values() for s in group)

DEFAULT_BODY = bytes(i % 256 for i in range(1024))

_REDIRECT_CHAIN = {"/start": "/hop1", "/hop1": "/hop2", "/hop2": "/final"}
_REDIRECT_LOOP = {"/a": "/b", "/b": "/a"}


def _ascii_digits(s):
    # HTTP range components are ASCII decimal digits only: int() would
    # otherwise accept "+1", "1_0" and non-ASCII digits.
    return s != "" and s.isascii() and s.isdigit()


def _parse_range(rng, size):
    """Parse a single bytes range against a body of `size` bytes.

    Returns (start, end) inclusive, or the strings "invalid"
    (syntactically bad) / "unsatisfiable" (well-formed but cannot be
    satisfied, including any range against an empty body).
    """
    if not rng.startswith("bytes="):
        return "invalid"
    start_s, sep, end_s = rng[len("bytes="):].partition("-")
    if not sep:
        return "invalid"
    if start_s == "":
        # Suffix form: bytes=-N means the last N bytes.
        if not _ascii_digits(end_s):
            return "invalid"
        n = int(end_s)
        if n <= 0 or size == 0:
            return "unsatisfiable"
        if n >= size:
            return (0, size - 1)
        return (size - n, size - 1)
    if not _ascii_digits(start_s):
        return "invalid"
    if end_s != "" and not _ascii_digits(end_s):
        return "invalid"
    if size == 0:
        return "unsatisfiable"
    start = int(start_s)
    end = int(end_s) if end_s else size - 1
    end = min(end, size - 1)
    if start > end or start >= size:
        return "unsatisfiable"
    return (start, end)


class _Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass  # script-log only; keep stderr clean for harness output

    # -- plumbing ----------------------------------------------------
    def _record(self, status, note="", bytes_sent=0):
        srv = self.server
        rec = {
            "ts": time.time(),
            "method": self.command,
            "path": self.path,
            "range": self.headers.get("Range"),
            "status": status,
            "bytes_sent": bytes_sent,
            "note": note,
            "scenario": srv.scenario,
        }
        with srv.log_lock:
            rec["seq"] = len(srv.request_log)
            srv.request_log.append(rec)

    def _empty(self, status, note, extra_headers=()):
        self._record(status, note)
        self.send_response(status)
        for k, v in extra_headers:
            self.send_header(k, v)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _not_found(self):
        self._empty(404, "unknown path for scenario %r" % self.server.scenario)

    def _redirect(self, location):
        self._empty(302, "redirect -> %s" % location, (("Location", location),))

    def do_GET(self):
        fn = getattr(self, "_scenario_" + self.server.scenario.replace("-", "_"), None)
        if fn is None:
            self._record(500, "no handler for scenario")
            return
        fn()

    # -- scenarios ---------------------------------------------------
    def _scenario_dribble(self):
        if self.path != "/body":
            return self._not_found()
        body = self.server.body
        chunk, delay = self.server.dribble
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self._record(200, "dribbling %dB as %dB chunks with %.3fs delay"
                     % (len(body), chunk, delay), len(body))
        for off in range(0, len(body), chunk):
            piece = body[off:off + chunk]
            self.wfile.write(piece)
            self.wfile.flush()
            if off + chunk < len(body):
                time.sleep(delay)

    def _scenario_trickle_headers(self):
        if self.path != "/headers":
            return self._not_found()
        body = self.server.body
        delay = self.server.header_delay
        headers = [
            ("Content-Type", "application/octet-stream"),
            ("Content-Length", str(len(body))),
            ("X-Trickle", "yes"),
            ("Connection", "close"),
        ]
        # Raw writes so each header line is flushed separately.
        self.wfile.write(b"HTTP/1.1 200 OK\r\n")
        self.wfile.flush()
        for k, v in headers:
            self.wfile.write(("%s: %s\r\n" % (k, v)).encode())
            self.wfile.flush()
            time.sleep(delay)
        self.wfile.write(b"\r\n")
        self._record(200, "trickled %d headers at %.3fs each"
                     % (len(headers), delay), len(body))
        self.wfile.write(body)
        self.wfile.flush()
        self.close_connection = True

    def _serve_clip(self, mode):
        if self.path != "/clip":
            return self._not_found()
        body = self.server.body
        rng = self.headers.get("Range")
        if rng and mode != "ignored":
            parsed = _parse_range(rng, len(body))
            if parsed == "invalid":
                return self._empty(400, "invalid range %r" % rng)
            if parsed == "unsatisfiable":
                return self._empty(416, "unsatisfiable range %r" % rng,
                                   (("Content-Range", "bytes */%d" % len(body)),))
            start, end = parsed
            if mode == "partial":
                # Honor the start but return only half the requested span.
                span = end - start + 1
                end = start + max(span // 2, 1) - 1
            part = body[start:end + 1]
            self.send_response(206)
            self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, len(body)))
            self.send_header("Content-Length", str(len(part)))
            self.send_header("Accept-Ranges", "bytes")
            self.end_headers()
            self._record(206, "range %s: %s" % (mode, rng), len(part))
            self.wfile.write(part)
            return
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        note = "full body"
        if rng:
            note = "range %r ignored; full body" % rng
        self._record(200, note, len(body))
        self.wfile.write(body)

    def _scenario_range_honored(self):
        self._serve_clip("honored")

    def _scenario_range_ignored(self):
        self._serve_clip("ignored")

    def _scenario_range_partial(self):
        self._serve_clip("partial")

    def _scenario_redirect_chain(self):
        if self.path in _REDIRECT_CHAIN:
            return self._redirect(_REDIRECT_CHAIN[self.path])
        if self.path == "/final":
            body = self.server.body
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self._record(200, "chain terminal", len(body))
            self.wfile.write(body)
            return
        self._not_found()

    def _scenario_redirect_loop(self):
        if self.path in _REDIRECT_LOOP:
            return self._redirect(_REDIRECT_LOOP[self.path])
        self._not_found()

    def _write_chunked(self, body, eof_delay=0.0, note=""):
        self.send_response(200)
        self.send_header("Transfer-Encoding", "chunked")
        self.send_header("Content-Type", "application/octet-stream")
        self.end_headers()
        sent = 0
        nchunks = 0
        for off in range(0, len(body), 256):
            piece = body[off:off + 256]
            self.wfile.write(("%x\r\n" % len(piece)).encode() + piece + b"\r\n")
            self.wfile.flush()
            sent += len(piece)
            nchunks += 1
        self._record(200, note, sent)
        if eof_delay:
            time.sleep(eof_delay)
        self.wfile.write(b"0\r\n\r\n")
        self.wfile.flush()
        return sent, nchunks

    def _scenario_chunked(self):
        if self.path != "/body":
            return self._not_found()
        nchunks = (len(self.server.body) + 255) // 256
        self._write_chunked(self.server.body,
                            note="chunked: %d data chunks + terminator" % nchunks)

    def _scenario_gzip(self):
        if self.path != "/body":
            return self._not_found()
        # mtime=0: wire bytes are deterministic across runs.
        comp = _gzip.compress(self.server.body, mtime=0)
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Encoding", "gzip")
        self.send_header("Content-Length", str(len(comp)))
        self.end_headers()
        self._record(200, "gzip: %dB -> %dB" % (len(self.server.body), len(comp)), len(comp))
        self.wfile.write(comp)

    def _scenario_length_mismatch(self):
        if self.path != "/body":
            return self._not_found()
        body = self.server.body
        short = body[: len(body) * 3 // 4]
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))  # claims full
        self.end_headers()
        self._record(200, "declared %dB, sent %dB, closed" % (len(body), len(short)), len(short))
        self.wfile.write(short)
        self.wfile.flush()
        self.close_connection = True

    def _scenario_drop_mid_body(self):
        if self.path != "/body":
            return self._not_found()
        body = self.server.body
        quarter = len(body) // 4
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body[:quarter])
        self.wfile.flush()
        time.sleep(0.05)
        self._record(200, "dropped mid-body after %d/%dB" % (quarter * 2, len(body)), quarter * 2)
        self.wfile.write(body[quarter:quarter * 2])
        self.wfile.flush()
        # Abrupt abort halfway through the declared body.
        self.close_connection = True

    def _scenario_slow_eof(self):
        if self.path != "/body":
            return self._not_found()
        delay = self.server.slow_eof_delay
        self._write_chunked(self.server.body, eof_delay=delay,
                            note="slow EOF: terminating chunk delayed %.3fs" % delay)


def _check_nonnegative_finite(name, value):
    if not isinstance(value, (int, float)) or isinstance(value, bool) \
            or not math.isfinite(value) or value < 0:
        raise ValueError("%s must be a non-negative finite number, got %r" % (name, value))


class ScenarioServer:
    """Loopback-only scripted HTTP server for one scenario.

    scenario: one of SCENARIOS (typed switch).
    dribble:  None for the default (16-byte chunks, 50ms), or a
              (chunk_bytes, delay_seconds) tuple; chunk_bytes must be a
              positive int, delay_seconds a non-negative finite number.
              Applies to the dribble scenario; other scenarios ignore it.
    host:     IPv4 loopback only; anything but 127.0.0.1 is refused.
    """

    def __init__(self, scenario, dribble=None, host="127.0.0.1", port=0,
                 body=DEFAULT_BODY, header_delay=0.05, slow_eof_delay=0.4):
        if scenario not in SCENARIOS:
            raise ValueError("unknown scenario %r; expected one of %s"
                             % (scenario, ", ".join(SCENARIOS)))
        if host != "127.0.0.1":
            raise ValueError("IPv4 loopback only: host must be 127.0.0.1, got %r" % (host,))
        self.scenario = scenario
        self.dribble = tuple(dribble) if dribble is not None else (16, 0.05)
        chunk, delay = self.dribble
        if not isinstance(chunk, int) or isinstance(chunk, bool) or chunk <= 0:
            raise ValueError("dribble chunk_bytes must be a positive int, got %r" % (chunk,))
        _check_nonnegative_finite("dribble delay_seconds", delay)
        _check_nonnegative_finite("header_delay", header_delay)
        _check_nonnegative_finite("slow_eof_delay", slow_eof_delay)
        httpd = http.server.ThreadingHTTPServer((host, port), _Handler)
        httpd.daemon_threads = True
        httpd.scenario = scenario
        httpd.body = bytes(body)
        httpd.dribble = self.dribble
        httpd.header_delay = header_delay
        httpd.slow_eof_delay = slow_eof_delay
        httpd.request_log = []
        httpd.log_lock = threading.Lock()
        self._httpd = httpd
        self._thread = threading.Thread(
            target=httpd.serve_forever, kwargs={"poll_interval": 0.05}, daemon=True)
        self._thread.start()

    @property
    def port(self):
        return self._httpd.server_address[1]

    @property
    def url(self):
        return "http://127.0.0.1:%d" % self.port

    @property
    def request_log(self):
        with self._httpd.log_lock:
            return list(self._httpd.request_log)

    def close(self):
        self._httpd.shutdown()
        self._httpd.server_close()
        self._thread.join(timeout=2)

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()

```

```text id=rf2
"""W-gdb-021 selftest: exercises all 9 loopback-server scenario kinds,
including negative assertions for invalid ranges, bad constructor
parameters, non-loopback hosts, and gzip wire determinism.

Run from the repo root:  python3 kits/loopback-server/selftest.py
Exit 0 with 'loopback-server selftest: 9/9 scenarios PASS' when every
scenario switch produces exactly its scripted behavior.
"""

import gzip
import http.client
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kit import DEFAULT_BODY, SCENARIOS, ScenarioServer  # noqa: E402

BODY = DEFAULT_BODY
TIMEOUT = 15


def _get(srv, path, headers=None):
    conn = http.client.HTTPConnection("127.0.0.1", srv.port, timeout=TIMEOUT)
    conn.request("GET", path, headers=headers or {})
    return conn, conn.getresponse()


def _expect_valueerror(fn, what):
    try:
        fn()
    except ValueError:
        return
    raise AssertionError("expected ValueError for %s" % what)


def t_dribble():
    chunk, delay = 64, 0.02
    # Kit surface: 9 kinds, 12 typed switches.
    assert len(SCENARIOS) == 12, len(SCENARIOS)
    # Constructor guards: bad dribble params and non-loopback hosts refuse.
    for bad in [(0, 0.1), (-4, 0.1), (16, -0.1), (16, float("nan")),
                (16, float("inf")), (True, 0.1), (16.5, 0.1)]:
        _expect_valueerror(lambda b=bad: ScenarioServer(scenario="dribble", dribble=b),
                           "dribble=%r" % (bad,))
    for bad_host in ["::1", "localhost", "0.0.0.0", "example.com"]:
        _expect_valueerror(lambda h=bad_host: ScenarioServer(scenario="dribble", host=h),
                           "host=%r" % (bad_host,))
    _expect_valueerror(lambda: ScenarioServer(scenario="dribble", header_delay=-1),
                       "header_delay=-1")
    _expect_valueerror(lambda: ScenarioServer(scenario="dribble", slow_eof_delay=float("nan")),
                       "slow_eof_delay=nan")
    with ScenarioServer(scenario="dribble", dribble=(chunk, delay)) as srv:
        start = time.monotonic()
        conn, r = _get(srv, "/body")
        data = r.read()
        elapsed = time.monotonic() - start
        conn.close()
        assert r.status == 200, r.status
        assert int(r.headers["Content-Length"]) == len(BODY)
        assert data == BODY, "body corrupted"
        min_time = (len(BODY) // chunk - 2) * delay
        assert elapsed >= min_time, "not dribbled: %.3fs < %.3fs" % (elapsed, min_time)
        log = srv.request_log
        assert len(log) == 1 and log[0]["path"] == "/body" and log[0]["status"] == 200
        return "(%dB in %dB chunks, %.2fs; 11 constructor guards)" % (len(BODY), chunk, elapsed)


def t_trickle_headers():
    with ScenarioServer(scenario="trickle-headers", header_delay=0.05) as srv:
        start = time.monotonic()
        conn, r = _get(srv, "/headers")
        data = r.read()
        elapsed = time.monotonic() - start
        conn.close()
        assert r.status == 200, r.status
        assert r.headers["X-Trickle"] == "yes"
        assert data == BODY
        assert elapsed >= 0.15, "headers not trickled: %.3fs" % elapsed
        assert srv.request_log[0]["status"] == 200
        return "(4 headers over %.2fs)" % elapsed


def t_range():
    def fetch(srv, rng=None):
        conn, r = _get(srv, "/clip", {"Range": rng} if rng else {})
        data = r.read()
        status, cr = r.status, r.headers.get("Content-Range")
        conn.close()
        return status, cr, data

    with ScenarioServer(scenario="range-honored", dribble=None) as srv:
        status, cr, full = fetch(srv)
        assert status == 200 and full == BODY
        status, cr, part = fetch(srv, "bytes=100-")
        assert status == 206 and cr == "bytes 100-1023/1024", (status, cr)
        assert part == BODY[100:]
        # Suffix form: last 100 bytes.
        status, cr, part = fetch(srv, "bytes=-100")
        assert status == 206 and cr == "bytes 924-1023/1024", (status, cr)
        assert part == BODY[-100:]
        # Suffix larger than body clamps to the whole body.
        status, cr, part = fetch(srv, "bytes=-9999")
        assert status == 206 and cr == "bytes 0-1023/1024" and part == BODY, (status, cr)
        # Out of range and reversed: no malformed 206, a typed 416.
        for bad in ["bytes=9999-", "bytes=200-100", "bytes=1024-1024"]:
            status, cr, data = fetch(srv, bad)
            assert status == 416, (bad, status)
            assert cr == "bytes */1024", (bad, cr)
            assert data == b""
        # Syntactically invalid: typed 400, not a guess. int() would
        # accept "+1", "1_0" and non-ASCII digits; HTTP syntax does not.
        # (Non-ASCII digits are also refused by the kit's ASCII check, but
        # http.client cannot encode them into a header to send them.)
        for bad in ["bytes=abc-", "items=0-10", "bytes=100", "bytes=1-2-3",
                    "bytes=+1-2", "bytes=1_0-", "bytes=-+4"]:
            status, cr, data = fetch(srv, bad)
            assert status == 400, (bad, status)
        log = srv.request_log
        assert [e["status"] for e in log] == [200, 206, 206, 206, 416, 416, 416] + [400] * 7, \
            [e["status"] for e in log]
    with ScenarioServer(scenario="range-honored", body=b"") as srv:
        # Empty body: every well-formed range is unsatisfiable; no
        # suffix arithmetic may produce Content-Range like bytes 0--1/0.
        status, cr, data = fetch(srv)
        assert status == 200 and data == b"", (status, data)
        for rng in ["bytes=-1", "bytes=0-", "bytes=0-0"]:
            status, cr, data = fetch(srv, rng)
            assert status == 416, (rng, status)
            assert cr == "bytes */0", (rng, cr)
            assert data == b""
    with ScenarioServer(scenario="range-ignored") as srv:
        # Ignores Range entirely, even garbage.
        for rng in ["bytes=100-", "bytes=9999-", "bytes=nonsense"]:
            status, cr, data = fetch(srv, rng)
            assert status == 200 and data == BODY and cr is None, (rng, status)
    with ScenarioServer(scenario="range-partial") as srv:
        status, cr, data = fetch(srv, "bytes=100-")
        assert status == 206 and cr == "bytes 100-561/1024", (status, cr)
        assert data == BODY[100:562] and len(data) < len(BODY[100:])
        status, cr, data = fetch(srv, "bytes=9999-")
        assert status == 416 and cr == "bytes */1024", (status, cr)
    return "(206 honored/suffix/clamped, 416 unsatisfiable+empty-body, 400 non-digit syntax, ignored 200, partial 206+416)"


def t_redirect():
    with ScenarioServer(scenario="redirect-chain") as srv:
        path = "/start"
        hops = []
        for _ in range(3):
            conn, r = _get(srv, path)
            r.read()
            hops.append((path, r.status))
            path = r.headers["Location"]
            conn.close()
        assert [s for _, s in hops] == [302, 302, 302], hops
        assert path == "/final", path
        conn, r = _get(srv, path)
        data = r.read()
        assert r.status == 200 and data == BODY
        conn.close()
        log_paths = [e["path"] for e in srv.request_log]
        assert log_paths == ["/start", "/hop1", "/hop2", "/final"], log_paths
    with ScenarioServer(scenario="redirect-loop") as srv:
        path = "/a"
        seen = []
        for _ in range(4):
            conn, r = _get(srv, path)
            r.read()
            assert r.status == 302, (path, r.status)
            seen.append(path)
            path = r.headers["Location"]
            conn.close()
        assert seen == ["/a", "/b", "/a", "/b"], seen
        assert path == "/a", "loop did not persist"
        assert len(srv.request_log) == 4
    return "(chain /start->/hop1->/hop2->/final; loop /a<->/b held 4 hops)"


def t_chunked():
    with ScenarioServer(scenario="chunked") as srv:
        conn, r = _get(srv, "/body")
        data = r.read()
        conn.close()
        assert r.status == 200
        assert r.headers["Transfer-Encoding"] == "chunked"
        assert data == BODY, "chunked reassembly wrong"
        assert srv.request_log[0]["bytes_sent"] == len(BODY)
        return "(4 data chunks + terminator, %dB reassembled)" % len(data)


def t_gzip():
    with ScenarioServer(scenario="gzip") as srv:
        wire = []
        for _ in range(2):
            conn, r = _get(srv, "/body")
            data = r.read()
            conn.close()
            assert r.status == 200
            assert r.headers["Content-Encoding"] == "gzip"
            assert gzip.decompress(data) == BODY, "gzip payload wrong"
            wire.append(data)
        # Byte-for-byte reproducible wire bytes (gzip mtime=0).
        assert wire[0] == wire[1], "wire bytes not deterministic"
        return "(%dB wire -> %dB decoded, wire bytes reproducible)" % (len(wire[0]), len(BODY))


def t_length_mismatch():
    with ScenarioServer(scenario="length-mismatch") as srv:
        conn, r = _get(srv, "/body")
        assert int(r.headers["Content-Length"]) == len(BODY)
        try:
            r.read()
            raise AssertionError("expected IncompleteRead")
        except http.client.IncompleteRead as e:
            got = e.partial
        conn.close()
        assert len(got) == len(BODY) * 3 // 4, len(got)
        assert srv.request_log[0]["bytes_sent"] == len(BODY) * 3 // 4
        return "(declared %dB, got %dB then EOF)" % (len(BODY), len(got))


def t_drop_mid_body():
    with ScenarioServer(scenario="drop-mid-body") as srv:
        conn, r = _get(srv, "/body")
        try:
            r.read()
            raise AssertionError("expected IncompleteRead")
        except http.client.IncompleteRead as e:
            got = e.partial
        conn.close()
        assert len(got) == len(BODY) // 2, len(got)
        assert "dropped mid-body" in srv.request_log[0]["note"]
        return "(connection dropped after %d/%dB)" % (len(got), len(BODY))


def t_slow_eof():
    with ScenarioServer(scenario="slow-eof", slow_eof_delay=0.4) as srv:
        start = time.monotonic()
        conn, r = _get(srv, "/body")
        data = r.read()
        elapsed = time.monotonic() - start
        conn.close()
        assert r.status == 200 and data == BODY
        assert r.headers["Transfer-Encoding"] == "chunked"
        assert elapsed >= 0.32, "EOF not delayed: %.3fs" % elapsed
        return "(terminating chunk held %.2fs)" % elapsed


CHECKS = [
    ("dribble", t_dribble),
    ("trickle-headers", t_trickle_headers),
    ("range", t_range),
    ("redirect", t_redirect),
    ("chunked", t_chunked),
    ("gzip", t_gzip),
    ("length-mismatch", t_length_mismatch),
    ("drop-mid-body", t_drop_mid_body),
    ("slow-eof", t_slow_eof),
]


def main():
    passed = 0
    for name, fn in CHECKS:
        try:
            detail = fn()
            print("PASS %s %s" % (name, detail))
            passed += 1
        except Exception as e:
            print("FAIL %s %s: %s" % (name, type(e).__name__, e))
    print("loopback-server selftest: %d/9 scenarios %s"
          % (passed, "PASS" if passed == len(CHECKS) else "FAIL"))
    return 0 if passed == len(CHECKS) else 1


if __name__ == "__main__":
    sys.exit(main())

```

```text id=actual_run_log
PASS dribble (1024B in 64B chunks, 0.30s; 11 constructor guards)
PASS trickle-headers (4 headers over 0.20s)
PASS range (206 honored/suffix/clamped, 416 unsatisfiable+empty-body, 400 non-digit syntax, ignored 200, partial 206+416)
PASS redirect (chain /start->/hop1->/hop2->/final; loop /a<->/b held 4 hops)
PASS chunked (4 data chunks + terminator, 1024B reassembled)
PASS gzip (298B wire -> 1024B decoded, wire bytes reproducible)
PASS length-mismatch (declared 1024B, got 768B then EOF)
PASS drop-mid-body (connection dropped after 512/1024B)
PASS slow-eof (terminating chunk held 0.40s)
loopback-server selftest: 9/9 scenarios PASS
```

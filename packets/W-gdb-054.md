# W-gdb-054 return-to-lab: W-0286/B7 transport kit test_wire startup-race flake (1nstinct) [rev 2]
state: candidate
solver lab: 1nstinct
reviewer lab: gdb integrator (gorav lane)
id: W-gdb-054

```packet-json
{
 "packet_id": "W-gdb-054",
 "writer": "gdb",
 "code_owner": "1nstinct (owning lab, transport allocation)",
 "product_repo": "goreda/gorav",
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
 "scope": "product",
 "touched_files": [
  {"path": "kits/b7-transport-flake/tests/run_e2e.sh", "excerpt_block": "source1"},
  {"path": "kits/b7-transport-flake/tests/test_wire.c", "excerpt_block": "source2"},
  {"path": "kits/b7-transport-flake/gen_mutants.py", "excerpt_block": "source3"}
 ],
 "interface": {
  "signatures": "run_e2e.sh orchestration (source1): python3 synth_server.py $PORT & sleep 1; then e2e_client scenarios + test_wire $PORT; test_wire W1-W6 assertions (source2: W2/W3/W4, the failing sites)",
  "types": "test_wire CHECK(cond) prints FAIL file:line; WIRE RESULT: FAIL (n); e2e E2E RESULT: PASS|FAIL",
  "ownership_lifetime": "synth server process owned by the script (kill at exit); carrier files verbatim from the G0746 archive with CARRIER.sha256",
  "caller": "gorav lane ingest gate (kits/b7-transport-flake/check.py)",
  "callee": "1nstinct w0286 kit (rt_transport + rt_wire_posix + synth_server.py)"
 },
 "test": {
  "command": "cd kits/b7-transport-flake && python3 check.py",
  "expected": "exit 0; stdout 'b7-transport-flake: 4/4 checks PASS' (carrier integrity, build, mutant-A-no-server exactly the 6 observed FAIL sites, mutant-B-fixed-e2e WIRE+E2E PASS)",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": ["kits/b7-transport-flake/"],
  "return_form": "patch"
 }
}
```

## problem (what fails)
W-0286/B7 rev2 kit e2e has a startup-race flake observed by the integrator at ingest: first `sh tests/run_e2e.sh` gave WIRE RESULT: FAIL (6), immediate retry passed. This packet returns the kit WITH the failing test executable, not a prose description.

## observed cause vs hypothesis (separated, per gate ruling)
- OBSERVED (reproduced here, mutant A): with nothing listening on the port, tests/test_wire fails at exactly six sites - tests/test_wire.c:49, 61, 66 (W2/W3 server fetches), 75, 77, 82 (W4) - and prints WIRE RESULT: FAIL (6). W1 and both connect-bounds checks pass without a server. The six-site signature of the original flake and of the no-server run are identical.
- HYPOTHESIS (plausible, not proven): the original first-run flake came from the fixed `sleep 1` startup window in run_e2e.sh (source1) expiring before synth_server.py was listening. No port-reuse evidence exists; no second mechanism is claimed.

## carrier pin (verbatim from the G0746 archive, 1nstinct)
kits/b7-transport-flake/ carries src/ + tests/ + Makefile byte-verbatim (CARRIER.sha256 in the kit; run_e2e.sh sha256 3b43b5a1dddf9722cd0b1ca92f1113aaf4f9a65bd8b0b9fa0355d3619f16152d, test_wire.c c90a4d81cc8987d95437ac85a142d69fd5fe6fa7cf959c2cdf63025857d0d3a6, synth_server.py b174dff104e976b39a9f22d9e124dedb44395c07d002f7cc24af8537bd72c37c).

## fix contract for the owning lab
replace the fixed `sleep 1` with a bounded readiness poll on the port (mutant B in gen_mutants.py shows one: 100ms interval, 5.0s deadline, named readiness-timeout error). The kit closes when the upstream run_e2e.sh itself carries the bounded poll and two consecutive runs PASS under host load.

## acceptance test (executable, bounded)
cd kits/b7-transport-flake && python3 check.py exits 0: builds the carrier (gcc), runs mutant A (bounded 60s) expecting exactly the six FAIL sites, generates and runs mutant B (bounded 180s) expecting WIRE+E2E PASS.

## pinned excerpts
### kits/b7-transport-flake/tests/run_e2e.sh (carrier, full file; the fixed `sleep 1` window is the flake locus)
```sh id=source1
#!/bin/sh
# W-0286 e2e: synthetic server + posix-wire client. No real endpoints.
set -u
cd "$(dirname "$0")"
if [ "${RT_SAN:-0}" = 1 ]; then alias_true=1; fi
CLI=./e2e_client; WIRE=./test_wire
if [ "${RT_SAN:-0}" = 1 ]; then CLI=./e2e_client_san; WIRE=./test_wire_san; fi
PORT=8971
python3 synth_server.py $PORT & SRV=$!
sleep 1
F=0
run() { echo "== $*"; "$@" || F=1; }
run $CLI http://127.0.0.1:$PORT/full    full   1048576
run $CLI http://127.0.0.1:$PORT/drop    full   300000
run $CLI http://127.0.0.1:$PORT/dribble full   200000
run $CLI http://127.0.0.1:$PORT/norange full   150000
run $CLI http://127.0.0.1:$PORT/chunked full   120000
run $CLI http://127.0.0.1:$PORT/full    seek   1048576
run $CLI http://127.0.0.1:$PORT/dribble cancel 100000
run $WIRE $PORT
kill $SRV 2>/dev/null
[ $F -eq 0 ] && echo "E2E RESULT: PASS" || echo "E2E RESULT: FAIL"
exit $F
```
### kits/b7-transport-flake/tests/test_wire.c (carrier, lines 41-90: W2/W3/W4 - the six failing assertion sites)
```c id=source2
    {
        RTWire w; rt_wire_posix_open(&w, 2000);
        char url[4200];
        snprintf(url, sizeof url, "http://127.0.0.1:%d/", port);
        size_t base = strlen(url);
        memset(url + base, 'a', 4000); url[base + 4000] = 0;
        RTTransport *t = NULL;
        int rc = rt_open(&t, &w, url, NULL);
        CHECK(rc == RT_ERR_PROTOCOL && t == NULL);
        rt_wire_posix_free(&w);
    }
    /* W3: 3000-char extra header fits -> normal fetch works byte-exact */
    {
        RTWire w; rt_wire_posix_open(&w, 2000);
        static char big[3001]; memset(big, 'H', 2990); big[2990] = 0;
        memcpy(big, "X-Pad: ", 7);
        const char *hdrs[1] = { big };
        RTOptions o = {0}; o.extra_headers = hdrs; o.n_extra_headers = 1;
        char url[64]; snprintf(url, sizeof url, "http://127.0.0.1:%d/norange", port);
        RTTransport *t = NULL;
        CHECK(rt_open(&t, &w, url, &o) == RT_OK);
        uint8_t b[8192]; size_t got = 0; ptrdiff_t n; int okd = 1;
        while ((n = rt_read(t, b, sizeof b)) > 0)
            for (ptrdiff_t i = 0; i < n; i++)
                if (b[i] != (uint8_t)((got++) * 131u + 17u)) okd = 0;
        CHECK(n == 0 && okd && got == 150000);
        rt_close(t);
        rt_wire_posix_free(&w);
    }
    /* W4: bare-LF response lines parse correctly (read_line CR strip fix) */
    {
        RTWire w; rt_wire_posix_open(&w, 2000);
        char url[64]; snprintf(url, sizeof url, "http://127.0.0.1:%d/barelf", port);
        RTTransport *t = NULL;
        CHECK(rt_open(&t, &w, url, NULL) == RT_OK);
        RTCapabilities c; rt_get_capabilities(t, &c);
        CHECK(c.size_known && c.size == 50000);
        uint8_t b[8192]; size_t got = 0; ptrdiff_t n; int okd = 1;
        while ((n = rt_read(t, b, sizeof b)) > 0)
            for (ptrdiff_t i = 0; i < n; i++)
                if (b[i] != (uint8_t)((got++) * 131u + 17u)) okd = 0;
        CHECK(n == 0 && okd && got == 50000);
        rt_close(t);
        rt_wire_posix_free(&w);
    }
    /* W5: connect timeout bounds an unreachable host */
    {
        RTWire w; RTWirePosixConfig cfg = { 500, 300, NULL, NULL };
        rt_wire_posix_open_cfg(&w, &cfg);
        RTTransport *t = NULL;
```
### kits/b7-transport-flake/gen_mutants.py (executable mutant generator, full file)
```python id=source3
#!/usr/bin/env python3
"""gen_mutants.py - W-gdb-054: produce the two executable mutants.

Mutant A (no-server): nothing to generate - check.py runs tests/test_wire
with no synthetic server listening (observed cause of the 6 FAILs).

Mutant B (fix): tests/run_e2e_fix.sh - the carrier run_e2e.sh with the fixed
`sleep 1` startup window replaced by a bounded readiness poll (deadline 5s,
hard fail with a named error), on a distinct port to avoid collisions.
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent
src = (ROOT / "tests" / "run_e2e.sh").read_text()

POLL = (
    "python3 - \"$PORT\" <<'PYEOF'\n"
    "import socket, sys, time\n"
    "port = int(sys.argv[1]); deadline = time.monotonic() + 5.0\n"
    "while True:\n"
    "    s = socket.socket()\n"
    "    try:\n"
    "        s.connect((\"127.0.0.1\", port)); s.close(); break\n"
    "    except OSError:\n"
    "        s.close()\n"
    "        if time.monotonic() > deadline:\n"
    "            print(\"readiness-timeout: synth server not listening after 5.0s\", file=sys.stderr)\n"
    "            sys.exit(2)\n"
    "        time.sleep(0.1)\n"
    "PYEOF\n"
)

if "sleep 1\n" not in src:
    print("carrier run_e2e.sh does not contain the expected `sleep 1` line", file=sys.stderr)
    sys.exit(2)

mutant = src.replace("PORT=8971", "PORT=8973")
mutant = mutant.replace("sleep 1\n", POLL)
out = ROOT / "tests" / "run_e2e_fix.sh"
out.write_text(mutant)
out.chmod(0o755)
print("wrote tests/run_e2e_fix.sh (port 8973, bounded readiness poll 5.0s)")
```


## roles and state
solver lab: 1nstinct. reviewer lab: gdb integrator. Returned with the failing test per arch-196q item 3; the kit stays out of the merge set until the flake closes upstream.

secret scan: clean

```json id=fixtures1
[{"check": "mutant A no-server", "expect": "exactly FAIL tests/test_wire.c:49,61,66,75,77,82 + WIRE RESULT: FAIL (6)"}, {"check": "mutant B fixed e2e", "expect": "WIRE RESULT: PASS + E2E RESULT: PASS, rc 0"}, {"check": "carrier integrity", "expect": "all CARRIER.sha256 entries match"}]
```
